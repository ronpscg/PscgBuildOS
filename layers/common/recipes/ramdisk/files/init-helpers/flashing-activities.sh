#
# Remove all remainders of files that can make automatic installation from a removable media, and reboot afterwards
#
remove_autoflash_files_and_reboot() {
	if rm -f $INSTALLER_AUTO_COMMAND_FILE_MOUNT_POINT/autoflash ; then
		hardInfo "Will no longer autoflash at the next reboot. Will automatically reboot now"
		if [ "$docker" = "true" ] ; then
			warn "You are running inside a container and it will not reboot for you. You may instead re-run.
				  In fact, it is better to run the next time WITHOUT removable media, and keep the file in tact,
				  since you are already not rerunning automatically.
				  You may ignore the errors on the next prints, not all of the mounts are available for you anyway"
			verbose "Removing previous fakestuff when possible"
			for i in $(losetup -a | grep fakestuff | cut -d: -f1) ; do losetup -d $i ; done
		fi
		cd /
		umount -a
		sync

		reboot -f
	else
		fatalError "Failed to remove the autoflash files. Will not reboot to avoid a possible infinite installation loop"
		# TODO revise fatalErrorness, and instead start a shell
	fi
}

#
# Install from removable media to specific default partitions (unless requested otherwise by the command line)
#
install_a_only() {
	(
	SRC_INSTALL_PARTITION_MOUNT_POINT=$INSTALLER_MEDIA_MOUNT_POINT
	flashing_reason=installer_a_only
	target_boot_partition=${EMMC_DEVICE}${PARTITION_MARK}${cmdline_installer_boot_partition_number-1}
	target_system_partition=${EMMC_DEVICE}${PARTITION_MARK}${cmdline_installer_system_partition_number-5}
	target_boot_label=BOOT_EMMC # careful - this means no A/B on boot
	target_system_label=system # a-only
	info_do_or_die main_common_installer_ota_flasher
	)

	if [ "$?" = "0" ] ; then
		if [ "$ONE_TIME_FLASHER" = "true" ] ; then
			# At the end of the flashing, it is expected that the partitions would be unmounted (to avoid disk damage if user shuts down the system)
			# So check if the partition is mounted, and if not, remount it, before checking whether to auto reboot or not

			# TODO extract to another function and allow multiple places to look at!!!!!!

			if mount | grep $INSTALLER_AUTO_COMMAND_FILE_MOUNT_POINT | grep -q ro, ; then
				mount -o remount,rw $INSTALLER_AUTO_COMMAND_FILE_MOUNT_POINT || fatalError "Cannot remount as rw" # TODO revise fatalError-ness
			elif ! mountpoint $INSTALLER_AUTO_COMMAND_FILE_MOUNT_POINT ; then
				mount LABEL=$INSTALLER_AUTO_COMMAND_FILE_PARTITION_LABEL $INSTALLER_AUTO_COMMAND_FILE_MOUNT_POINT || fatalError "Cannot mount" # TODO revise fatalError-ness
			fi
			remove_autoflash_files_and_reboot
		else
			debug_stopatramdisk_checkpoint successful_flashing # This is just for illustrative purposes, and does nothing unless a kernel cmdline argument instructs it to stop here
			reInitLogsAndStopPersistentLogging
			warn "Most of our users will brutally turn off the machine, so we unmount the removable media for you"
			# this is done in the installer so it can be removed
			if mountpoint $INSTALLER_MEDIA_MOUNT_POINT ; then
				umount $INSTALLER_MEDIA_MOUNT_POINT || error "Failed to unmount the removable media"
			fi

			call_if_exists do_reboot_to_state

			# this is done in the installer so it can be removed
			unmount_ota_partitions || error "Failed to unmount the OTA partitions"
			warn "Stopping at ramdisk after a successful installer media flashing"
			do_fallback_to_shell
		fi
	else
		error "Flashing seems to have failed. Will stay at ramdisk"
		warn "Stopping at ramdisk the onetime flasher"
		do_fallback_to_shell
	fi
}

#
# The function decides the next OTA state on the developer feature of doing A/B flashing as OTA from the installer media.
# $1: state to set, if we indeed want to reflash, and not just let the OTA process proceed what it has been doing. Can be "pendingReflash|pendingInstallerReflash"
#
set_installer_media_ota_state_if_necessary() {
	local installer_potential_next_state=$1
	state=$(get_state)
	case "$state" in
		"testingReflashedImages"|"otaCompletedSuccessfully"|"livepatchCompletedSuccessfully")
			verbose "ota state is $state. Skipping removable media installer logic"
			;;
		"awaitingReboot")
			fatalError "ota state is $state. (we are not supposed to be here, and since this is strictly a debugging mechanism, we'll stop here)"
			;;
		"pendingReflash" | "pendingInstallerReflash" | "reflashing" | "pendingReflashVerification" | "reflashingVerification" | "reflashOK" | "reflashFailed" | "reflashVerificationFailed")
			verbose "ota state is $state. Will not do anything, since we are in the middle of a reflash or verification"
			;;
		*) # this goes to all richos tests - remember, this is an installer! for example: "idle"|"downloading"|"downloaded"|"verifying"|"verified"|"unpacking"|"unpacked"
			warn "OTA: state=$state. Will set the state to $installer_potential_next_state and continue with the installer media A/B OTA like flashing"
			set_state $installer_potential_next_state
			;;
	esac
}

#
# Check the corresposnding environment variables and run flashing upon boot, if required to
# At the end, check for a one-time flashing indication, to prevent the removable media from:
#	- requiring user interaction
#	or
#	- running into a flashing reboot loop
#
do_autoflash_sequence() {
	INSTALLER_AUTO_COMMAND_FILE_PARTITION_LABEL=$INSTALLER_MEDIA_LABEL
	INSTALLER_AUTO_COMMAND_FILE_MOUNT_POINT=$INSTALLER_MEDIA_MOUNT_POINT

	# The following line is used to allow an easy command line or environment toggling for virtualized targets
	if [ "$forceskipinstallermediaflashing" = "true" ] ; then
		warn "Skipping installing media flashing sequence due to user request"
		return 0
	fi

	if [ -e $INSTALLER_AUTO_COMMAND_FILE_MOUNT_POINT/autoflash ] ; then
		info "Will now auto flash ... If you don't want it on the next boot - make sure you remove the file from the installation media!"

		export installer_a_only=false
		# Mounting to decide the A/B state, in case of an A/B state.
		if [ "$cmdline_installer_a_only" = "true" ] ; then
			installer_a_only=true
		elif ! mount_ota_partitions ; then
			installer_a_only=true
		fi

		if [ "$installer_a_only" = "true" ] ; then
			install_a_only
		else
			if [ "$ONE_TIME_FLASHER" = "true" ] ; then
				# This is by design, do not change the behavior. I only note it because essentially, a real system installation from a removable media,
				# in any project, will always be an A only (or a B only) installation.
				# This is a nice development feature I added, so "don't push it"
				warn "For the A/B sequence, we ignore the ONE_TIME_FLASHER flag. Upon succeess, you will end up in the richos system."
				warn "Please be careful, and don't reboot the richos with the media installed, or you will have another instllation (to the other bank)"
			fi
			hardVerbose "A/B installing scheme - moving to OTA scheme, in pendingInstallerReflash state"
			if [ -f $INSTALLER_AUTO_COMMAND_FILE_MOUNT_POINT/installer.manifest ] ; then
				info "Setting the installer manifest as the wip manifest"
				dod_shell cp $INSTALLER_AUTO_COMMAND_FILE_MOUNT_POINT/installer.manifest $NEW_WIP_MANIFEST_FILE
			else
				: # The current userspace flasher will want the manifest for its last update state, so if you don't have it
				: # you might just do an a-only scheme instead
			fi

			if [ "$INSTALLER_MEDIA_INSTALLER_AB_STRATEGY" = "copyoverotaextract" ] ; then
				# This is a total reusing of the OTA mechanism - copying the installer over the OTA_EXTRACT_PARTITION
				# While it works perfectly, you should NOT be using it, unless you also want to update the recovery tarball in the process, which
				# is a bad idea, and if you do so, you would rather use a_only. Otherwise, you will need a huge otaaextract partition
				verbose_do_or_die cleanup_ota_extract
				loglevel_dod_shell verbose cp -rPv $INSTALLER_AUTO_COMMAND_FILE_MOUNT_POINT/* $OTA_EXTRACT_BASE_DIR/
				set_installer_media_ota_state_if_necessary pendingInstallerReflash
			else
				# Install directly from the insallation media. This is faster - but if you stop in the middle, it is not something we intend to support
				# or test, or give a lot of warnings to
				set_wip_extract_working_dir $INSTALLER_AUTO_COMMAND_FILE_MOUNT_POINT
				set_installer_media_ota_state_if_necessary pendingInstallerReflash
			fi
		fi
	fi
}
