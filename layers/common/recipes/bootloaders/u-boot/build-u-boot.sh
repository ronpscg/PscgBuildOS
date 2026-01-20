#!/bin/bash
#
# build-u-boot.sh  - derived from the generic build-linux-kernel.sh - removed most of the comments for brevity so you can read all explanations there
#
#
# This file is meant to be sourced by a BSP specific kernel build script.
# The specific script will reimplement some of the functions, and they are left in this file as a reference, as this is meant to serve
# mostly for educational reasons. Having said that, duplication is intentional.
#
# To help you follow some of the prints, we will use another logTag in the functions that are expected to not be overridden
#


# May be overriden with a different name (e.g. init_env_bsp_kernel in a bsp kernel build file will call this function)
# This allows a default configuration in case no one selected a build configuration (which is discouraged and is why we would fail it)
init_env() {
	local prevLogTag=$logTag
	logTag="common-build-u-boot"

	uboot__common_init_fetch_unpack_variables
	call_if_exists init_env_bsp_uboot
	call_if_exists uboot__specific_init_fetch_unpack_variables

	debug "Building U-Boot: \n--> src: $UBOOT_SOURCE_DIR \n--> build: $UBOOT_BUILD_DIR \n--> install $UBOOT_INSTALL_DIR \nARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE"	

	# We create some directories as soon as we can, and others only after unpacking (as they may need to set up links)
	if [ ! -d "$UBOOT_BUILD_WORKING_DIRECTORY" ] ; then
		verbose_do_or_die mkdir $UBOOT_BUILD_WORKING_DIRECTORY
	fi

	if [ ! -d "$UBOOT_BUILD_DIR" ] ; then
		verbose_do_or_die mkdir $UBOOT_BUILD_DIR
	fi
	if [ ! -d "$UBOOT_INSTALL_DIR" ] ; then
		verbose_do_or_die mkdir $UBOOT_INSTALL_DIR
	fi

	debug "config_uboot__git_repo_uri=$config_uboot__git_repo_uri config_uboot__commit=$config_uboot__commit config_uboot__uboot_config_src_path=$config_uboot__uboot_config_src_path config_uboot__uboot_config_out_name=$config_uboot__uboot_config_out_name"

	verbose "Building for ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE"
	logTag=$prevLogTag
}

# Should not be overridden
do_fetch() {
	local prevLogTag=$logTag
	logTag="common-build-u-boot"
	base_do_fetch
	logTag=$prevLogTag
}

# Should not be overridden
do_unpack() { # TODO: fix all logs / errors if there is something ( i.e. { vs ( - if it's { then doing these logtags is OK })})
	local prevLogTag=$logTag
	logTag="common-build-u-boot"
	if [ "$config_uboot__fetch_git_or_tarball" = "tarball" -a -d $UBOOT_SOURCE_DIR ] ; then
		# note that we check only for tarball outside of the function, as the base implementation allows untarring on top of a current one, to allow
		# the implementation select what to do (keep, remove, add to tarball and let it override, etc.)
		# the base implementation assumes that unpacking in git will happen only if the folder does exist already
		verbose "$UBOOT_SOURCE_DIR exists. Skipping tarball unpacking"
	else
		base_do_unpack
	fi
	logTag=$prevLogTag
}

#
# Add config fragments to a current configuration
# $1 uboot build directory
#
do_config_fragments() {
	local dst=$1
	if [ -z "$config_uboot__list_of_config_fragments" ] ; then
		return
	fi
	if [ "$config_uboot__config_fragments_build_strategy" = "merge_config" ] ; then
		(
		cd $dst
		debug_do_or_die ./source/scripts/kconfig/merge_config.sh .config $config_uboot__list_of_config_fragments
		)
	else
		error "config_uboot__config_fragments_build_strategy=$config_uboot__config_fragments_build_strategy is not supported."
		return 1
	fi
}

do_config_overrides() {
	local dst=$1
		if [ -z "$config_uboot__list_of_config_overrides" ] ; then
		return
	fi
	(
	cd $dst

	# Split config_uboot__list_of_config_overrides into array, respecting quoted values
	eval "local arr=($config_uboot__list_of_config_overrides)"
	if [ "$config_uboot__configs_overrides_build_strategy" = "config" ] ; then
		for i in "${arr[@]}" ; do
			key="${i%%=*}"
			value="${i#*=}"
			debug_do_or_die ./source/scripts/config --set-val "$key" \"$value\"
		done

		# Optional: uncomment this if the list of config is not full, and you want to risk
		# not having your right configs. Remember, this method does not update dependencies, so
		# it is very hard to debug!
		# debug_do_or_die make olddefconfig
	elif [ "$config_uboot__configs_overrides_build_strategy" = "fragment" ] ; then
		# Note: hasn't been tested after supporting multiple strings in a config
		local newfragment=$dst/config_overrides_fragment.config
		rm -f $newfragment # restart from scratch if exists
		for i in "${arr[@]}" ; do
			key="${i%%=*}"
			value="${i#*=}"
			if [[ ! $key =~ ^CONFIG_ ]] ; then
				warn "Fragment: Adjusting $key --> CONFIG_$key"
				key=CONFIG_$key
			fi
			echo "$key=$value" >> $newfragment
		done

		debug "Created fragment. Fragment file contents:\n$(cat $newfragment)"

		debug_do_or_die ./source/scripts/kconfig/merge_config.sh .config $newfragment
	else
		fatalError "Please set config_uboot__configs_overrides_build_strategy to either config or fragment (please don't use $config_uboot__configs_overrides_build_strategy)"
		# One could implement the sed strategy, but it is error prone, doesn't do anything related to dependencies, and it's better to not do it at all
	fi
	)

}

#
# configure the uboot
# [$1] and optional directory where the configuration would happen. This was added to support an educational step of modules_prepare
#
do_config() {
	local dst=${1:-$UBOOT_BUILD_DIR}
	if [ -n "$config_uboot__uboot_config_src_path" ] ; then
		verbose "copying: $config_uboot__uboot_config_src_path --> $dst/.config"
		[ -d $dst ] || mkdir $dst
		cp $config_uboot__uboot_config_src_path $dst/.config || fatalError "Could not copy uboot config file"
		verbose "Running olddefconfig on $dst/.config"
		make -C $UBOOT_SOURCE_DIR O=$UBOOT_BUILD_DIR olddefconfig || fatalError "Failed to make olddefconfig"
	else
		hardWarn "No config_uboot__uboot_config_src_path provided. For now reverting to config_uboot__list_of_defconfigs"
		debug_do_or_die make -C $UBOOT_SOURCE_DIR O=$dst $config_uboot__list_of_defconfigs
	fi

	debug_do_or_die do_config_fragments $dst
	debug_do_or_die do_config_overrides $dst

	# Sanity check for some items that can be tricky
	if ! uboot__common_check_config_sanity	$dst/.config ; then
		if [ "$config_uboot__autoadd_tricky_and_required_config_items" = "true" ] ; then
			verbose "Redoing config overrides after adding them. You should add to a more persistent config fragment or custom connfiguration file once you are dont testing"
			debug_do_or_die do_config_overrides $dst
		elif [ "$config_uboot__fail_on_missing_tricky_and_required_config_items" = "true" ] ; then
			error "You are missing some tricky configuration options. You should add them, or opportunisticly try to build with config_uboot__autoadd_tricky_and_required_config_items=true"
			fatalError "Failing build since config_uboot__fail_on_missing_tricky_and_required_config_items is true"
		fi
	fi
}

uboot__common_check_config_sanity() {
	:
}

# Should not be overridden
do_make() {
	local prevLogTag=$logTag
	logTag="common-build-u-boot"
	info Building the uboot proper...
	# Build the uboot
	make -C $UBOOT_SOURCE_DIR O=$UBOOT_BUILD_DIR olddefconfig || fatalError "Failed to make olddefconfig"
	verbose_do_or_die make -C $UBOOT_SOURCE_DIR O=$UBOOT_BUILD_DIR -j$(nproc) || fatalError "Kernel build failed"
	info Done building the uboot proper
	logTag=$prevLogTag
}

# Should be overridden
do_make_out_of_tree_modules() {
	:
}



# Should be overridden
do_make_install() {
	if type uboot__specific_do_make_install &>/dev/null ; then
		# TODO: sparc64 was added last moment. This was added to accomodate for it.
		# There would not be an if/else otherwise, but I don't have the time to change ARCH now or add the mechanism as there was a huge source/call refactoring
		uboot__specific_do_make_install
		return
	fi

	cp ${UBOOT_BUILD_DIR}/.config ${UBOOT_INSTALL_DIR}/$config_uboot__uboot_config_out_name

	# copy uboot files to the boot partition
	cp ${UBOOT_BUILD_DIR}/$config_uboot__uboot_image_type ${UBOOT_INSTALL_DIR}/ || fatalError "Failed to copy u-boot image to the install dir"

	# Depending on the way the hardware is expecting it, you may add additional steps such as:
	# - copying the second stage uboot to the $BOOT_DIR (in this BSP - U-Boot goes in the beginning of the memory so it's different)
	# - create a default environment (in this BSP we can decide that we keep the U-boot environment in the eMMC - as with the Android boxes that come from the manufacturers)
	#
	# The latter will be done, with a configuration patch
	#
}

#
# Build U-Boot. This is generic enough to support all reasonable derivations.
# If you would like to change its behavior in a BSP, you may define a function with the same name, and make sure you source it
# after this file
#
# In general the idea is: source specific configs before non specific configs (to allow conditional assigning which we use a lot)
# and source specific "function files" after the most specific ones, so that the functions are overridden (although some recipes may use some sort of a "template method" instead)
#
bootloaders__uboot__build_boot() {
	init_env
	info_do_or_die do_fetch
	info_do_or_die do_unpack
	if [ ! "$config_bootloaders__uboot__rebuild_uboot" = "false" ] ; then
		info_do_or_die do_config
		info_do_or_die do_make
	else
		if [ ! -e $UBOOT_BUILD_DIR/.config ] ; then
			fatalError "You tried to save time with config_uboot__rebuild_uboot=false but it seems like you have not built your uboot"
		fi
	fi

	info_do_or_die do_make_install

	info "Done"
}
export -f bootloaders__uboot__build_boot



#
# main busybox builder function
#
main() {
	init_env $@	
	verbose "Building U-Boot..."

	info_do_or_die do_fetch
	cd $UBOOT_BUILD_WORKING_DIRECTORY	|| fatalError "Cannot chdir to $UBOOT_BUILD_WORKING_DIRECTORY"
	info_do_or_die do_unpack
	
	info_do_or_die do_config
	info_do_or_die do_make
	info_do_or_die do_make_install	
}

commonScriptPrologueLogRunAndEpilogue $@