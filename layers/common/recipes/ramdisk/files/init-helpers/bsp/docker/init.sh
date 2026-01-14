# This is meant to be sourced

#
# Function definitions and activities for a system running in docker. This is a heavy refactoring, TODO, not tested, etc.
#


#
# Setup a fake file (preprovisioned) as a loopback device. This represents the emmc device in the docker emulation, should
# we want to simulate an entire ramdisk sequence (which will be closer to reality outside of docker, but this will help
# other developers, so I bothered to do it)
#
do_docker_emmc_loopback_device_setup() {
	: ${FAKE_LOOPBACK_EMMC_FILE=/fakestuff/fakestorage0}

	if [ ! -f "$FAKE_LOOPBACK_EMMC_FILE" ] ; then
		fatalError "docker: $FAKE_LOOPBACK_EMMC_FILE does not exist. Will not proceed without an internal storage"
	fi
	# This is not really necessary, but on docker over MacOS, the kernel keeps the mounts.
	# If we *KNOW* that we don't want the other loopbacks, clean them up before we start
	# (this may, and will interfere with other dockers instances!)
	# busybox fdisk sort of always returns 0 for -l so we'll just do something dumb / or assume we cleanup only
	# partitions we know we created (Problem is that with MacOS we would need to prepopulate the partitions prior to first usage.
	# It is annoying. Another problem is that with busybox dd cannot create sparse files,
	# so creating it on the fly is a very bad idea, as the I/O is slower on the emulated (at least for now...) target
	# (docker I/O in Windows and MacOS is slow. There have been great advancements when they introduced virtio there, but
	# it is still much inferior to Linux, where docker does not need to run on top of an emulator ), so it would beat the purpose of doing things faster
	doLoopbackCleanupHeuristic=true
	if [ "$doLoopbackCleanupHeuristic" = "true" ] ; then
		# We know there are only 8 loopback device set but the kernel can do up to 1023(4) so let's be very explicit about it...
		for blk in $(ls 2>/dev/null -1 $DEV_BLOCK_FOLDER/loop[0-9] $DEV_BLOCK_FOLDER/loop[0-9][0-9] $DEV_BLOCK_FOLDER/loop[0-9][0-9][0-9]) ; do
			debug2 "Looking at ${blk}${PARTITION_MARK}5"
			if [ -b ${blk}${PARTITION_MARK}5 ] ; then
				warn "Removing previously setup loop device $blk. It might affect your other docker instances which are completely unrelated to our project!"
				losetup -d $blk || error "Failed to delete loopback device $blk. Proceeding anyway, but you are unlikely to be able to use the first loopback device for your needs. If this does not align with your logic, you should change the ramdisk code to something less hardcoded (which the R of course has done for you, before you stepped in...)"
			fi
		done
	fi
	EMMC_DEVICE=$(losetup -f)
	debug2 "EMMC_DEVICE is: $EMMC_DEVICE"
	dod_shell losetup -Pf $FAKE_LOOPBACK_EMMC_FILE
	hardVerbose "THIS IS TEMPORARY: SHOULD BE DONE ONLY FOR THE FLASHER IF WE ARE ABLE TO DO THE ISO LOGIC"
}

#
# Setup a fake file (preprovisioned) as a loopback device.
# This represents the persistent storage device and the removable device in the docker emulation, should
# we want to simulate an entire ramdisk sequence using an installer media [or a live CD, etc...]
#
do_docker_removable_media_loopback_device_setup() {
	: ${FAKE_LOOPBACK_REMOVABLE_MEDIA_FILE=/fakestuff/fakestorage1}

	# do removable media cleanup - here it is somewhat more clear, as long as we keep using the installer
	for blk in $(blkid | grep $INSTALLER_MEDIA_LABEL | cut -d':' -f1) ; do
		losetup -d $blk || error "Failed to delete loopback device $blk. Proceeding anyway, but you are unlikely to be able to use the fake removable media installer"
	done

	# See comments in do_docker_emmc_loopback_device_setup.
	# we will not do cleanups - instead, we will assume that this is always called after setting up the EMMC
	# at first shot we won't be working hard, and assume that there is only one instance and that the EMMC_DEVICE is at /dev/loop0.
	if [ ! -f "$FAKE_LOOPBACK_REMOVABLE_MEDIA_FILE" ] ; then
		info "docker: No removable media was provided"
		return 1
	fi

	REMOVABLE_MEDIA_DEVICE=$(losetup -f)
	losetup -Pf $FAKE_LOOPBACK_REMOVABLE_MEDIA_FILE || { find /fakestuff/ ; /bin/sh ;  exit 1 ; }
	debug2 "REMOVABLE_MEDIA_DEVICE is: $REMOVABLE_MEDIA_DEVICE"
}

#
# Wrappers to set up the block devices, should we want to use docker. In this case, we are going to provide
# external files (bind mounted), and setup loopback devices associated with them.
# our convention will be: first loop device is the emmc, second is the removable drive (just as we do in qemu)
# we are going to go exactly by the removable media logic / kernel params / etc.
# the only difference is that, once again, we are going to cheat with loopback devices, and set them up
# ahead of time.
#
bsp_init_blockdev_variables() {
	DEV_BLOCK_FOLDER=/dev 														# TODO: if we still want to support android partitioning, do it by the kernel version
	PARTITION_MARK="p"															# loopback setup have "p" as the partition mark
	# EMMC_DEVICE and REMOVABLE_MEDIA_DEVICE are decided dynmaically in the next functions
	if [ "$docker" = "true" ] ; then
		# this does not format, just mounts as loopback
		do_docker_emmc_loopback_device_setup
		do_docker_removable_media_loopback_device_setup
	fi

	# note: we don't really need to check if "docker" is true in the bsp, but it's dont to keep it consistent
}

#
# Docker environments must get their own treatment, especially since docker behaves differently in different platforms, and
# if running on Linux, the combination of privilege, docker version, kernel version and systemd version can become unpleasant
#
pre_switch_root_docker() {
	# TODO DEBUG DOCKER
	if [ ! "$docker" = "true" ] ; then
		return
	fi

	if [ -e $ROOTFS_MOUNT_POINT/etc/systemd/system/multi-user.target.wants ] ; then
		verbose "Likely switching into a systemd based system. May need to do some tweaks to keep the systemd green"
		if [ -e $ROOTFS_MOUNT_POINT/etc/systemd/system/systemd-modules-load.service ] ; then
			hardDebug "Was probably masked... $(ls -l $ROOTFS_MOUNT_POINT/etc/systemd/system/systemd-modules-load.service)"
			# cat $ROOTFS_MOUNT_POINT/etc/systemd/system/systemd-modules-load.service
		else
			hardDebug "Masking service"
			ln -s /dev/null $ROOTFS_MOUNT_POINT/etc/systemd/system/systemd-modules-load.service
			# could just test that /etc/systemd/system/systemd-modules-load.service → /dev/null
			# also, should be done not on the overlayed fs if it is being used, but we're good
			# chroot $ROOTFS_MOUNT_POINT systemctl mask systemd-modules-load.service # this is just to not have a falsly degraded state
		fi
	fi


	hardVerbose "Keeping docker mounts to be accessed in the new filesystem. This helps with developer features..."
	# We do it here and not in another function just to have all diffs in one place...
	# I suppose we will refactor it later on

	# This is only relevant to MacOS with the docker virtio drivers (and maybe to Windows as well? Todo, check that) in the case we provided some bind mounts that we would like to move
	dockerBindMounts=$(grep virtiofs $ROOTFS_MOUNT_POINT/proc/mounts | cut -d' ' -f 2)
	for d in $dockerBindMounts ; do
		mkdir -p $ROOTFS_MOUNT_POINT/media/docker/$d
		mount -n -o bind $d $ROOTFS_MOUNT_POINT/media/docker/$d || error "Failed to mount $d onto the /media/docker/ hierarchy"
	done

	# Handle pulse audio forwarding if you wish to support it (easier with MacOS and Windows, due to the variety of different mixers and frameworks in Linux hosts)
	if [ "$docker_forward_pulseaudio" = "true" ] ; then
		info "Forwarding pulseaudio"
		mkdir -p $ROOTFS_MOUNT_POINT/root/.config/pulse
		mount -n -o move /root/.config/pulse $ROOTFS_MOUNT_POINT/root/.config/pulse || error "Failed to forward pulse audio. c'est la vie"
	fi

	# Important: (busybox) switch_root needs to be havily hacked to work in docker, and it's not worth it so chroot instead
	#		     (TODO update this and the other comments)
	if ! grep -q 'tmpfs / tmpfs' $ROOTFS_MOUNT_POINT/proc/mounts ; then
		warn "docker switch_root: avoiding 'switch_root: root filesystem is not ramfs/tmpfs' in docker"
		hardDebug exec chroot ${ROOTFS_MOUNT_POINT} "${system_init}"
	else
		warn "docker switch_root - the genious workarounder arranged a tmpfs for you. heh"
		cat $ROOTFS_MOUNT_POINT/proc/mounts
		hardDebug "However your systemd will not work at this point due to combination of systemd+docker stupidity (autofs...) - unless you do another genious workaround..."
		hardInfo "And yet, the R worked around it (beware on Linux hosts though...)"
	fi

	# TODO: check there are no automounts with autofs4 - probably taken care of by blacklisting modules
}

bsp_docker_init() {
	hardDebug "Hello from your favorite docker bsp init script. This is run in a subshell"
}