#!/bin/bash
main() {
	info "Adding the bootchain to the removable media to make it bootable in presence of empty or no eMMC"

	export DEV=$config_imager__installer_image_file
	export indir=${FIP_INSTALL_DIR}

	tool=${FIP_SOURCE_DIR}/copy-to-media.sh

	verbose "Preparing an dd-able sdcard image"
	debug "You can do the same by running:   DEV=$DEV indir=$indir $tool sd file"
	do_or_die $tool sd file

	info "You may flash $config_imager__installer_image_file into an sdcard"
}

commonScriptPrologueLogRunAndEpilogue $@
