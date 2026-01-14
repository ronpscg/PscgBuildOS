
#
# This is an fsck wrapper, that tells whether to proceed or not after an fsck. It takes into consideration successful fixes, as per fsck
# but this, naturally, does not guarnatee that everything is indeed in tact after a fix.
#
fsck_wrapper_check_by_partition_label() {
	local blockdev=${EMMC_DEVICE}${PARTITION_MARK}$(eval echo \$$(eval echo partition_number_$1))
	# attempt to fsck and retry. if that doesn't work - give up the target mountpoint
	warn "Trying to fsck $blockdev before giving up on LABEL=$1"
	e2fsck -p $blockdev
	case $? in
		0)
			warn "fsck status is OK, so you have another error and your logic will soon fail for it"
			return 0
			;;
		1|2)
			warn "fsck corrected errors and returned with $?"
			return 0
			;;
		*)
			error "fsck returned with $?. you have serious errors that could not be automagically corrected"
			return 2
			;;
	esac
}

#
# This is a wrapper function to mount a lower bas directory partition, and fsck it if it doesn't work immediately
# note that an fsck is not needed if the rootfs is always used as plan, as ro, but if people play with it or it has been
# malformed during its creation, it is give a chance before giving it up
#
# $1 label of the lowerdir base directory
#
mount_overlayed_rootfs_base_as_ro() {
	mkdir -p $OVERLAYFS_MOUNT_POINT_BASE_DIR/$1 || fatalError "Failed to create $OVERLAYFS_MOUNT_POINT_BASE_DIR/$1"
	if mountpoint $OVERLAYFS_MOUNT_POINT_BASE_DIR/$1 ; then
		error "$1 is already mounted: $(mount | grep $1)"
		return 1
	fi

	# try to mount the overlay base, attempting to fix filesystem errors if it fails
	if ! mount LABEL=$1 -o ro $OVERLAYFS_MOUNT_POINT_BASE_DIR/$1 ; then
		error "Failed to mount $1 - no lower directory available"
		if ! fsck_wrapper_check_by_partition_label ; then
			if ! mount LABEL=$1 -o ro $OVERLAYFS_MOUNT_POINT_BASE_DIR/$1 ; then
				error "$FUNCNAME: Could not mount $1 even after fsck"
				return 2
			fi
		fi
	fi
}

#
# This creates the actual structure and does the overall mounting
# $1 overlayfs lowerdir (e.g. a readonly, already mounted partition, or a folder)
# $2 overlayfs upperdir - (a r/w folder, [usually] representing a mounted partition). the overlay and work dir (upperdir/workdir) will be here
#
mount_overlayfs_folders() {
	# If we are here, it means that both the base and overlay filesystems are ready to work with.
	local lowerdir=$1
	local upperdir=$2/upper
	local workdir=$2/work
	local merged=$2/merged

	do_or_die mkdir -p $upperdir $workdir $merged

	if mount -t overlay overlayfs -o lowerdir=$lowerdir,upperdir=$upperdir,workdir=$workdir $merged ; then
		: # all good
	else
		# TODO: may give it another choice for fallback mounting (e.g.: mount tmpfs, or don't use overlayfs at all...)
		hardError "Failed mount the overlayed fs: $merged $upperdir over $lowerdir."
		return 2
	fi
}

#
# Set up an overlayfs structure in a partition associated with label $2, and overlay its designated contents on top of the parition associated by $1
# $1 partition to be used as rootfs - will be mounted as readonly
# $2 partition to be used as the holder of overlays - will be mounted as readwrite - and this will be the partition we will switchroot to
#
# This function is to be used during installations, e.g. for prepopulating the magaappfs. It is pretty much a copy paste of the mountOverlayedRootfs, removing the rollback logic. When the code is integrated, this should be removed and a common path should be made instead
#
# returns:
#	0 for success
# 	1 for a fatal error
#	2 for an error that the caller may decide to recover from
#
#
mount_overlayed_filesystem_by_labels() {
	: ${proceed_after_fsck_fix=true} # if false, a successful fsck would result in error
	: ${overlays_base_workdir=$OVERLAYFS_MOUNT_POINT_BASE_DIR/$2/fsmaterials}
	if [ -z "$1" -o -z "$2" ] ; then
		error "Failed to mount the overlayed rootfs - wrong parameters ($1,$2)"
		return 1
	fi
	hardInfo "Mounting rootfs $1 overlaying $2 on top of it ($debug_mount_overlay_reason)"

	mount_overlayed_rootfs_base_as_ro $1 || return $?

	mkdir -p $OVERLAYFS_MOUNT_POINT_BASE_DIR/$2 || fatalError "Failed to create $OVERLAYFS_MOUNT_POINT_BASE_DIR/$2"
	if mountpoint $OVERLAYFS_MOUNT_POINT_BASE_DIR/$2 ; then
		error "$2 is already mounted: $(mount | grep $2)"
		return 1
	fi

	# Mount the overlay upper/work filesystem holder.
	# If you cannot mount it - try to fsck it, and retry. If that fails, give up on it.
	if ! mount LABEL=$2 $OVERLAYFS_MOUNT_POINT_BASE_DIR/$2 ; then
		if ! fsck_wrapper_check_by_partition_label ; then
			if ! mount LABEL=$2 $OVERLAYFS_MOUNT_POINT_BASE_DIR/$2 ; then
				error "$FUNCNAME: Could not mount $2 even after fsck"
				return 2
			fi
		fi
	fi

	# mount the overlayfs and let the return value propagate to caller
	mount_overlayfs_folders $OVERLAYFS_MOUNT_POINT_BASE_DIR/$1 $overlays_base_workdir
}

#
# The function encapsulate the logic of creating (or reusing) a tmpfs for fallback mounting of the overlayfs upper directory
# $1 tmpfs path
#
create_tmpfs_for_rootfs_overlay() {
	: ${overlayfs_tmpfssize=500M} # this is suppsed to be provided by command line e.g. overlayfs=tmpfs,<size>
	if [ "$1" = "/tmp" ] ; then
		error "You are trying to mount /tmp without mount --move. This means you must take care of it in the switch_root logic!"
	else
		if [ ! -d "$1" ] ; then
			warn "$1 does not exist - creating it and mounting it as tmpfs"
			mkdir $1 || { error "Could not create the overlaytmpfs $1" ; return 1 ; }
		fi
		mount -t tmpfs  tmpfs -o size=$overlayfs_tmpfssize $1 || { error "Could not mount the target overlaytmpfs" ; return 2 ; }
	fi
}

#
# This is educational only: we assume that the reason you want to do something like this, is to see the changes in the rootfs, without
# using another partition. Existing tools will have hard time to work with, although the overlayfs would work, and you will see
# errors e.g., when using ls, like cannot access '/educational-bad-practice/upper': Too many levels of symbolic links"
# since the system is mounted r/w, you will have to remount it again as r/w
#
educational_example_placeholder_overlayfs() {
	return 1 # Uncomment and rebuild to see the educational example

	FALLBACK_DIR_FOR_OVERLAY_MOUNT_FAIL=$OVERLAYFS_MOUNT_POINT_BASE_DIR
	warn "$FALLBACK_DIR_FOR_OVERLAY_MOUNT_FAIL"
	if [ -d "$FALLBACK_DIR_FOR_OVERLAY_MOUNT_FAIL" ] ; then
		warn "Will try to create an overlayfs structure in $FALLBACK_DIR_FOR_OVERLAY_MOUNT_FAIL. Be sure that this is what you were looking for"
		mount -o remount,rw $OVERLAYFS_MOUNT_POINT_BASE_DIR/$1
		overlays_base_workdir=$FALLBACK_DIR_FOR_OVERLAY_MOUNT_FAIL/$1/educational-bad-practice
		if mount_overlayfs_folders $OVERLAYFS_MOUNT_POINT_BASE_DIR/$1 $overlays_base_workdir ; then
			ROOTFS_MOUNT_POINT=$overlays_base_workdir/merged
			warn Hack succeeded. You will get to a shell - exit it, and you will see the resumption of the boot process
			spawn_shell
			return
		else
			fatalError "Failed to run the educational example."
		fi
	fi
}

#
# Common code for creating a tmpfs and mounting it on top of $1 as overlayfs
# $1 rootfs dir. Expected to already be mounted
#
mount_overlayed_tmpfs_over_rootfs_dir() {
	local tmpfsdir=$OVERLAYFS_MOUNT_POINT_BASE_DIR/tmpfsoverlayfs
	overlays_base_workdir=$tmpfsdir/fsmaterials
	if create_tmpfs_for_rootfs_overlay $tmpfsdir ; then
		if mount_overlayfs_folders $1 $overlays_base_workdir ; then
			ROOTFS_MOUNT_POINT=$overlays_base_workdir/merged
			info "Successfully overlayed tmpfs. Using $ROOTFS_MOUNT_POINT as your rootfs"
			return
		else
			error "Failed to use tmpfs as the overlay fs. Unmounting tmpfs to reclaim memory, and falling back if fonciguration allows"
			dod_shell umount $tmpfsdir
		fi
	else
		local rc=$?
		error "Failed to create tmpfs for overlay. falling back if configuration allows"
		return $rc
	fi
}

#
#
# The function implements (an easily comment-outable) fallback to use tmpfs if mounting of the overlayfs fails
# you are strongly encouraged to read the comments about it.
# Obviously,
#
# Your kernel is expected to have CONFIG_OVERLAY_FS=y, although we could easily add a module and install it.
# A potential "debugging" excerpt for class, if it doesn't:
# 	Problem: init:] Failed to mount the overlayed rootfs - wrong parameters (,) ( s )
# 	Explanation: overlayfs is not built in the kernel.
# 	Easy solution: CONFIG_OVERLAY_FS=y -
#	Note: on older kernels you may have to add OVERLAY_FS_REDIRECT_ALWAYS_FOLLOW=y as well.
#
#
mount_rootfs_with_overlayfs() {
	# partition to be used as rootfs - will be mounted as readonly
	local base_label=$ROOTFS_MOUNT_LABEL
	# partition to be used as the holder of overlays - will be mounted as readwrite - and this will be the partition we will switchroot to
	# Important note about the command line: it is not recommended to set overlayfs_partition unless it is tmpfs.
	# So it's actually better to just use overlayfs without an equal sign to use eg. systemrw over system
	local overlay_label=${overlayfs_partition:-$partition_label_system_overlay}


	hardInfo "$FUNCNAME: Overlaying $overlay_label on top of $base_label"

	debug_mount_overlay_reason=switch_root

	dod_shell mkdir -p $OVERLAYFS_MOUNT_POINT_BASE_DIR

	if [ "$overlayfs_partition" = "tmpfs" ] ; then
		mount_overlayed_rootfs_base_as_ro $base_label || return $?
		# Overlay a tmpfs over a filesystem from a backing device
		if mount_overlayed_tmpfs_over_rootfs_dir $OVERLAYFS_MOUNT_POINT_BASE_DIR/$base_label ; then
			# ROOTFS_MOUNT_POINT is already set inside the function so no need to set it again here
			return
		else
			warn "Failed to overlay a tmpfs. Will try a fallback mount strategy if the configuration flags allow it"
		fi
	else
		# Overlay a filesystem from a backing device over a filesystem from a backing device
		mount_overlayed_filesystem_by_labels $base_label $overlay_label
		case $? in
			0)
				ROOTFS_MOUNT_POINT=$overlays_base_workdir/merged
				return
				;;
			1|2)
				warn "Will try a fallback mount strategy if the configuration flags allow it"
				;;
			*)
				fatalError "Failed to verify validity of overlayed partitions"
				;;
		esac

		# About the next line:
		# You can go ahead and use a folder within your own rootfs, if you want to experiment with things, and keep them writable, but other than
		# for educational or troubleshooting purposes, it is not recommended
		educational_example_placeholder_overlayfs && return # Read commments in the function - it should be noop - but you can "enable it"
	fi

	#
	# Important educational warnings:
	#	- if you use /tmp - do not mount --move.  Otherwise, do not use /
	#	- Be very careful if you want to give it /tmp - it is recommended, instead to either modify the mount -o move of /tmp or to create another tmpfs for it
	#
	# Note: in case we use a tmpfs overlay and systemd you should modify x-systemd.device-timeout/x-systemd.mount-timeout, in fstab.
	#       Otherwise, you will wait 90 seconds by default before a failure.

	# Note the if: if overlayfs=tmpfs it means we are falling back from already trying to mount a tmpfs overlayfs
	if [ ! "$overlayfs_partition" = "tmpfs" -a "$ALLOW_FALLBACK_TO_TMPFS_OVERLAY" = "true" ] ; then
		error "Failed to mount $overlay_label - will attempt to use tmpfs as the overlayed directory structure"
		if mount_overlayed_tmpfs_over_rootfs_dir $OVERLAYFS_MOUNT_POINT_BASE_DIR/$base_label ; then
			return
		fi
	fi

	if [ "$ALLOW_FALLBACK_TO_NO_OVERLAY" = "true" ] ; then
		warn "Falling back to mounting without overlays"
		case $FALLBACK_TO_NO_OVERLAY_STRATEGY in
			# Do note that if the target system is systemd, you will not have a green state if the rootfs is ro
			usesystemro)
				warn "Falling back to read-only system with no overlays"
				ROOTFS_MOUNT_POINT=$OVERLAYFS_MOUNT_POINT_BASE_DIR/$base_label
				return
				;;
			usesystemrw)
				warn "Remounting system as rw and falling back to r/w system without overlays"
				ROOTFS_MOUNT_POINT=$OVERLAYFS_MOUNT_POINT_BASE_DIR/$base_label
				dod_shell mount -o remount,rw $ROOTFS_MOUNT_POINT
				return
				;;
			*)
				warn "Falling back to your own strategy. Have mercy!"
				debug "Will run $FALLBACK_TO_NO_OVERLAY_STRATEGY"
				dod_shell eval $FALLBACK_TO_NO_OVERLAY_STRATEGY
				debug "After the custom strategy: target rootf=$ROOTFS_MOUNT_POINT\ndf=\n$(df)\nmount=\n$(mount)blkid=$(blkid). Good luck!"
				return
				;;
			esac
	fi

	fatalError "Could not set up a root filesystem."
}