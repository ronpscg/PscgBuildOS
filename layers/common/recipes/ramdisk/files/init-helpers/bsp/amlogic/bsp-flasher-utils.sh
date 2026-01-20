#
# This is an optional function. In this BSP, we set it to replace the ATF and U-Boot FIP (Firmware Image Package)
#
bsp_pre_create_partitions() {
	hardWarn "$FUNCNAME called"
	: ${OVERWRITE_BOOT_FIRMWARE=true}
	if [ "$OVERWRITE_BOOT_FIRMWARE" = "true" ] ; then
		hardWarn "REPLACING YOUR BOOT FIRMWARE AND U-BOOT CODE"
		# Note: this also copies/replaces the environment. once may decide to have it or not
		#		one can decide to separate it or not, etc.
		#		at the time of writing, we allow to store the environment on the 3MiB mark.
		#temporarily use the same path we have before we properly create it
		dd if=$REMOVABLE_MEDIA_DEVICE of=$EMMC_DEVICE bs=$((1024*1024)) count=4 || fatalError "Failed to update the bootloader"
	fi
}

bsp_post_partition_format_pre_install_to_partitions() {
	hardWarn "$FUNCNAME called"
}