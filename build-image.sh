#!/bin/bash
#
# This is the main builder script
#

#
# Set basic environment variables and source the top level build configuration file
#
init_env() {
	# Allow an option to provide a config=<path> and use it as a build definitions file
	if [ -n "$config" ] ; then
		. $config || { echo "$config does not refer to a real config file, or has errors" ; exit 1 ; }
		unset config
	fi

	cd $(dirname ${BASH_SOURCE[0]}) || { echo "You are running an invalid build system." ; exit 1 ; }

	# Allow setting some defaults before sourcing commonEnv.sh, so that logFile and other things will be provisioned
	# This will set: BUILD_OUT config_toplevel__product_build_dir_prefix config_toplevel__shared_build_src_dir_prefix config_toplevel__shared_build_arch_dir_prefix
	. config/toplevel.pre_commonEnv_configs.buildconfig

	# Source the top level configuration files
	. build/commonEnv.sh || { echo "You are running an invalid build system." ; exit 1 ; }

	hardInfo Welcome to the PSCG OS builder!

	source_file_or_die config/toplevel.buildconfig
	source_file_or_die config/buildtasks.buildconfig

	# validate supported distro types
	if [[ "$config_distro" =~  "pscg_" ]]  ; then
		:
	else
		fatalError "You must set config_distro (you selected: $config_distro)"
	fi

	toplevel__buildconfig_sanity_check
}

#
# Allow the printing of other distro specific environment variables before prompting the user
# this should not be here and is only here for debugging, because we do not want to source the distro specific code at this point
#
temporary_debug_print_some_distro_specific_variables() {
	# distro specific variables - temporary
	if [ "${config_distro}" = "pscg_debos" ] ; then
		printvars_sorted "config_pscgdebos__expected_debootstrap_fingerprint config_pscgdebos__recreate_debootstrap_cache_on_unmatching_fingerprints\
				config_pscgdebos__init_frameworks config_pscgdebos__network_manager\
		"
	fi
}

#
# Make sure "the users knows what they are signing for" (especially for the case of reusing or removing previous builds
#
prompt_user() {
	info "Below is an excerpt of your build configuration: "
	printvars_sorted "BUILD_OUT config_toplevel__product_build_dir_prefix config_toplevel__rebuild_from_scratch_all config_toplevel__rebuild_from_scratch_product config_distro config_buildtasks__do_build_kernel config_buildtasks__do_build_rootfs config_buildtasks__do_pack_images BUILD_IMAGE_VERSION\
		    config_toplevel__shared_artifacts \
			config_distro__prebuilt_image_materials_workdir \
			config_imager__dontformatemmc config_imager__allow_missing_system_installation config_imager__installer_runtime_recreate_partitions config_imager__installer_runtime_format_system_partition \
			config_imager__workdir config_imager__workdir_start_from_scratch config_imager__installer_workdir_start_from_scratch\
			config_imager__create_ota_image  config_imager__workdir_compressed config_imager__recovery_tarball \
			config_imager__staging_do_non_staging_stuff config_imager__list_of_image_creation_scripts_to_run\
			CROSS_COMPILE ARCH ARCH_SUBARCH_STRING config_toplevel__arch config_toplevel__arch_subarch config_toplevel__arch_before_adjusting\
			config_bsp__qemu_generated_runqemu_folder config_bsp__qemu_copy_installer_image_to_removable_media config_imager__installer_image_file config_bsp__qemu_removable_media_path config_bsp__qemu_storage_device_path \
			config_bsp__qemu_create_livecd_with_default_path_if_need_be config_bsp__qemu_create_storage_device_with_default_path_if_need_be config_bsp__qemu_recreate_storage_device\
			BUILD_DIR\
			config_toplevel__caches_workdir_base_path config_toplevel__caches_base_path config_toplevel__downloads_base_path\
	"

	verbose "In addition, there go some staging variables:"
	printvars_sorted "BUILD_SHARED_SRC_DIR BUILD_SHARED_ARCH_DIR BUILD_SHARED_ARCH_SUBARCH_DIR"
	echo

	temporary_debug_print_some_distro_specific_variables # distro specific variables - temporary	

	warn "Are you sure you would like to proceed with the build?"

	if [ "$AUTO_CONFIRM_BUILD" = "true" ] ; then
		info "Auto-confirming build"
		return
	fi

	read
	case $REPLY in
	yes|Yes|YES|y|Y|1|true)
		;;
	*)
		error "The build was cancelled by the user."
		exit 1
		;;
	esac
}

#
# Reads config_toplevel__rebuild_from_scratch_* variables and deletes folders according to them
# This must be called after the BUILD_DIR has been set by the respective distro
#
remove_previous_builds() {
	# Delete previous build directory (for all products and whatever is there) if the user asked to do so
	if [ "$config_toplevel__rebuild_from_scratch_all" = "true" ] ; then
		warn "Removing directory $BUILD_OUT"
		sudo rm -rf $BUILD_OUT && info "Removed build directory $BUILD_OUT"
	fi

	if [ "$config_toplevel__rebuild_from_scratch_product" = "true" ] ; then
		warn "Removing directory $BUILD_DIR"
		echo $BUILD_DIR
		sudo rm -rf $BUILD_DIR && info "Removed build directory $BUILD_DIR"
	fi
}

#
# Build the image/distro/ according to the overall configuration (either overridden externally, or by default in .buildconfig files)
#
build_image() {
	toplevel__set_global_ARCH_SUBARCH_variable # see notes inside that function, would be nice to rework and remove duplications
	toplevel__set_arch_and_bsp_variables
	toplevel__set_build_image_version
	local distro_src_dir=$BUILD_TOP/distros/${config_distro}

	source_file_or_die $distro_src_dir/${config_distro}.buildconfig

	info "Will build ${config_distro}: $distro_src_dir --> $BUILD_DIR"	# This shows that the last line sets BUILD_DIR according to the architecture. This will likely move the the topconfig, so I'm keeping the comment here in case this goes up before I do that.

	source_file_or_die $DISTROS_DIR/common/build-distro-common.sh

	if [ "$distro__type" = "linux" ] ; then
		source_file_or_die $DISTROS_DIR/common-linux/build-distro-common-linux.sh
	fi

	source_file_or_die $distro_src_dir/build-distro.sh
	source_file_or_die $BUILD_TOP/build/base_fetch_unpack.sh

	# temporary: they are sourced in the linux dir as well, but not exported, so it is not possible to print them. I added a couple of prints. I'll see later
	# TODO: imager.ext4images.buildconfig is only called by the installer generation script.  imager.buildconfig can either be moved to linux or to the other one
	source_file_or_die $LAYERS_DIR/common/recipes/image/imager.buildconfig
	#source_file_or_die $LAYERS_DIR/common/recipes/image/imager.ext4images.buildconfig


	if [ $(readlink -f ${BASH_SOURCE[-1]}) = $BUILD_TOP/build-image.sh ] ; then
		warn "You are running $0 directly. It is your responsibility to have filled the environment variables you wish to have"
	fi

	prompt_user

	remove_previous_builds # done conditionally depending on flags

	toplevel__make_working_directories_structure

	do_or_die main_build_distro $@
}


main() {
	init_env
	build_image
}

main $@
