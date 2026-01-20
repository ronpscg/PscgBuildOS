do_install_dtbs() {	
	TODO REVISE THIS
	prebuilt_dtb_path_base=$LOCAL_DIR/dtb
	LIST_OF_INSTALL_PREBUILT_DTBS=$prebuilt_dtb_path_base/arm64*.dtb
	if [ ! "$config_kernel__do_dtbs" = "false" ] ; then
		# This would be BSP specific
		mkdir -p ${LINUX_INSTALL_DIR}/dtb/thepscg
		cp $LIST_OF_INSTALL_PREBUILT_DTBS ${LINUX_INSTALL_DIR}/dtb/thepscg/
	else
		warn "Skipped recopy dtbs due to user request"
	fi
	cp -r $LINUX_INSTALL_DIR/dtb $BOOT_DIR/ || fatalError "Failed to copy the dtbs to $BOOT_DIR"
}
