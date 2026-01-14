#!/bin/bash

#
# This script aims to do some validity checks for the QEMU image parameters very early during the build stage.
# The idea is to avoid building the wrong thing due to all kinds of development "improvements" (hacks that speed up build times)
# in case someone uses some wrapper scripts to build, or some environment variables that are not set correctly.
#
# QEMU gets its own treatment, because it is a main target for quick experimentation, and so it is easy to
# set parameters for minimal copying when quickly testing (E.g. check live image, and only later the installer), and
#

check_qemu_image_paths() {
	# Should go as a sanity check early enough during config:
	if [ "$config_bsp__qemu_copy_installer_image_to_removable_media" = "true" ] && [ "$config_imager__installer_image_file" = "$config_bsp__qemu_removable_media_path" ] ; then
		warn "You may want to set config_bsp__qemu_removable_media_path=/tmp/removable.img if you are running after a clever development hack"
		fatalError "You MUST NOT set config_bsp__qemu_copy_installer_image_to_removable_media=true and have config_bsp__qemu_removable_media_path==config_imager__installer_image_file (=$config_imager__installer_image_file)"
	fi

	printvars_sorted "config_bsp__qemu_copy_installer_image_to_removable_media config_imager__create_ota_image"


	if [ ! "$config_imager__create_ota_image" = "true" ] && [ "$config_bsp__qemu_copy_installer_image_to_removable_media" = "true" ] ; then
		warn "You are not compressing the working directory, so you will not be able to create an OTA tarball or a recovery image tarball. You can set config_imager__create_ota_image=true to enable this."
		fatalError "You cannot create the installer image without compressing the working directory. Please decide if you want to create an installer or not. If so, kindly set config_imager__create_ota_image=true"
	fi

	if [ -z "$config_bsp__qemu_storage_device_path" -a "$config_bsp__qemu_recreate_storage_device" = "true" ] ; then
		if [ ! "$config_bsp__qemu_create_storage_device_with_default_path_if_need_be" = "true" ] ; then
			fatalError "Please provide a storage path at config_bsp__qemu_storage_device_path or set config_bsp__qemu_recreate_storage_device=false"
		fi
	fi
	if [ -z "$config_bsp__qemu_removable_media_path" ] ; then
		if [ "$config_bsp__qemu_copy_installer_image_to_removable_media" = "true" ] ; then
			fatalError "You must not set config_bsp__qemu_copy_installer_image_to_removable_media=true and not set config_bsp__qemu_removable_media_path"
		else
			warn "You did not specify a removable media path at config_bsp__qemu_removable_media_path. If the installer is mounted r/w your image will not be prestine, but we trust you know what you are doing"
		fi
	fi
}

# This is *super* inaccurate and will definitely change with different distro versions. The ballpark though, is to ensure that
# if there is a debos image (and maybe later other images with "big" features like graphics), the generated image files will
# not be way too small for them - before we even start the build
check_evident_and_inaccurate_image_sizes() {
	if [ "$ENABLE_GRAPHICS" = "true" ] ; then
		verbose "Checking if the installer image size is big enough for $config_distro graphics..."
		if [ "$config_imager__installer_media_size_sectors" -lt "$((5*$SECTORS_PER_GIB))" ] ; then
			fatalError "config_imager__installer_media_size_sectors=$config_imager__installer_media_size_sectors. Please increase it!"
		fi
	fi
}

create_containing_folders_if_needed() {
	for path in config_bsp__qemu_storage_device_path config_bsp__qemu_removable_media_path ; do
		test -z "$(get_compound_var $path)" && continue
		d=$(dirname $(get_compound_var $path))
		if [ ! -d $d ] ; then
			warn "Creating $d for the first time"
			mkdir -p $d || fatalError "Failed to create $d"
		fi
	done
}

prebuild_sanity_check_qemu_images_params() {
	check_qemu_image_paths
	check_evident_and_inaccurate_image_sizes
	create_containing_folders_if_needed
}

main() {
	source $LOCAL_DIR/../qemu.buildconfig # the prologue takes care of the path - but I actually don't think we need to source it at all now, unless we do it before the prompt. Leaving it just in case
	prebuild_sanity_check_qemu_images_params
}

commonScriptPrologueLogRunAndEpilogue $@
