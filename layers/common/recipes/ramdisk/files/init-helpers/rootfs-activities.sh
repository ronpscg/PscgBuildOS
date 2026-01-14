source /init-helpers/rootfs-overlayfs-functions.sh

#
# Mount a rootfs without overlays
#
mount_rootfs() {
	local mountopts=""

	ROOTFS_MOUNT_POINT=$SYSTEM_MOUNT_POINT
	if mkdir -p $ROOTFS_MOUNT_POINT ; then
		hardInfo "Mounting $ROOTFS_MOUNT_LABEL"
		if [ -n "$mountopt_rootfs" ] ; then mountopts="-o $mountopt_rootfs" ; else mountopts="" ; fi
		if ! mount $mountopts LABEL=$ROOTFS_MOUNT_LABEL $ROOTFS_MOUNT_POINT ; then
			error "Failed to mount LABEL=$ROOTFS_MOUNT_LABEL --> $ROOTFS_MOUNT_POINT"
			return 1
		fi
	else
		error "Failed to create rootfs mount point"
		return 1
	fi
}

adjust_overlayfs_parameters_for_testing_flashed_image() {
	if [ ! "$overlayfs" = "true" ] ; then
		return # not overlayfs, image will be tested without overlays anyway
	fi

	case $AB_TEST_IMAGE_OVERLAY_STRATEGY in
		usesystemro)
			# Do note that if the target system is systemd, you will not have a green state if the rootfs is ro!
			info "$FUNCNAME testing flashed image without overlays. Using system as is in read-only mode (systemd might override that unless you provide a kernel parameter)"
			overlayfs=false
			if [ -z "$mountopt_rootfs" ] ; then
				mountopt_rootfs="ro"
			else
				mountopt_rootfs="$mountopt_rootfs,ro"
			fi
			return
			;;
		usesystemrw)
			info "$FUNCNAME testing flashed image without overlays. Using system as is in read-write mode (systemd might override that unless you provide a kernel parameter)"
			overlayfs=false
			if [ -z "$mountopt_rootfs" ] ; then
				mountopt_rootfs="rw"
			else
				mountopt_rootfs="$mountopt_rootfs,rw"
			fi
			return

			;;

		usesystemoverlay)
			# The idea here is to use the overlay as if it were a regular boot. If the strategy imposed deleting
			# the previous overlay
			info "$FUNCNAME using overlay as is"
			;;

		tmpfs*)
			if [ "$overlayfs_partition" = "tmpfs" ] ; then
				return
			fi
			info "$FUNCNAME using tmpfs parameters for upper: $AB_TEST_IMAGE_OVERLAY_STRATEGY"
			export overlayfs_partition=${AB_TEST_IMAGE_OVERLAY_STRATEGY%%,*}
			export overlayfs_tmpfssize=${AB_TEST_IMAGE_OVERLAY_STRATEGY#*,}
			;;
		*)
			# The rest are unsupported. One can use a custome string to use overlays as they are and see what happens
			# this can be useful, e.g. if you want to do updates of the ota code while working on it, as part of testing
			# but you are inside an overlay. Otherwise, seriously, don't provide anything that is not supported unless you really know what you are doing
			warn "Unsupported strategy $AB_TEST_IMAGE_OVERLAY_STRATEGY"
			;;
	esac
}

#
# Decide the system label to mount and use as rootfs for this boot
# this accounts for software update state.
#
# One could also add a next boot label, but we do not handle it in this project (explained in several places in the code w.r.t bootloaders xor kexec, and perhaps will be added)
#
decide_rootfs_label_for_this_boot_attempt() {
	# Set default labels
	if [ -z "${root}" ] ; then
		ROOTFS_MOUNT_LABEL=$SYSTEM_DEFAULT_LABEL
	else
		warn "User provided a root param: $root. Perhaps they are expecting to be using it, but this is unlikely for our system"
		# we do not expect this to be set, but just in case, why not. for now assume they do want to provide an alternate label, which is what we'll set here.
		ROOTFS_MOUNT_LABEL=${root#*=}
	fi
	# Read from state partition if it is properly set up
	if mount_ota_partitions ; then
		if [ "$(get_state)" = "reflashOK" -o "$(get_state)" = "testingReflashedImages" -o "$(get_state)" = "otaCompletedSuccessfully" ] ; then
			# If reflashing seems to be OK but the satate is not idle - we still have to take note of what the next partition is
			# 	check if there are more such states
			hardVerbose "$(get_state): Reflash seems to be OK. ROOTFS_MOUNT_LABEL=$ROOTFS_MOUNT_LABEL and we shall boot into $(get_next_system_partition) or in my script $(tune2fs -l $(get_next_system_partition) | grep volume  | cut -d: -f 2 | tr  -d ' ')"
			ROOTFS_MOUNT_LABEL=$(tune2fs -l $(get_next_system_partition) | grep volume  | cut -d: -f 2 | tr  -d ' ')
			adjust_overlayfs_parameters_for_testing_flashed_image
		else
			hardVerbose "Your software update state is=$(get_state)"
		fi
	else
		warn "This system is not set up yet for flasher state and OTA updates. Will use the default partition scheme"
	fi
	unmount_ota_partitions
}

#
# mount the root filesystem, taking into consideration overlays and fallback strategies
#
do_mount_rootfs() {
	decide_rootfs_label_for_this_boot_attempt
	if  [ "$overlayfs" = "true" ] ; then
		dod_shell mount_rootfs_with_overlayfs
	else
		dod_shell mount_rootfs
	fi
}

#
# sets system_init to the init executable/script if such exists and is executable
#

pre_switch_root_common() {
	local candidate
	local candidates="$init /sbin/init /lib/systemd/systemd"
	system_init=""
	for candidate in $candidates ; do
	    if [ -x "${ROOTFS_MOUNT_POINT}/$candidate" ]; then
	        system_init="$candidate"
	        break
	    fi
	done

	if [ -z "$system_init" ] ; then
		hardError "Failed to find an executable init in $ROOTFS_MOUNT_POINT. Will not switch root"
		return 2
	fi

	call_if_exists bsp_stop_current_audio_activities
	call_if_exists bsp_stop_current_graphics_activities

	# move mount points to free memory used by the "old" rootfs (e.g. initramfs)
	mount -n -o move /sys  ${ROOTFS_MOUNT_POINT}/sys || { error "Failed to move /sys mount" ; return 1 ; }
	mount -n -o move /proc ${ROOTFS_MOUNT_POINT}/proc || { error "Failed to move /proc mount" ; return 1 ; }
	mount -n -o move /tmp  ${ROOTFS_MOUNT_POINT}/tmp || { error "Failed to move /tmp mount" ; return 1 ; }

	# TODO revise all logFiles
	logFile1=$ROOTFS_MOUNT_POINT/tmp/logs/rinit.log . /commonEnv.sh # sourcing again to change the log file

	# Some distros don't like it when /dev is already mounted so avoid mount move for known ones (as per the time of writing this line)
	# You may add your own heuristics if you encounter and debug such errors
	if ! grep -q Debian ${ROOTFS_MOUNT_POINT}/etc/os-release  2>/dev/null ; then
		warn "Also moving /dev mountpoint. If your new rootfs is behaving weird (mostly tty), this might be the reason!"
		mount -n -o move /dev  ${ROOTFS_MOUNT_POINT}/dev || { error "Failed to move /dev mount" ; return 1 ; }
		# TODO: also move /dev/pts if it is mounted
	fi

	# TODO: perhaps unmount other mounts, or perhaps move them as well
	# Unmount all other mounts so that the ram used by
	# the initramfs can be cleared after switch_root
}


# This must be caleld after mount_rootfs succeeded, so careful if you run it out of context
# Do not run this function from any pid other than the one and only real init, pid 1!
# Check if $init exists and is executable

#
# In every step of the process, a failure will revert to a debug shell. The switch_root is the final step
# of the boot, and if it fails, there is nothing to do but stay in recovery mode
#
_switch_root() {
	dod_shell pre_switch_root_common

	# Switch to the new root and execute init or panic upon failure
	hardInfo "Switching root to ${root} mounted on $ROOTFS_MOUNT_POINT and running ${system_init}..."

	if [ "$docker" = "true" ] ; then
		dod_shell pre_switch_root_docker # docker special treatments, see comments. If not running in docker, this does nothing
		# TODO: in docker the TEECMD and logFile2 persisted the reboot. In QEMU they did not and it's probably
		# 		a slip somewhere - leaving this if for now just because of that.
		stop_logging
	fi

	exec switch_root ${ROOTFS_MOUNT_POINT} "${system_init}"

	hardError "Failed to exec switch root due to some empty variable. You are lucky you're just sloppy... (but you should never get here)"
	return 1
}

#
# switch to the "operational"  root filesystem
#
do_switch_root() {
	cd / # just in case, for the unmounts
	if [ "$docker" = "true" ] ; then
		warn "docker: not unmounting the OTA partitions (right before chroot) - this is done only to allow the operational userspace to have a peek at the bind mounts [hmm... and if we use it in a ramdisk scenario, perhaps also update it directly as with the megaapp container attempt]"
	else
		unmount_ota_partitions || warn "OTA partitions were not mounted when trying to unmount them and proceed with ramdisk"
	fi

	stop_logging $INSTALLER_MEDIA_MOUNT_POINT

	if mountpoint $INSTALLER_MEDIA_MOUNT_POINT &> /dev/null ; then
		umount $INSTALLER_MEDIA_MOUNT_POINT || warn "Could not unmount removable media"
	fi

	kill_currently_opened_shell_on_ttys

	info "Switching rootfs $root"

	_switch_root # switch_root is taken... I was tempted to call it SwitchRootImpl... (reference to Android if you may...)

	# This will only be run if the exec above failed
	hardError "Failed to switch root"

	# before switchRoot we closed everything, so now let's reopen
	open_vts
	# Important: here goes the tradeoff of whether we do serial console or the tty. Uncommenting the next line will lead to no ctrl+c behavior (i.e. ctrl+c --> kills the shell)
	# Not uncommenting it will mean that the init task will execute its shell on the serial console, so one needs to know what they are doing to not be surprised, but no job control. I think the cttyhack should enable job control, but this is not the issue - the issue is whether someone has serial access or not.
	# My work for perfecting the mechanisms was interrupted, so I have to leave it as is for the while. Sorry!
	# open_serial_tty
}
