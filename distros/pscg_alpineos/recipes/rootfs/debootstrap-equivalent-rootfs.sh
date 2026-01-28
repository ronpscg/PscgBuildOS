#!/bin/bash
#
# Set up a minimal Alpine root filesystem by issuing (cross) rootfs extraction, allowing reusing previously cached rootfilesystem, for an offline and reproducible build
#
# If you are wondering about the offline builds, in fact, we can run it BEFORE having an apk cache - it doesn't even use apk update.

init_env() {
	alpineos_common_init_env # TODO everything about this and the encapsulating function name
	source $BUILD_TOP/distros/pscg_alpineos/recipes/rootfs/alpineos-common.inc # no need to hide behind variables - this is very specific to this distro
	alpineos_common_init_env
	alpineos_common_init_apk_caches_vars
	init_fetch_and_unpack_definitions
}

#
# Checks if the base alpine_rootfs already exist in the working directory, so that it does not need to be created again
# this applies not only for a base alpine_rootfs, but also for whatever packages have been installed on top of it
# (in case the check is on the target rootfs itself)
#
# $1 a folder to check for an alpine system (can be an intended target rootfs or a cache dir)
# $2 if equal "dontdelete", do not delete $1. Otherwise, delete $1.
# returns 0 if the contents needs to be updated (recreated, or perhaps updated if $2 is nodelete), 1 otherwise
#
check_for_existing_alpine_base_system() {
	verbose "Checking for existing alpine status in $1"
	if [ -f $1/$ALPINE_ROOTFS_DONE_MARKER_PATH ] ; then
		if [ -n "$config_pscg_alpineos__expected_rootfs_fingerprint" ] ; then
			if ! grep -q "$config_pscg_alpineos__expected_rootfs_fingerprint" $1/$ALPINE_ROOTFS_DONE_MARKER_PATH ; then
				warn "Unmatching fingerprints. Expected: $config_pscg_alpineos__expected_rootfs_fingerprint ; Actual: $(cat $1/$ALPINE_ROOTFS_DONE_MARKER_PATH)"
				if [ "$config_pscg_alpineos__recreate_rootfs_cache_on_unmatching_fingerprints" = "true" ] ; then
					if [ "$2" = "dontdelete" ] ; then
						verbose "skipping deletion of folder (use this for the target rootfs, if you don't rebuild it from scratch and just want to copy caches)"
					else
						warn "removing cache at $1. It will be recreated."
						sudo rm -rf $1 || fatalError "Failed to remove $1"
					fi
				fi
				return 0
			fi
		fi
		verbose "Skipping base alpine rootfs as it was already done"
		return 1
	else
		verbose "No fingerprint detected for $1. Will repopulate from caches"
		return 0
	fi
}

init_fetch_and_unpack_definitions() {
	pscg_alpineos__set_arch_specific_variables_if_needed
	local archadj=${config_pscg_alpineos__alpine_arch}
	# bash note: note that we avoided only sourcing in pscg_alpineos.buildconfig, as it is not possible
	# to export arrays.
	# Instead, the file is sourced here directly, as declared arrays are a mess upon sourcing.
	# This is an example of using complex bash concepts for brevity (most of the build system aims
	# to avoid them, for these reasons (and for easing up on those new to bash)
	#
	# Also, source_file_or_die does not play nicely with declared variables! So let's source directly
	# Then, let's verify that it has been sourced correctly, or blow up the run	
	source "$DISTROS_DIR/pscg_alpineos/pscg_alpineos.minirootfs_upstream.buildconfig"
	eval_or_die "declare | grep -q ALPINEOS_MINI_ROOTFS_ARRAY"
			  
	fetch_remote_uri=${ALPINEOS_MINI_ROOTFS_ARRAY["${archadj}_tarball"]}
	fetch_expected_sha256=${ALPINEOS_MINI_ROOTFS_ARRAY["${archadj}_sha256"]}
	warn fetch_remote_uri=${ALPINEOS_MINI_ROOTFS_ARRAY["${archadj}_tarball"]}
	warn fetch_expected_sha256=${ALPINEOS_MINI_ROOTFS_ARRAY["${archadj}_sha256"]}
		
	if [ -z "$fetch_remote_uri" -o -z "fetch_expected_sha256" ] ; then
		fatalError "Your rootfs uri/sha256 are missing"
	fi
	fetch_local_target_path=$config_toplevel__downloads_base_path/$(basename $fetch_remote_uri) # we assume the URI ends with the tarball name
	
	unpack_dest_path=${CACHED_BASE_ROOTFS_DIR}
}

do_debootstrap_equivalent() {
	info_do_or_die do_fetch
	if [ ! -d $unpack_dest_path ] ; then
		# On the first time, the folder is not expected to exist. As opposed to the Linux kernel, U-Boot and busybox, the tarball directly contains the rootfs structure
		verbose_do_or_die mkdir -p $unpack_dest_path
	fi
	info_do_or_die do_unpack
	
	# touching is enough, but we'll add a naive implementation of fingerprinting
	# this allows to check for a specific "version" in case someone wants to cache it
	# we won't go all the way here though on checking.
	local fingerprint=$(date)
	hardVerbose "New debootstrap fingerprint: $fingerprint"
	echo $fingerprint | sudo tee $CACHED_BASE_ROOTFS_DIR/$ALPINE_ROOTFS_DONE_MARKER_PATH > /dev/null || fatalError "Failed to create $CACHED_BASE_ROOTFS_DIR/$ALPINE_ROOTFS_DONE_MARKER_PATH"
}

#
# The name resembles a build system fetch task. Inside the function we both fetch and unpack to a cached dir
#
do_fetch_wrapper() {
	check_for_existing_alpine_base_system $CACHED_BASE_ROOTFS_DIR || return 0
	do_debootstrap_equivalent
	echo invalidatecaches > $ALPINEOS_COMMON_CACHES_STATE_PATH
}

#
# The name resembles a build system unpack task. Inside the function we copy from a cached dir to our target dir
#
do_unpack_wrapper() {
	debug_do_or_die sudo cp -aT ${CACHED_BASE_ROOTFS_DIR} $ROOTFS_DIR	
}

# checking something: copied AS IS from build-caches.sh
# TODO: can/should probably build the package config in the build_distro but I'll look at it later,
# 		for now I just want to see that the cache mechanism works
#		this actually attempts to get all packages it encounters which is WRONG in the presence
#		of different apk sources and needs to be fixed but I won't do that now
populate_apk_package_list() {
	for f in $(find $BUILD_TOP -name packages*apk.buildconfig) ; do
		source $f
	done

	# TODO: see the comment for this function. It is important!
	hardDebug PackageList=$(pscg_alpineos__print_package_list)
	hardDebug ConflictingPackageList=$(pscg_alpineos__print_conflicting_package_list)
}

main() {
	init_env $@
	#
	# Note: the fetch and unpack are "cheating". They don't really get downloads, but rather populate
	#		a state cache. Therefore, they do not use the base functions, nor the common variables.
	#		The names are used to accompany my training philosophy, and to help my
	#		Embedded Linux development/security research course students more easily migrate to other
	#		build systems. In particular:
	# 		- do_fetch does not fetch a tarball, but rather a cached state so it goes to the caches dir
	#		- do_unpack copies the cache not only if there is no prestine base alpine rootfs, but also if there were no packages on top of it
	#
	# Also note: if you mess with the caches directories (or with the download directories), and do not clean the build and restart
	#			 you will have a consistency problem. Many hours have been spent by people debugging such things in yocto project, build root, AOSP and every
	#			 build system, so I did not bother to protect you from yourselves. Take heed!
	#

	# initial check - to avoid inconsistency in future builds assume that if the folder exists,
	# then the user doesn't care about the cached status at all.
	# Addition: Check package list if the user added a new package, and at least warn them
	if ! check_for_existing_alpine_base_system $ROOTFS_DIR ; then
		return 0
		# Uncomment the line above if you want to allow changes of packages - this has not been checked and is still in development,
		# so no guarantees here. The reason? It's just better to wipe the caches if someone adds new pacakges, and I wanted to
		# release the code with other changes.
		# This is the well checked behavior, relying on having the caches and caches work dir created with all of the required packages
		# any change in packages would mean that the user would need to invalidate the caches themselves, as we rely on the fingerprint
		# or on the alpine rootfs done marker. Yo can comment out

		# All of this will not be called (unless you comment out the previous line), and is WIP. See comment above, don't be lazy
		verbose "alpine rootfs existed TODO - this is WIP and will waste a lot of time on regenerating caches, which is not wanted during regular development"
		if [ -z "$(pscg_alpineos__print_package_list)" ] ; then
			warn "No packages in the package list yet ($APK_PACKAGE_LIST)"
			populate_apk_package_list
			hardDebug "Populated the package list locally TOOD fix that: $(pscg_alpineos__print_package_list)"
		fi
		warn "$(pscg_alpineos__print_package_list)"
		package_list=$(pscg_alpineos__print_package_list)
		if alpineos_common_naive_search_for_packages_in_caches "$package_list" $ROOTFS_DIR ; then
			if naive_search_for_packages_in_apk "$package_list" $ROOTFS_DIR ; then
				return 0
			else
				warn "All packages are in the caches, but not all of the packages have been installed in the rootfs"
			fi
		fi
	fi
	# Now run the logical ( :-) ) logic
	info_do_or_die do_fetch_wrapper
	info_do_or_die do_unpack_wrapper
}

commonScriptPrologueLogRunAndEpilogue $@
