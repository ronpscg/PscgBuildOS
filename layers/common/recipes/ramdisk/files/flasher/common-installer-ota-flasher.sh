#!/bin/sh

source /flasher/flash-emmc-common.sh

should_format_emmc() {
	if [ -f ${SRC_INSTALL_PARTITION_MOUNT_POINT}/dontformatemmc ] ; then
		warn "User instructed to not format partitions. Be warned (unless it is intended)"
		return 1
	fi

	if [ "$dontformatemmc" = "true" ] ; then
		warn "User instructed to not format partitions in the kernelcmdline" # this is likely for debuggign and/or speeding up things
		return 1
	fi
}

#
# Create (or recreate) partitions, unless there is a specific instruction to not do so (e.g. in a partial OTA that keeps the same structure. This speeds up the update process if the partition structure is identical)
# This creates and formats the partitions according to a predefined scheme
#
# This code runs before starting installation to partitions (whether from a media, recovery, or OTA mechanisms)
#
pre_installer_create_partitions() {
	if ! should_format_emmc ; then
		return
	fi
	(
		# You can save time in installation if you know for sure the partitions are the same
		if [ "$config_imager__installer_runtime_recreate_partitions" = "true" ] ; then
			info_do_or_die create_emmc_partition_table
		fi
		info_do_or_die format_emmc_partitions
	) || fatalError "Failed to (re)create and format emmc partitions"
}

#
# Set the updater status files after a successful installation
#
post_installer_flash_emmc_set_ota_states_after_installer_flashing() {
	local installation_src_directory
	installer_flasher=true # Otherwise:
	case "$flashing_reason" in
		installer_a_only)
			installation_src_directory=$INSTALLER_MEDIA_MOUNT_POINT
			last_active_boot_partition=$target_boot_partition
			last_active_system_partition=$target_system_partition
			;;
		ota|recovery|installer_ab_copyoverotaextract|installer_ab_directlyfromremovablemedia)
			return 0
			;;
		*)
			fatalError "Impossible flashing_reason $flashing_reason"
			;;
	esac

	# We don't really need the digest anymore as all installation sources can now include manifest (TODO- can work on it and on the userspace one, but it's not necessary, just a little cleanup. Won't do for now)
	local installer_digest_file=$installation_src_directory/installer.digest
	if [ -e $installer_digest_file ] ; then
		installer_digest=$(cat $installer_digest_file)
		verbose "The installer digest is $installer_digest"
	else
		installer_digest=""
		verbose "The installer digest was not provided on installation media."
	fi

	installer_manifest_file=$installation_src_directory/installer.manifest

	hardDebug "Done installing to partitions. You're all set to go except for some ota stuff"

	verbose "Updating OTA state after first flashing..."
	set_ota_done_states_after_first_installation
	verbose "Finished!"
}

#
# This is a wrapper code for flashing code from a (mounted) folder (${SRC_INSTALL_PARTITION_MOUNT_POINT}),
# to a device
# expecting:
# 	SRC_INSTALL_PARTITION_MOUNT_POINT - folder where the installables are
#	EMMC_DEVICE - target device
#	flashing_reason
#	target_boot_partition - next boot partition p-indicator (e.g. p<partition-number>)
#	target_system_partition - next system partition p-indicator (e.g. p<partition-number>)
#	target_boot_label - label for the next boot candidate partition
#	target_system_label - label for the next system candidate partition
# $2 boot partition p-indicator (e.g. p<partition-number>)
# $3 system partition p-indicator (e.g. p<partition-number>)
#
main_common_installer_ota_flasher() {
	source_hardware_dependent_functions # for hmi in scripts which are executed and not sourced
	bsp_hmi_software_flashing_start $flashing_reason
	info "\x1b[5m-- STARTING TO FLASH EMMC (reason: $flashing_reason) --\x1b[0m"
	# note: it is OK to use fatalError here but not on init, as this script is forked from init, not exe-ed.


	hardInfo "Flashing ${SRC_INSTALL_PARTITION_MOUNT_POINT} --> ${EMMC_DEVICE}"

	# Educational note:
	# This could be a good place to backup data, and after flashing could be to restore it.
	# You can design a mechanism that does it, e.g. by keeping a lower partition number as a backup/restore storage
	# and deciding what to backup and when (E.g. configuration files, log, network connections, etc.)
	# We do not provide a reference design here for simplicity, and because this is task and system specific

	if [ "$flashing_reason" = "installer_a_only" ] ; then
		pre_installer_create_partitions
	fi

	do_install_to_partitions || fatalError "Failed to install to partitions"

	if [ "$flashing_reason" = "installer_a_only" ] ; then
		post_installer_flash_emmc_set_ota_states_after_installer_flashing
	fi

	bsp_hmi_software_flashing_completed
	info "\x1b[5m*******************************************\x1b[0m"
	info "\x1b[5m Completed $flashing_reason eMMC flashing  \x1b[0m"
	info "\x1b[5m*******************************************\x1b[0m"
}
