#!/bin/bash

# Usage:  <value>
#
# Does not verify input validity, so be careful when using it
# We could add several functions to do something like  foo a b and set a to b - but this would require too much explanation of bash stuff
# so we keep it simple - usage is by echoing te result
#
# $1: value
#
#
set_true_false_by_value() {
		case $1 in
		"") fatalError "Must provide a value" 	;;
			1|true|y|Y) echo -n "true"      	;;
			0|false|n|N) echo -n "false" 		;;
			*) fatalError "Please provide a proper value" ;;
        esac
}

init_env() {
	: ${logFile=${TMP_TOP}/$(basename $0).log} # allow running the script independently and yet allowing -u in older builds
	: ${logTag=devbuild} # allow running the script independently and yet allowing -u) in older builds

	busybox__common_init_fetch_unpack_variables

	# Same as the mini workshop format:
	fetch=true
	untar=true
	config=true
	build=true
	removeprev=true
	install=true

	for arg in $@ ; do
		case $arg in
			dontfetch)      fetch=false     ;;
			dontuntar)      untar=false     ;;
			dontconfig)     config=false    ;;
			dontbuild)      build=false     ;;
			dontremoveprev) removeprev=false;;
			dontinstall) 	install=false;;
		esac
	done

	# based on environment variables as before - this will take precedence if any is 0. One of the methods will be cancelled, I'm just merging several for a start
	# to demonstrate trivial vs. not so trivial ramdisks. This is the less trivial one.
	# we still don't use the new ones so this is mostly a preparation

	# This is redundant - I just want to keep the ramdisk script easy and independent to use from command line so I provided arguments
	# These environment variables supersede it
	fetch=$(set_true_false_by_value $config_busybox__do_fetch)
	untar=$(set_true_false_by_value $config_busybox__do_unpack)
	build=$(set_true_false_by_value $config_busybox__do_make)
	config=$(set_true_false_by_value $config_busybox__do_config)
	removeprev=$(set_true_false_by_value $config_ramdisk_removeprev)
	install=$(set_true_false_by_value $config_ramdisk_install)
}

#unused
do_clean() {
	# TODO: can clean by phases, to make things easier, but I won't do it now. Too much work for some illustrations...
	#		examples: do_clean_fetch do_clean_config do_clean_make do_clean_install
	#		and then according to some flags can select which "clean target" to apply
	rm -rf $BUSYBOX_BUILD_DIR
	rm -rf $BUSYBOX_INSTALL_DIR
	rm -rf $BUSYBOX_SOURCE_DIR
}


init_folders() {
	set -euo pipefail
	mkdir -p $BUSYBOX_BUILD_WORKING_DIRECTORY
	if [ -d $BUSYBOX_INSTALL_DIR ] ; then
		warn "$BUSYBOX_INSTALL_DIR already exists. "

		# devhack will just skip everything. You could otherwise just avoid the removeprev clause - which is probably what I should do now that busybox is separated. But I will need to take care of caches TODO
		[ "$config_busybox__allow_useprevbuild_devhack" = "true" ] && devhack_skip_doing_things_if_they_exist # speed things up, without managing caches, I don't want to add a mechanism for anything that is not the debos rootfs right now...

		if [ $removeprev = true ] ; then
			dod rm -rf $BUSYBOX_INSTALL_DIR
		fi
	fi
	set +euo pipefail
}

do_fetch() (
	if [ ! $fetch = true ] ; then return ; fi
	local prevLogTag=$logTag
	logTag=build-busybox
	base_do_fetch
	logTag=$prevLogTag
)

do_unpack() (
	if [ ! $untar = true ] ; then return ; fi
	local prevLogTag=$logTag
	logTag=build-busybox
	if [ "$config_busybox__fetch_git_or_tarball" = "tarball" -a -d $BUSYBOX_SOURCE_DIR ] ; then
		# note that we check only for tarball outside of the function, as the base implementation allows untarring on top of a current one, to allow
		# the implementation select what to do (keep, remove, add to tarball and let it override, etc.)
		# the base implementation assumes that unpacking in git will happen only if the folder does exist already
		verbose "$BUSYBOX_SOURCE_DIR exists. Skipping tarball unpacking"
	else
		base_do_unpack
	fi

	logTag=$prevLogTag
)

do_config() (
	if [ ! "$config" = true ] ; then return ; fi
	if [ "$config_busybox__do_config_if_already_built" = "false" -a -e "${BUSYBOX_BUILD_DIR}/.config" ] ; then
		verbose "Skipping busybox configuration since ${BUSYBOX_BUILD_DIR}/.config exists and  config_busybox__do_config_if_already_built is false"
		return
	fi
	verbose "Configuring busybox..."
	# Configure busybox
	mkdir -p $BUSYBOX_BUILD_DIR  || fatalError "Failed to create $BUSYBOX_BUILD_DIR"
	if [ "$config_busybox__use_config_file" = "true" ] ; then
		cp ${BUSYBOX_CONFIG_FILE} ${BUSYBOX_BUILD_DIR}/.config || fatalError "Failed to copy busybox config"
	else
		verbose_eval_or_die $busybox_build_flags make -C $BUSYBOX_SOURCE_DIR O=$BUSYBOX_BUILD_DIR $BUSYBOX_DEFCONFIG
		sed -i 's:# CONFIG_STATIC is not set:CONFIG_STATIC=y:' $BUSYBOX_BUILD_DIR/.config || fatalError "Failed to make the busybox config static"
		sed -i 's:CONFIG_TC=y:CONFIG_TC=n:' $BUSYBOX_BUILD_DIR/.config || fatalError "Failed to unset CONFIG_TC which is known to not to not work (build) in linux kernel > v6.7"
	fi
)

do_make() (
	if [ ! $build = true ] || [ "$config_busybox__do_install" = "true" ] ; then
		return
	fi
	verbose "Building busybox without installing..."
	verbose_eval_or_die $busybox_build_flags make -C $BUSYBOX_BUILD_DIR -j$(nproc)
)

do_make_install() (
	# We will consider "install" without building as rebuilding busybox this way or another
	if [ ! "$config_busybox__do_install" = "true" ] ; then
		return
	fi
	verbose "Building and installing busybox..."
	mkdir -p $BUSYBOX_INSTALL_DIR || fatalError "Failed to create $BUSYBOX_INSTALL_DIR"
	verbose_eval_or_die $busybox_build_flags make -C $BUSYBOX_BUILD_DIR CONFIG_PREFIX=$BUSYBOX_INSTALL_DIR install -j$(nproc)
)

devhack_skip_doing_things_if_they_exist() {
	debug "ASSUMING THAT IF YOUR OUTPUT FILES EXIST - YOU ARE NOT INTERESTED IN REBUILDING BUSYBOX"
	# This is ABSOLUTELY not how a build system looks like, but for our purposes, it is
	# a fantastic hack because we only need to build busybox once, and the config step is lengthy
	# if a rebuild is required - well, just rebuild busybox!
	if [ -f "$BUSYBOX_INSTALL_DIR/bin/busybox" ] ; then
		hardDebug "Skipping busybox rebuilding. If you don't want that, unset config_busybox__allow_useprevbuild_devhack"
		commonScriptEpilogue
		exit 0
	fi
}

#
### Specific tratements for building busybox for i386
# Note that most distros provide cross-toolchains - but they conflict with gcc-multilib. So it's better
# to crosscompile for x86 32 bits.
#
# Also note that busybox does not care at all about ARCH - it cares about CROSS_COMPILE.
#
set_toolchain_flags_if_necessary() {
	prev_cppflags=$CPPFLAGS
	prev_cflags=$CFLAGS
	prev_ldflags=$LDFLAGS

	if [ "$ARCH" = "i386" -o "$ARCH" = "x86" ] && [ -z "$CROSS_COMPILE" ] ; then
		warn "Building 32 bit busybox without a cross compiler. Assuming you have multilib installed, otherwise you will fail"
		warn "Some heuristics for you would be to check if you have /usr/<x86-toolchain>/  or /usr/include/<x86-toolchain> If not, busybox will fail building on include <asm/errno.h>"
		CFLAGS="$CFLAGS -m32"
		LDFLAGS="$LDFLAGS -m32"
		busybox_build_flags="CFLAGS=-m32 LDFLAGS=-m32"
	else
		busybox_build_flags=""
	fi
}
restore_prev_toolchain_flags_if_necessary() {
	CPPFLAGS=$prev_cppflags
	CFLAGS=$prev_cflags
	LDFLAGS=$prev_ldflags
}

#
# main busybox builder function
#
main() {
	init_env $@
	dod init_folders
	verbose "Building busybox..."

	info_do_or_die do_fetch
	cd $BUSYBOX_BUILD_WORKING_DIRECTORY	|| fatalError "Cannot chdir to $BUSYBOX_BUILD_WORKING_DIRECTORY"
	info_do_or_die do_unpack

	set_toolchain_flags_if_necessary
	info_do_or_die do_config
	info_do_or_die do_make
	info_do_or_die do_make_install

	restore_prev_toolchain_flags_if_necessary
}

commonScriptPrologueLogRunAndEpilogue $@