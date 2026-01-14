#!/bin/bash
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
	logTag="common-build-kernel"

	kernel__common_init_fetch_unpack_variables
	call_if_exists init_env_bsp_kernel
	call_if_exists specific_init_fetch_unpack_variables

	debug "Building the Linux kernel: \n--> src: $LINUX_SOURCE_DIR \n--> build: $LINUX_BUILD_DIR \n--> install $LINUX_INSTALL_DIR \nARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE"

	# We create some directories as soon as we can, and others only after unpacking (as they may need to set up links)
	if [ ! -d "$KERNEL_BUILD_WORKING_DIRECTORY" ] ; then
		verbose_do_or_die mkdir $KERNEL_BUILD_WORKING_DIRECTORY
	fi

	if [ ! -d "$LINUX_BUILD_DIR" ] ; then
		mkdir $LINUX_BUILD_DIR || fatalError "Cannot create $LINUX_BUILD_DIR"
	fi
	if [ ! -d "$LINUX_INSTALL_DIR" ] ; then
		mkdir $LINUX_INSTALL_DIR || fatalError "Cannot create $LINUX_INSTALL_DIR"
	fi

	debug "config_kernel__git_repo_uri=$config_kernel__git_repo_uri config_kernel__commit=$config_kernel__commit config_kernel__kernel_config_src_path=$config_kernel__kernel_config_src_path config_kernel__kernel_config_out_name=$config_kernel__kernel_config_out_name" # TODO: probably remove most

	verbose "Building for ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE"
	logTag=$prevLogTag
}

# Should not be overridden
do_fetch() {
	local prevLogTag=$logTag
	logTag="common-build-kernel"
	base_do_fetch
	logTag=$prevLogTag
}

# Should not be overridden
do_unpack() { # TODO: fix all logs / errors if there is something ( i.e. { vs ( - if it's { then doing these logtags is OK })})
	local prevLogTag=$logTag
	logTag="common-build-kernel"
	if [ "$config_kernel__fetch_git_or_tarball" = "tarball" -a -d $LINUX_SOURCE_DIR ] ; then
		# note that we check only for tarball outside of the function, as the base implementation allows untarring on top of a current one, to allow
		# the implementation select what to do (keep, remove, add to tarball and let it override, etc.)
		# the base implementation assumes that unpacking in git will happen only if the folder does exist already
		verbose "$LINUX_SOURCE_DIR exists. Skipping tarball unpacking"
	else
		base_do_unpack
	fi
	logTag=$prevLogTag
}

#
# Add config fragments to a current configuration
# $1 kernel build directory
#
do_config_fragments() {
	local dst=$1
	if [ -z "$config_kernel__list_of_config_fragments" ] ; then
		return
	fi
	if [ "$config_kernel__config_fragments_build_strategy" = "merge_config" ] ; then
		(
		cd $dst
		debug_do_or_die ./source/scripts/kconfig/merge_config.sh .config $config_kernel__list_of_config_fragments
		)
	else
		error "config_kernel__config_fragments_build_strategy=$config_kernel__config_fragments_build_strategy is not supported."
		return 1
	fi
}

do_config_overrides() {
	local dst=$1
		if [ -z "$config_kernel__list_of_config_overrides" ] ; then
		return
	fi
	(
	cd $dst

	# Split config_kernel__list_of_config_overrides into array, respecting quoted values
	eval "local arr=($config_kernel__list_of_config_overrides)"
	if [ "$config_kernel__configs_overrides_build_strategy" = "config" ] ; then
		for i in "${arr[@]}" ; do
			key="${i%%=*}"
			value="${i#*=}"
			debug_do_or_die ./source/scripts/config --set-val "$key" \"$value\"
		done

		# Optional: uncomment this if the list of config is not full, and you want to risk
		# not having your right configs. Remember, this method does not update dependencies, so
		# it is very hard to debug!
		# debug_do_or_die make olddefconfig
	elif [ "$config_kernel__configs_overrides_build_strategy" = "fragment" ] ; then
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
		fatalError "Please set config_kernel__configs_overrides_build_strategy to either config or fragment (please don't use $config_kernel__configs_overrides_build_strategy)"
		# One could implement the sed strategy, but it is error prone, doesn't do anything related to dependencies, and it's better to not do it at all
	fi
	)

}

#
# configure the kernel
# [$1] and optional directory where the configuration would happen. This was added to support an educational step of modules_prepare
#
do_config() {
	local dst=${1:-$LINUX_BUILD_DIR}
	if [ -n "$config_kernel__kernel_config_src_path" ] ; then
		verbose "copying: $config_kernel__kernel_config_src_path --> $dst/.config"
		[ -d $dst ] || mkdir $dst
		cp $config_kernel__kernel_config_src_path $dst/.config || fatalError "Could not copy kernel config file"
		verbose "Running olddefconfig on $dst/.config"
		make -C $LINUX_SOURCE_DIR O=$LINUX_BUILD_DIR olddefconfig || fatalError "Failed to make olddefconfig"
	else
		hardWarn "No config_kernel__kernel_config_src_path provided. For now reverting to config_kernel__list_of_defconfigs"
		debug_do_or_die make -C $LINUX_SOURCE_DIR O=$dst $config_kernel__list_of_defconfigs
	fi

	add_firmware_to_kernel_builtin $dst
	debug_do_or_die do_config_fragments $dst
	debug_do_or_die do_config_overrides $dst

	# Sanity check for some items that can be tricky
	if ! kernel__common_check_config_sanity	$dst/.config ; then
		if [ "$config_kernel__autoadd_tricky_and_required_config_items" = "true" ] ; then
			verbose "Redoing config overrides after adding them. You should add to a more persistent config fragment or custom connfiguration file once you are dont testing"
			debug_do_or_die do_config_overrides $dst
		elif [ "$config_kernel__fail_on_missing_tricky_and_required_config_items" = "true" ] ; then
			error "You are missing some tricky configuration options. You should add them, or opportunisticly try to build with config_kernel__autoadd_tricky_and_required_config_items=true"
			fatalError "Failing build since config_kernel__fail_on_missing_tricky_and_required_config_items is true"
		fi
	fi
}

# Should not be overridden
do_make() {
	local prevLogTag=$logTag
	logTag="common-build-kernel"
	info Building the kernel proper...
	# Build the kernel
	make -C $LINUX_SOURCE_DIR O=$LINUX_BUILD_DIR olddefconfig || fatalError "Failed to make olddefconfig"
	verbose_do_or_die make -C $LINUX_SOURCE_DIR O=$LINUX_BUILD_DIR -j$(nproc) || fatalError "Kernel build failed"
	info Done building the kernel proper
	logTag=$prevLogTag
}

# Should be overridden
do_make_out_of_tree_modules() {
	:
}


#
# Do kernel modules install. You are not necessarily required to run this one.
# If you have loadable kernel modules as part of the in-tree kernel, this will install them
# to a working directory
kernel__do_modules_install() {
	if [ ! "$config_kernel__do_modules" = "true" ] ; then
		warn "User opted out of building and packing the kernel modules"
		return
	fi
	local prevLogTag=$logTag
	logTag="common-build-kernel"

	verbose_do_or_die make  -C $LINUX_SOURCE_DIR O=$LINUX_BUILD_DIR modules_install INSTALL_MOD_PATH=$kernel__modules_install_workdir

}
export -f kernel__do_modules_install

#
# Do kernel modules install. You are not necessarily required to run this one.
# If you have loadable kernel modules as part of the in-tree kernel, this will install them
# to a working directory, and pack the working directory.
# You can then copy the contents of that directory or unpack the resulting tarball onto a rootfs (whether a rich one or a ramdisk),
# or copy selective modules from there (which you could do directly from the kernel build out if you wanted to, but that's not the desired practice)
#
kernel__do_modules_install_and_pack_workdir() {
	if [ ! "$config_kernel__do_modules" = "true" ] ; then
		warn "User opted out of building and packing the kernel modules"
		return
	fi
	local prevLogTag=$logTag
	logTag="common-build-kernel"
	kernel__do_modules_install
	info "Creating modules_install tarballs"
	verbose_do_or_die tar -C $kernel__modules_install_workdir -czf $kernel__modules_install_tarball .
	logTag=$prevLogTag
}
export -f kernel__do_modules_install_and_pack_workdir

#
# Careful: This is NOT one of the essential build steps.
# Prepare kernel headers. This is not required for building the kernel or the image, but can be useful if you export it to developers
# without requiring to export the entire build dir
#
kernel__do_headers_install_and_pack_workdir() {
	make  -C $LINUX_SOURCE_DIR O=$LINUX_BUILD_DIR headers_install INSTALL_HDR_PATH=$kernel__headers_install_workdir
	verbose_do_or_die tar -C $kernel__headers_install_workdir -czf $kernel__headers_install_tarball .
}
export -f kernel__do_headers_install_and_pack_workdir

#
# Careful: This is NOT one of the essential build steps.
# This one is educationally useful if you DO NOT wish to build the entire kernel, but just preapre it for linking.
#		   you must run this after mkfconfig
# Prepare a folder tree for external module building. This is not required for building the kernel or the image, but can be useful if you export it to developers
# without requiring to export the entire build dir, if the user knows what they are doing.
# NOTE: If so, and they are in control they can use KBUILD_MODPOST_WARN=1 when building oot modules against this directory,
# 		and not requiremay a kernel build directory, therefore saving space, but it is not recommended, and the specific
#		error as warning statement (KBUILD_MODPOST_WARN) is for a reason
#
kernel__do_modules_prepare_and_pack_workdir() {
	# Before preparing a folder for oot module build, one must configure it
	if [ ! -d $kernel__modules_prepare_workdir ] ; then
		verbose_do_or_die mkdir -p $kernel__modules_prepare_workdir
		verbose_do_or_die do_config $kernel__modules_prepare_workdir
	fi
	# then they can prepare the modules
	make  -C $LINUX_SOURCE_DIR O=$kernel__modules_prepare_workdir modules_prepare || fatalError "Failed to modules_prepare. (did you run this after configuring?)"
	verbose_do_or_die tar -C $kernel__modules_prepare_workdir -czf $kernel__modules_prepare_tarball .
}
export -f kernel__do_modules_prepare_and_pack_workdir

# Should be overridden
do_make_install() {
	if type kernel__specific_do_make_install &>/dev/null ; then
		# TODO: sparc64 was added last moment. This was added to accomodate for it.
		# There would not be an if/else otherwise, but I don't have the time to change ARCH now or add the mechanism as there was a huge source/call refactoring
		kernel__specific_do_make_install
		return
	fi

	cp ${LINUX_BUILD_DIR}/.config ${LINUX_INSTALL_DIR}/$config_kernel__kernel_config_out_name

	# copy kernel files to the boot partition
	cp ${LINUX_BUILD_DIR}/arch/$ARCH/boot/$config_kernel__kernel_image_type ${LINUX_INSTALL_DIR}/ || fatalError "Failed to copy kernel image to the install dir"

	cp $LINUX_INSTALL_DIR/$config_kernel__kernel_image_type $BOOT_DIR/$config_kernel__kernel_image_type || fatalError "Failed to copy kernel image to $BOOT_DIR"
	cp $LINUX_INSTALL_DIR/$config_kernel__kernel_config_out_name $BOOT_DIR/ || error "Failed to copy the kernel config to $BOOT_DIR. It is negligible"

	call_if_exists do_install_dtbs
}

#
# Do a depmod step to account for out of tree built modules.
# This can be done on first boot, but there is no reason to not do it on build time.
#
# $1 target rootfs directory - we could just install to the ROOTFS_DIR - but you may want to install modules and dempod them in a ramdisk, so we are flexible here.
#
kernel__do_cross_depmod() {
	local target_dir=$1
	if [ ! -d $target_dir/lib/ ] ; then
		fatalError "$target_dir/lib does not exist. You must set up a reasonable root filesystem if you want to install modules"
	fi
	read depmod_kv < $LINUX_BUILD_DIR/include/config/kernel.release
	info "Running cross depmod: $depmod_kv --> $target_dir"
	sudo depmod -b $target_dir -F $LINUX_BUILD_DIR/System.map  $depmod_kv || fatalError "Cannot depmod $depmod_kv."
}
export -f kernel__do_cross_depmod

#
# Build Linux kernel. This is generic enough to support all reasonable derivations.
# If you would like to change its behavior in a BSP, you may define a function with the same name, and make sure you source it
# after this file
#
# In general the idea is: source specific configs before non specific configs (to allow conditional assigning which we use a lot)
# and source specific "function files" after the most specific ones, so that the functions are overridden (although some recipes may use some sort of a "template method" instead)
#
kernel__build_linux_kernel() {
	init_env
	info_do_or_die do_fetch
	info_do_or_die do_unpack
	if [ ! "$config_kernel__rebuild_kernel" = "false" ] ; then
		info_do_or_die do_config
		info_do_or_die do_make
	else
		if [ ! -e $LINUX_BUILD_DIR/.config ] ; then
			fatalError "You tried to save time with config_kernel__rebuild_kernel=false but it seems like you have not built your kernel"
		fi
	fi

	info_do_or_die do_make_install

	info "Done"
}
export -f kernel__build_linux_kernel
