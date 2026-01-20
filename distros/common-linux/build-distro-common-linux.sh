#!/bin/bash
# Distro build script.
# Builds the different components of the distro, such as [bootloader], ramdisk, Linux kernel, a core rootfs, and layers on top of the rootfs
# Creates an installer image.
#
# With minor changes, can create the same (runtime) distro workable from a removable media (e.g. as in Raspberry Pi). This is not done now.
#

#
# Add build configs from extra layers. This looks at all the extra layers, and sources *exactly* the <layername>.buildconfig,
# where the <layername> is the containing folder of add-layer.sh
#
build_distro__add_build_configs_from_extra_layers() {
	local layerline layerpath layername l
	# config_distro__extra_layers gets predence over config_distro__extra_layers_file
	for l in $config_distro__extra_layers ; do
		layerpath=$(eval echo $l) # in case it has variables, e.g. $LAYERS_DIR. Super insecure, beware eval!
		layername=$(basename $layerpath)
		if [ -f "$layerpath/$layername.buildconfig" ] ; then
			extra_layers_build_configs+=" $layerpath/$layername.buildconfig"
		fi
	done

	if [ -f "$config_distro__extra_layers_file" ] ; then
		# This is a file with layers to add, one per line, and comments are allowed
		while read -r layerline ; do
			if [ -n "$layerline" ] && [[ ! "$layerline" =~ ^#.* ]] ; then
				layerpath=$(eval echo $layerline) # in case it has variables, e.g. $LAYERS_DIR. Super insecure, beware eval!
				layername=$(basename $layerpath)
				if [ -f "$layerpath/$layername.buildconfig" ] ; then
					extra_layers_build_configs+=" $layerpath/$layername.buildconfig"
				fi
			fi
		done < "$config_distro__extra_layers_file"
	fi
}


#
# This might be temporary (as each recipe may handle their own source, etc., or perhaps every layer would take care of something of its own but the kernel etc. are not
# set properly in this case, at least for now (I mean, as layers)
# go over all of the relevant config files for the distro
#
build_distro__source_build_configs() {
	local build_configs=""
	local more_build_configs=""
	# On dependent recipes (e.g. common and bsp related to the same functionality), source  from the more specific to the less specific one
	build_configs="$build_configs ${config_bsp_layer}/recipes/kernel/kernel.buildconfig"

	if [ -f "${config_bsp_layer}/bsp.buildconfig" ] ; then
		# This could go with the extra configs or the extra layers - but it is important enough and may be specific enough,
		# so we will do it here for now. It was added to support the rewritten (2026) amlogic example which demonstrates the building of:
		# - u-boot + extlinux
		# - specific arm trusted firmware (we will call it boot_firmware for this sake)
		#
		# If will also support the x86_64 EFI example. Since Tianocore EDK2 takes a while to build and it is a specific example, and I am busy, I will not 
		# integrate it properly at this point. It can be a good exercise for the next longer-term batch of training, or for some diligent people to take it
		# I don't see having time for this in the next good couple of months, and I don't want to quickly hack without documenting or testing extensively, so I don't
		# think I will personally put work on it		
		build_configs="$build_configs ${config_bsp_layer}/bsp.buildconfig"
	fi

	build_configs="$build_configs $LAYERS_DIR/bsp/recipes/linux/common-linux/common-linux.buildconfig"
	build_configs="$build_configs $LAYERS_DIR/common/recipes/kernel/kernel.buildconfig"
	build_configs="$build_configs $LAYERS_DIR/bsp/recipes/linux/common-linux/firmware/linux-firmware.buildconfig" # TODO probably move places - e.g. to common/recipes/firmware/  - everything there is linux related (common/recipes) so maybe change that too
	build_configs="$build_configs $LAYERS_DIR/common/recipes/ramdisk/ramdisk.buildconfig"
	build_configs="$build_configs $LAYERS_DIR/common/recipes/image/imager.buildconfig $LAYERS_DIR/common/recipes/image/imager.ext4images.buildconfig"
	build_configs="$build_configs $LAYERS_DIR/bsp/recipes/linux/common-qemu/qemu.buildconfig"

	extra_layers_build_configs="" # set in the next line
	build_distro__add_build_configs_from_extra_layers
	build_configs="$build_configs $extra_layers_build_configs"


	# Independent build configs
	for config in $build_configs ; do
		if [ -f "$config" ] ; then
			source "$config" || fatalError "Failed to source $config"
		else
			# either warn or fatalError. I always used to warn, as per development, but for new comers it is better to fail altogether
			fatalError "Expected $config but it was not present"
		fi
	done

	# Dependent build configs
	more_build_configs="$build_configs $LAYERS_DIR/common/recipes/$config_ramdisk__shell_swissknife/$config_ramdisk__shell_swissknife.buildconfig"
	for config in $more_build_configs ; do
		if [ -f "$config" ] ; then
			source "$config" || fatalError "Failed to source $config"
		else
			fatalError "Expected $config but it was not present" # could be warn too
		fi
	done
}

#
# Source shell scripts that have functions used during this build, which may or may not be used according to configuration values, so we get them in anyway
#
build_distro__source_shell_scripts() {
	# We allow for all kinds of tricks to save time on building, and so we source the scripts. However, if the kernel is not
	# to be built, we do not want some of its fetch/unpack etc. functions defined.
	# I suppose we could modify the names, will do it at a later pass
	if [ "$config_buildtasks__do_build_kernel" = "false" -a "$config_buildtasks__do_build_kernel_modules" = "false" ] ; then
		return
	fi

	# In this case we source the common file before the more specific ones (if the latter exists), because the more specific one would implement
	# functions that have the exact same name on the one hand (intentional, but might be modified), that will override completely (or use, explicitly)
	# some of the functions defined in the former
	source_file_or_die $LAYERS_DIR/common/recipes/kernel/build-linux-kernel.sh
	source_if_exists ${config_bsp_layer}/recipes/kernel/build-linux-kernel.sh
}

#
# add layers and recipes that are either optional or dependant on configuration options
# this is only geared towards rootfs
#
build_distro__add_more_layers_and_recipes() {
	if [ "$config_distro__add_oot_ota_code" = "true" ] ; then
		info "Adding out of tree OTA code (demonstration)"
		quick_demonstration_add_ota_code_to_folder $ROOTFS_DIR $config_distro__copy_oot_ota_code_to_rootfs_method
	fi

	# Since the OTA mechanism is important and is a first level citizen in a way, I added it explicitly
	# for the rest, please use extra layers

	local layerline layerpath layername l
	#
	# config_distro__extra_layers gets predence over config_distro__extra_layers_file for sourcing
	# for add_layer(execution), it is is also executed first although it is arbitrary
	for l in $config_distro__extra_layers ; do
		layerpath=$(eval echo $l) # in case it has variables, e.g. $LAYERS_DIR. Super insecure, beware eval!
		banner_and_do add_layer $layerpath
	done

	if [ -f "$config_distro__extra_layers_file" ] ; then
		# This is a file with layers to add, one per line, and comments are allowed
		while read -r layerline ; do
			if [ -n "$layerline" ] && [[ ! "$layerline" =~ ^#.* ]] ; then
				layerpath=$(eval echo $layerline) # in case it has variables, e.g. $LAYERS_DIR. Super insecure, beware eval!
				banner_and_do add_layer $layerpath
			fi
		done < "$config_distro__extra_layers_file"
	fi
}

#
# allow to execute more commands before packing
#
build_distro__run_more_commands_before_image_packing() {
	for cmd in "$config_distro__extra_commands_before_image_packing" ; do
		:
	done
}


#
# Adds an oot (out of tree) code to a folder via one of several methods
# $1 tarball to either extract to $2 or copy (depending on $3)
# $2 folder to add the code to. This is a direct approach if $3 is direct
# $3 method - can be <direct|overlay|writableoverlay> for direct extraction,
#			  adding as an overlay tarball, or adding as a writable overlay tarball
#
add_fs_tarball_to_folder() {
	local tarball=$1
	local extraction_dir=$2
	local method=$3

	case $method in
		direct)
			verbose_do_or_die tar -C $extraction_dir -xf $tarball
			;;
		overlay)
			do_or_die mkdir -p $distro__image_materials_installables_overlays_dir/system
			verbose_do_or_die cp -a $tarball $distro__image_materials_installables_overlays_dir/system
			;;
		writableoverlay)
			do_or_die mkdir -p $distro__image_materials_installables_writableoverlays_dir/system
			verbose_do_or_die cp -a $tarball $distro__image_materials_installables_writableoverlays_dir/system
			;;
		*)
			fatalError "Unsupported method $method"
			;;
	esac
}



#
# Adds an oot (out of tree) code to a folder via one of several methods
# $1 folder to add the code to. This is a direct approach. One could also create a tarball and add it as an overlay
# $2 method - can be <direct|overlay|writableoverlay> for direct extraction,
#			  adding as an overlay tarball, or adding as a writable overlay tarball
#
quick_demonstration_add_ota_code_to_folder() {
	local extraction_dir=$1
	local method=$2
	local ota_project_src=$config_toplevel__oot_dir/ota-update-richos
	local ota_tarball_builder=$ota_project_src/make-ota-userspace-tarball.sh
	local wd=${TMP_TOP}/oot-build/ota-targetfiles
	local tarball=${TMP_TOP}/oot-build/ota-targetfiles-tarball.tar.xz

	local resolved_path=$(readlink -f "$ota_project_src")
	if [ -z "$resolved_path" -o ! -d "$resolved_path" ] ; then
		hardError "THIS IS A PRIVATE REPO AND IT NEEDS TO BE REFACTORED"
		fatalError "No source folder in $ota_project_src. You may want to get the source code from somewhere e.g. git clone  https://github.com/ronpscg/PscgBuildOS-ota-update-richos.git $ota_project_src"
	fi

	verbose_eval_or_die workdir=$wd targetarchive=$tarball $ota_tarball_builder

	add_fs_tarball_to_folder $tarball $extraction_dir $method
}


#
# This interacts closely with the kernel builders, and can either do things or do nothing.
# We postpone the packaging of kernel modules to allow for the insertion of the built modules either:
# - to the selected folder (e.g. rootfs or ramdisk)
# - to a (system) overlay tarball
# - to a (system) writable overaly tarball
build_distro__add_kernel_modules_to_rootfs() {
	if [ "$config_buildtasks__do_build_kernel_modules" = "false" ] ; then
		warn "Skipped rootfs module install due to user request"
		return
	fi

	info "Adding kernel modules to rootfs"

	if [ "$config_kernel__copy_all_built_modules_to_rootfs" = "true" ]  ; then
		local all_modules_method=$config_distro__copy_linux_modules_to_rootfs_method_all_kernel_modules
		info_do_or_die kernel__do_modules_install_and_pack_workdir
		add_fs_tarball_to_folder $kernel__modules_install_tarball $ROOTFS_DIR $config_distro__copy_linux_modules_to_rootfs_method_all_kernel_modules
		return
	fi

	# leaving some options here for quick hacking, but they are disabled by default
	local keep_previous_modules=false
	local specific_kernel_modules_tarball=${distro__image_materials_workdir_specific_linux_kernel_modules}/../linux-modules-specific.tar.gz

	if [ -d "$distro__image_materials_workdir_specific_linux_kernel_modules" ] ; then
		if [ "$keep_previous_modules" = false ] ; then
			verbose_do_or_die rm -rf $distro__image_materials_workdir_specific_linux_kernel_modules
		else
			warn "Keeping previous specific modules in $distro__image_materials_workdir_specific_linux_kernel_modules"
		fi
	fi

	if [ -z "$config_kernel__specific_modules_rootfs_files_list_nosuffix" ] ; then
		return
	fi

	verbose_do_or_die mkdir -p $distro__image_materials_workdir_specific_linux_kernel_modules

	info_do_or_die kernel__do_modules_install
	info_do_or_die copy_linux_modules_to_folder_and_rerun_depmod "$config_kernel__specific_modules_rootfs_files_list_nosuffix" $distro__image_materials_workdir_specific_linux_kernel_modules


	case $config_distro__copy_linux_modules_to_rootfs_method_specific_kernel_modules in
		direct)
			# don't bother to compress
			verbose_do_or_die sudo cp -a $distro__image_materials_workdir_specific_linux_kernel_modules/* $ROOTFS_DIR/
			;;
		overlay|writableoverlay)
			# Create a tarball of the firmware files
			verbose_do_or_die tar -C $distro__image_materials_workdir_specific_linux_kernel_modules -czf $specific_kernel_modules_tarball .
			add_fs_tarball_to_folder $specific_kernel_modules_tarball dontcare $config_distro__copy_linux_modules_to_rootfs_method_specific_kernel_modules
			;;
		*)
			fatalError "Unsupported method $config_distro__copy_linux_modules_to_rootfs_method_specific_kernel_modules"
			;;
	esac
}

build_distro__add_kernel_modules_to_initramfs() {
	if [ "$config_buildtasks__do_build_kernel_modules" = "false" ] ; then
		warn "Skipped rootfs module install due to user request"
		return
	fi

	info "Adding kernel modules to initramfs"
	# in the ramdisk we don't use overlays, but always copy

	# Note: we might do the modules install part twice so TODO do once before the add kernel etc. and package separately
	#       I just don't have time to test, and doing it twice doesn't hurt
	# Also note: if all kinds of layers do things after building the ramdisk - it will have to be repacked
	# I am not doing it yet (TODO) but it is necessary to avoid people having to think about the order.
	# Alternatively, one could postpone the ramdisk to the end of the process. Since building the ramdisk is super fast
	# and it is useful, I prefer to do repack twice if needed, rather than postpone it to the end
	if [ "$config_kernel__copy_all_built_modules_to_initramfs" = "true" ]  ; then
		info_do_or_die kernel_do_modules_install
		copy_linux_modules_to_folder_and_rerun_depmod all $RAMDISK_DIR
		verbose_do_or_die sudo cp -a $distro__image_materials_workdir_specific_linux_kernel_modules/* $RAMDISK_DIR/
		return
	fi

	if [ -z "$config_kernel__specific_modules_initramfs_files_list_nosuffix" ] ; then
		return
	fi

	info_do_or_die kernel__do_modules_install
	info_do_or_die copy_linux_modules_to_folder_and_rerun_depmod "$config_kernel__specific_modules_initramfs_files_list_nosuffix" $RAMDISK_DIR
}

build_distro__add_firmware_to_rootfs() {
	# leaving some options here for quick hacking, but they are disabled by default
	local keep_previous_firmware=false
	local firmware_tarball=${distro__image_materials_workdir_specific_linux_firmware}/../linux-firmware.tar.gz

	if [ -d "$distro__image_materials_workdir_specific_linux_firmware" ] ; then
		if [ "$keep_previous_firmware" = false ] ; then
			verbose_do_or_die rm -rf $distro__image_materials_workdir_specific_linux_firmware
		else
			warn "Keeping previous firmware in $distro__image_materials_workdir_specific_linux_firmware"
		fi
	fi

	if [ -z "$config_firmware__linux_firmware_rootfs_files_list" ] ; then
		return
	fi

	verbose_do_or_die mkdir -p $distro__image_materials_workdir_specific_linux_firmware

	add_firmware_to_rootfs # adds the firmware to $distro__image_materials_workdir_specific_linux_firmware/lib/firmware

	case $config_distro__copy_linux_firmware_to_rootfs_method in
		direct)
			# don't bother to compress
			verbose_do_or_die sudo cp -a $distro__image_materials_workdir_specific_linux_firmware/* $ROOTFS_DIR/
			;;
		overlay|writableoverlay)
			# Create a tarball of the firmware files
			verbose_do_or_die tar -C $distro__image_materials_workdir_specific_linux_firmware -czf $firmware_tarball .
			add_fs_tarball_to_folder $firmware_tarball dontcare $config_distro__copy_linux_firmware_to_rootfs_method
			;;
		*)
			fatalError "Unsupported method $config_distro__copy_linux_firmware_to_rootfs_method"
			;;
	esac
}

#
# Reusing build materials.
# This function encapsulates some build optimization choices for the developer
#
build_distro_reuse_materials_wrapper() {
	init_env_reuse_materials
	# Allow reusing other materials. Internally, the function looks at the buildtasks variables,
	# so if they are set to build, the respective folder will not be reused, making it safe to call it here
	# just in case (and either the user or the distro need to be very specific about the reusing anyhow.
	# remember it is use for debugging!
	reuse_build_materials
}

#
# Reusing sources and intermediates
# This function encapsulates some build optimization choices for the developer
#
build_distro_reuse_build_src_and_arch_wrapper() {
	# There is no point in making any other thing than symlink here, so it is set in here. this configuration option may be removed later
	config_distro__shared_src_reusing_method=symlink
	config_distro__shared_arch_reusing_method=symlink

	init_env_reuse_build_src_intermediates
	init_env_reuse_build_arch_intermediates

	reuse_build_src_intermediates
	reuse_build_arch_intermediates
}

build_distro__highlight_major_step_in_log() {
	hardVerbose "\x1b[37;5m\n\t\t\t\n$@\t\t\t\n\t\t\t\n\t\t\t\x1b[0m"
}

#
# Allow some more sanity checks after sourcing the build configs, but before starting the build
# This is a good place to do some sanity checks, such as checking the environment variables, the build directories,
# check if the user has the necessary permissions to run the build scripts, and so on.
#
build_distro__prebuild_post_sourcing_sanity_checks() {
	hardVerbose "Running prebuild sanity checks (after the first user prompt)"
	sanity_check_firmware_config builtin
	sanity_check_firmware_config initramfs
	sanity_check_firmware_config rootfs

	# TODO: now that qemu.buildconfig is sourced, we can get rid of the script, and put its contents in qemu.buildconfig
	info_do_or_die $LAYERS_DIR/bsp/recipes/linux/common-qemu/sanity/prebuild-sanity-check-qemu-images-params.sh || fatalError "Failed to do prebuild sanity checks for QEMU images parameters"
}

build_distro__cleanup_overlay_tarballs() {
	if [ ! "$config_distro__cleanup_overlay_tarballs_before_build" = "true" ] ; then
		return
	fi

	verbose_do_or_die rm -rf $distro__image_materials_installables_overlays_dir
	verbose_do_or_die rm -rf $distro__image_materials_installables_writableoverlays_dir
}

main_build_distro() {
	export logTag=pscg_builder

	build_distro__source_build_configs
	build_distro__source_shell_scripts
	call_if_exists build_distro__source_distro_specific_configs
	build_distro__prebuild_post_sourcing_sanity_checks
	build_distro__make_working_directories_structure

	build_distro_reuse_materials_wrapper
	build_distro_reuse_build_src_and_arch_wrapper

	bsp_linux__set_console_device_by_target_architecture # Call early enough, as it is used by the configuration files of several components

	if [ "$config_buildtasks__do_build_rootfs" = "true" ] ; then
		build_distro__highlight_major_step_in_log "Rootfs - prepass"
		if [ "$config_buildtasks__do_build_rootfs_caches_and_quit" = "true" ] ; then
			# This is an hacky addition to allow prebuilding all caches, e.g. before a flight, or when
			# evaluating a new distro version, or a completely new set of tasks.
			# Since the caches are built during a build anyhow, if some packages don't exist, etc., it's nice
			# to know that ahead of time, and then one can also run the build system on different distros and architectures
			# via a script, and not worry about the packages for the subsequent builds
			# In the subsequent builds, one will happily work offline with the caches.
			# I provided this feature, because it can be time consuming, and it's very easy to prepare a wrapper script, that just
			# does that (I will do so in the helpers, for a set of architectures and distros)
			info_do_or_die ${config_distro}_build_rootfs_pre_pass
			exit 0;
		fi

		info_do_or_die ${config_distro}_build_rootfs_pre_pass
	else
		warn "Skipping rootfs due to user's request"
	fi

	if [ "$config_buildtasks__do_build_kernel" = "true" ] ; then
		build_distro__highlight_major_step_in_log "Kernel"
		banner_and_do kernel__build_linux_kernel || fatalError "Failed to build Linux kernel"
	else
		warn "Skipping Linux kernel building due to user's request"
	fi

	if [ "$config_buildtasks__do_build_kernel_dtbs" = "true" ] ; then
		build_distro__highlight_major_step_in_log "Kernel dtbs"
		banner_and_do kernel__do_dtbs_install
	fi

	if [ "$config_buildtasks__do_build_ramdisk" = "true" ] ; then
		build_distro__highlight_major_step_in_log "initramfs"
		# We build the swissknife before, whether it is, or is not a part of a rootfs (can be reused)
		# so that we will not need separate passes for packing the initramfs
		banner_and_do $LAYERS_DIR/common/recipes/$config_ramdisk__shell_swissknife/build-$config_ramdisk__shell_swissknife.sh     || fatalError "build-$config_ramdisk__shell_swissknife failed"
		banner_and_do $LAYERS_DIR/common/recipes/ramdisk/build-initramfs.sh buildonlydontrepack    || fatalError "build-initramfs failed"
		# if the ramdisk is interested in some additional kernel modules, it will make sure to do it itself.
		# the reason is selectiveness
	else
		warn "Skipping initramfs building due to user's request"
	fi


	if [ "$config_buildtasks__do_build_rootfs" = "true" ] ; then
		build_distro__highlight_major_step_in_log "Rootfs"
		build_distro__cleanup_overlay_tarballs
		build_distro__add_rootfs_layers
		build_distro__add_more_layers_and_recipes
		build_distro__add_kernel_modules_to_rootfs || fatalError "Failed to add modules to rootfs. Did you forget to build your kernel?"
		build_distro__add_firmware_to_rootfs
		info_do_or_die ${config_distro}_build_rootfs_post_pass
	else
		# note to reviewrs - this is ugly for a reason, quick and dirty ' vs !  handling using natural concatenation... ugly style, but working and regex less
		warn "Skipping adding the rootfs layers. If you don't know what you are doing this may give you hard time at run time, \x1b[06mtake heed"'!'"\x1b[0m"
	fi

	#
	# Add a chance for a second repacking to the ramdisk.
	# The reason for this, is allowing all kinds of BSP layers to decide for themselves whether they want to add some things
	# to the initramfs, or to the rootfs, or both, and do it directly. If they do it for the rootfs, it's taken care of
	# If they do it in the rootfs and the initramfs as well (e.g. directly copy firmware files, build more external modules, etc.),
	# we will just repack the initramfs again and that's it.
	# For this reason, we will populate the selected firmware and modules here, and not prior to it

	if [ "$config_buildtasks__do_build_ramdisk" = "true" ] ; then
		build_distro__highlight_major_step_in_log "initramfs-modules-firmware-repack"
		add_firmware_to_initramfs
		build_distro__add_kernel_modules_to_initramfs || fatalError "Failed to add modules to rootfs. Did you forget to build your kernel?"
		banner_and_do $LAYERS_DIR/common/recipes/ramdisk/build-initramfs.sh repackonly     || fatalError "build-initramfs failed"
	fi

	if [ "$config_buildtasks__do_build_bootloaders" = "true" ] ; then
		build_distro__highlight_major_step_in_log "Bootloaders"
		hardWarn "This is where you will call a BSP specific bootloader code (U-Boot, GRUB, extlinux etc.)"
		info_do_or_die bsp__do_build_boot_firmware
	else
		warn "Skipping bootloader building"
	fi

	if [ "$config_buildtasks__do_build_boot_firmware" = "true" ] ; then
		build_distro__highlight_major_step_in_log "Boot firmware"
		hardWarn "This is where you will call a BSP specific boot firmware (BIOS, Arm Trusted Firmware, UEFI firmware (and bootloader), OpenSBI firmware [and bootloader] etc.) "
		info_do_or_die bsp__do_build_boot_firmware
	else
		warn "Skipping boot firmware building"
	fi

	build_distro__run_more_commands_before_image_packing

	if [ "$config_buildtasks__do_pack_images" = "true" ] ; then
		build_distro__highlight_major_step_in_log "Image"
		banner_and_do $LAYERS_DIR/common/recipes/image/pack-image.sh || fatalError "Failed to pack the image"
	fi

	if [ "$config_buildtasks__do_generate_qemu_scripts" = "true" ] ; then
		build_distro__highlight_major_step_in_log "QEMU scripts"
		banner_and_do $LAYERS_DIR/bsp/recipes/linux/common-qemu/generate-qemu-scripts.sh || fatalError "Failed to generate QEMU scripts"
	fi


	info done

}
