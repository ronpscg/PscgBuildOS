
init_env() {
	source_file_or_die $LOCAL_DIR/qemu.buildconfig # not needed as everything there is supposed to be exported, but doesn't hurt

	MORE_USAGE_RECOMMENDATIONS="" # Add some warnings on common pitfalls before exiting this script.
	MORE_USAGE_RECOMMENDATIONS_IN_RUNQEMU="" # ditto propagate to the run-qemu.sh script itself
}

decide_storage_device_size_by_image_materials_or_partition_sizes() {
	local ramdisk_partition_emmc_config_file=$RAMDISK_DIR/flasher/config/partitions-emmc.config
	local partitions_emmc_config_file=""
	# If an image is being reused
	if [ -d "$config_distro__prebuilt_image_materials_workdir" \
	     -a "$config_buildtasks__do_build_ramdisk" = "false" \
		 -a -f "$distro__prebuilt_partitions_emmc_config_file_for_imager_estimation" \
	   ] ; then
		partitions_emmc_config_file=$distro__prebuilt_partitions_emmc_config_file_for_imager_estimation
	elif [ -f "$imager__target_partition_defs_generator" -a -f "$ramdisk_partition_emmc_config_file" ] ; then
		partitions_emmc_config_file=$ramdisk_partition_emmc_config_file
	elif [ -n "$config_bsp__qemu_storage_device_size_mib" ] ; then
		verbose "Using provided storage device size $config_bsp__qemu_storage_device_size_mib MiB\n$(printvars config_bsp__qemu_storage_device_size_mib partitions_emmc_config_file config_distro__prebuilt_image_materials_workdir config_buildtasks__do_build_ramdisk imager__target_partition_defs_generator)"
		return
	else
		fatalError "Unable to decide storage device size\n$(printvars config_bsp__qemu_storage_device_size_mib partitions_emmc_config_file config_distro__prebuilt_image_materials_workdir config_buildtasks__do_build_ramdisk imager__target_partition_defs_generator)"
	fi

	# Check the provided hint size, and adjust if needed.
	# This works well also if config_bsp__qemu_storage_device_size_mib is not provided
	. $partitions_emmc_config_file || fatalError "Could not source $RAMDISK_DIR/flasher/config/partitions-emmc.config"
	trivial_installer_size_sanity_checks
	if [ $ballpark_required_storage_bytes -gt $(($bs * config_bsp__qemu_storage_device_size_mib)) ] ; then
		warn "Your selected size $config_bsp__qemu_storage_device_size_mib is not enough. You want to set config_bsp__qemu_storage_device_size_mib to at least $(($ballpark_required_storage_bytes/1024/1024 + 1))"
		if [ "$config_bsp__qemu_storage_device_size_autoadjust" = "true" ] ; then
			info "Auto adjusting your storage size"
			count=$(($ballpark_required_storage_bytes/1024/1024 + 1))
		fi
	fi
}

create_storage_device() {
	if [ ! "$config_bsp__qemu_recreate_storage_device" = "true" ] ; then
		if [ -z "$config_bsp__qemu_storage_device_path" ] ; then
			MORE_USAGE_RECOMMENDATIONS+="\e[33;40mYou you did not provide (on build time) config_bsp__qemu_storage_device_path. You will have to take care of your own storage\e[0m\n"
		elif [ ! -f "$config_bsp__qemu_storage_device_path" ] ; then
			MORE_USAGE_RECOMMENDATIONS+="\e[33;40mYou chose to set config_bsp__qemu_recreate_storage_device=false (on build time), and your file does not exist. You must dd/fallocate/copy/etc. $config_bsp__qemu_storage_device_path yourself\e[0m\n"
		fi
		MORE_USAGE_RECOMMENDATIONS_IN_RUNQEMU+="$MORE_USAGE_RECOMMENDATIONS"
		return
	fi
	# We'll be very simple here, although we can use qcow format etc... won't do now
	if [ -z  "$config_bsp__qemu_storage_device_path" ] ; then
		fatalError "Please provide a (default) storage device path"
	fi

	local bs=$((1024*1024))
	count=$config_bsp__qemu_storage_device_size_mib

	decide_storage_device_size_by_image_materials_or_partition_sizes

	info "Creating storage device..."
	verbose_do_or_die dd if=/dev/zero of=$config_bsp__qemu_storage_device_path bs=$bs count=$count
}

copy_removable_device_if_needed() {
	if [ ! "$config_bsp__qemu_copy_installer_image_to_removable_media" = "true" ] ; then
		local warningstring="QEMU scripts will use the installer image ($config_imager__installer_image_file). Careful if you want to modify and reuse it or distribute the image"
		warn $warningstring
		MORE_USAGE_RECOMMENDATIONS_IN_RUNQEMU+="\e[33;40m$warningstring\e[0m"
		config_bsp__qemu_removable_media_path=$config_imager__installer_image_file
		return
	fi

	info "Copying storage device..."
	verbose_do_or_die cp $config_imager__installer_image_file $config_bsp__qemu_removable_media_path

}


#: \${KERNEL_IMAGE=$bootdir/$imagetype}
#	: \${RAMDISK_IMAGE=$bootdir/initramfs.cpio.gz}

create_qemu_env() {
	local qemuenvfile=$config_bsp__qemu_generated_runqemu_folder/qemu.env
	cat << EOF > $qemuenvfile
	: \${bootdir=$distro__image_materials_installables_bootfs_dir}
	: \${config_distro=${config_distro}}
	: \${ARCH=$ARCH}
	: \${BIOSPARAMS=${config_bsp__qemu_prebuilt_bios:+-bios $config_bsp__qemu_prebuilt_bios}}
	: \${EMMC_IMAGE_FILE=$config_bsp__qemu_storage_device_path}
	: \${INSTALLER_IMAGE=$config_bsp__qemu_removable_media_path}
	: \${MACHINE=$config_bsp__qemu_machine}
	: \${CPU=$config_bsp__qemu_cpu}
	: \${SMP=$config_bsp__qemu_smp}
	: \${MEMORY=$config_bsp__qemu_memory}

	: \${CMDLINE_CONSOLE="console=$CONSOLE_DEV_TTY"}
	: \${CMDLINE_GRAPHICS=""}
	: \${CMDLINE_NETWORK="net.ifnames=0"}
	: \${CMDLINE_RAMDISK_DEFAULT_SETTINGS="pscgrd.hw.bsp=qemu pscgrd.net.autotelnet=true"}

	: \${config_ramdisk__compression=$config_ramdisk__compression}

	: \${USE_VIRTIO_FOR_STORAGE_DEVICES=$config_bsp__qemu_storage_use_virtio}
	: \${USE_VIRTIO_FOR_CONSOLE_DEVICES=$config_bsp__qemu_console_use_virtio}
	: \${USE_VIRTIO_FOR_NETWORK_DEVICES=$config_bsp__qemu_network_use_virtio}

	: \${CONSOLEPARAMS_0="$config_bsp_qemu__devices_console_params"}
	: \${GRAPHICSPARAMS_0="$config_bsp_qemu__devices_graphics_params"}
	: \${AUDIOPARAMS_0="$config_bsp_qemu__devices_audio_params"}
	: \${INPUTPARAMS_0="$config_bsp_qemu__devices_input_params"}
	: \${NETWORKPARAMS_0="$config_bsp_qemu__devices_network_params"}
	: \${MOREDEVICESPARAMS_0="$config_bsp_qemu__devices_more_devices_params_0"}
	: \${MOREDEVICESPARAMS_1="$config_bsp_qemu__devices_more_devices_params_1"}
	: \${CMDLINE="$config_bsp_qemu__kernel_cmdline"}
	: \${COMPLETE_COMMAND_LINE_OVERRIDE="$config_bsp_qemu__complete_command_line_override"}

	# These are handled in other scripts, and left here to discuss some things that are not the common installer flow
	: \${ROOTFS_IMAGE=xy}
	: \${ROOTFS_9P=xyz}
	: \${RAMDISK_9P=vwt}

	: \${MORE_USAGE_RECOMMENDATIONS_IN_RUNQEMU="$MORE_USAGE_RECOMMENDATIONS_IN_RUNQEMU"}

EOF
	[ $? = 0 ] || fatalError "Could not populate $qemuenvfile"

	# More additions that may be less standard or require on more conditions
	if [ "$config_bsp_qemu_kernel_image_use_vmlinux" = "true" ] ; then
		echo -e "	: \${KERNEL_IMAGE=$LINUX_BUILD_DIR/vmlinux}" >> $qemuenvfile	|| fatalError "Could not populate $qemuenvfile"
	fi

	info "successfull populated $qemuenvfile"
}

#
# The objective of this function is to allow a quick tester to very quickly copy paste some things that were either previously split
# or did not appear, to give a quick testing facility, without exploring the generated scripts (which is the recommended path of action!)
#
quick_usage_recommendations() {
	hardWarn "You may want to modify the qemu.env file to suit your needs."
	warn  "Some running recommendations:
- If you want to have the installer image \"inserted\" or removed you must follow the params there. Running the scripts will give you more information
"
if [ -n "$config_bsp__qemu_livecd_storage_device_path" ] ; then
	if [ ! -f "$config_bsp__qemu_livecd_storage_device_path" ] ; then
		 "Careful - config_bsp__qemu_livecd_storage_device_path points to a non existing path! This should not be possible, and the build would have failed earlier, unless you are toying around and change things!"
	fi
	warn "- If you want to use a livecd:
  EMMC_IMAGE_FILE=$config_bsp__qemu_livecd_storage_device_path $config_bsp__qemu_generated_runqemu_folder/run-qemu.sh
"
else
	warn "You did not set config_bsp__qemu_livecd_storage_device_path.
You can generate it yourself by copying it from $config_imager__workdir_ext_partition_images/system.img , however it is not recommended as the build system offers you
other things, e.g. should you choose to set config_bsp__qemu_livecd_extract_system_overlays_into_live_image , etc."
fi

 	info "You may run qemu [possibly after modifying the environment variables in $config_bsp__qemu_generated_runqemu_folder/qemu.env] by running the script
$config_bsp__qemu_generated_runqemu_folder/run-qemu.sh"

	verbose "Some running examples:
  - If you want to run the installer in an A/B mode (and remember to run without the installer after that)
    CMDLINE=\"waitforremovablemedia\" $config_bsp__qemu_generated_runqemu_folder/run-qemu.sh
  - If you want to run the installer in an A only mode (best for reinstallation) (and remember to run without the installer after that)
    CMDLINE=\"waitforremovablemedia installer_a_only=true\" $config_bsp__qemu_generated_runqemu_folder/run-qemu.sh
"

	if [ -n "$MORE_USAGE_RECOMMENDATIONS" ] ; then
		warn "$MORE_USAGE_RECOMMENDATIONS"
	fi
}

copy_scripts() {
	pwd
	local scripts="run-scripts/run-qemu.sh" # relative path to LOCAL_DIR
	for f in $scripts ; do
		verbose_do_or_die cp -a $f $config_bsp__qemu_generated_runqemu_folder
	done
}


show_arch_wip_warnings() {
	case "$ARCH" in
		arm)
			warn "ARM is not properly supported on the trivial QEMU setup. You will need to do some more work (exercises...)"
			;;
		i386)
			warn "i386 is not yet properly implemented. It's relatively easy, but just note that"
			;;
	esac
}

main() {
	init_env
	show_arch_wip_warnings # We did not test some things, and we know that the easy and default storage parameters don't work in ARM so...
	info "Generating qemu scripts in $config_bsp__qemu_generated_runqemu_folder"
	if [ ! -d "$config_bsp__qemu_generated_runqemu_folder" ] ; then
		verbose_do_or_die mkdir -p $config_bsp__qemu_generated_runqemu_folder
	fi

	create_storage_device
	copy_removable_device_if_needed
	create_qemu_env
	copy_scripts
	info "Done"
	quick_usage_recommendations
}

commonScriptPrologueLogRunAndEpilogue $@
