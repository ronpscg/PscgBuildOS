#!/bin/bash
#
# Set up a minimal Debian root filesystem by issuing (cross) debootstrap, allowing reusing previously debootstrapped rootfilesystem, for an offline and reproducible build
#
# If you are wondering about the offline builds, in fact, we can run it BEFORE having an apt cache - it doesn't even use apt update.

init_env() {
	source $BUILD_TOP/distros/pscg_debos/recipes/rootfs/debos-common.inc # no need to hide behind variables - this is very specific to this distro
	debos_common_init_deb_caches_vars
}

#
# Checks if the base debootstrap already exist in the working directory, so that it does not need to be created again
# this applies not only for a base debootstrap, but also for whatever packages have been installed on top of it
# (in case the check is on the target rootfs itself)
#
# $1 a folder to check for a deboostrapped system (can be an intended target rootfs or a cache dir)
# $2 if equal "dontdelete", do not delete $1. Otherwise, delete $1.
# returns 0 if the contents needs to be updated (recreated, or perhaps updated if $2 is nodelete), 1 otherwise
#
check_for_existing_debootstrap_base_system() {
	verbose "Checking for existing debootstrap status in $1"
	if [ -f $1/$DEBOOTSTRAP_DONE_MARKER_PATH ] ; then
		if [ -n "$config_pscgdebos__expected_debootstrap_fingerprint" ] ; then
			if ! grep -q "$config_pscgdebos__expected_debootstrap_fingerprint" $1/$DEBOOTSTRAP_DONE_MARKER_PATH ; then
				warn "Unmatching fingerprints. Expected: $config_pscgdebos__expected_debootstrap_fingerprint ; Actual: $(cat $1/$DEBOOTSTRAP_DONE_MARKER_PATH)"
				if [ "$config_pscgdebos__recreate_debootstrap_cache_on_unmatching_fingerprints" = "true" ] ; then
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
		verbose "Skipping base debootstrap as it was already done"
		return 1
	else
		verbose "No fingerprint detected for $1. Will repopulate from caches"
		return 0
	fi
}

do_debootstrap() {
	case ${config_pscgdebos__debian_variant} in
		default|none|"")
			variantArgument=" "
			;;
		*)
			variantArgument="--variant=${config_pscgdebos__debian_variant}"
			;;
	esac

	info "Debootstrapping for the first time..."
	info_do_or_die sudo debootstrap              		\
		${debianDebootstrapExtraArgs}					\
		--arch=${config_pscgdebos__debian_arch}                   			\
		$variantArgument              					\
		${config_pscgdebos__debian_codename} $CACHED_DEBOOTSTRAP_DIR 		\
		${config_pscgdebos__debian_url}									\
		|| fatalError "Debootstrap failed. You might want to remove $CACHED_DEBOOTSTRAP_DIR before trying again."

	# touching is enough, but we'll add a naive implementation of fingerprinting
	# this allows to check for a specific "version" in case someone wants to cache it
	# we won't go all the way here though on checking.
	local fingerprint=$(date)
	hardVerbose "New debootstrap fingerprint: $fingerprint"
	echo $fingerprint | sudo tee $CACHED_DEBOOTSTRAP_DIR/$DEBOOTSTRAP_DONE_MARKER_PATH > /dev/null || fatalError "Failed to create $CACHED_DEBOOTSTRAP_DIR/$DEBOOTSTRAP_DONE_MARKER_PATH"
}

do_fetch() {
	check_for_existing_debootstrap_base_system $CACHED_DEBOOTSTRAP_DIR || return 0
	do_debootstrap
	echo invalidatecaches > $DEBOS_COMMON_CACHES_STATE_PATH
}

do_unpack() {
	# Note: as an optimization phase, we already checked before so we don't need to check for debootstrap updating here.
	# However, if you want to maybe later separate the steps, you may want to add a check here.
	debug_do_or_die sudo cp -aT $CACHED_DEBOOTSTRAP_DIR $ROOTFS_DIR
}

# checking something: copied AS IS from build-caches.sh
# TODO: can/should probably build the package config in the build_distro but I'll look at it later,
# 		for now I just want to see that the cache mechanism works
#		this actually attempts to get all packages it encounters which is WRONG in the presence
#		of different apt sources and needs to be fixed but I won't do that now
populate_deb_package_list() {
	for f in $(find $BUILD_TOP -name packages*deb.buildconfig) ; do
		source $f
	done

	# TODO: see the comment for this function. It is important!
	hardDebug PackageList=$(pscg_debos__print_package_list)
	hardDebug ConflictingPackageList=$(pscg_debos__print_conflicting_package_list)
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
	#		- do_unpack copies the cache not only if there is no prestine base debootstrap, but also if there were no packages on top of it
	#
	# Also note: if you mess with the caches directories (or with the download directories), and do not clean the build and restart
	#			 you will have a consistency problem. Many hours have been spent by people debugging such things in yocto project, build root, AOSP and every
	#			 build system, so I did not bother to protect you from yourselves. Take heed!
	#

	# initial check - to avoid inconsistency in future builds assume that if the folder exists,
	# then the user doesn't care about the cached status at all.
	# Addition: Check package list if the user added a new package, and at least warn them
	if ! check_for_existing_debootstrap_base_system $ROOTFS_DIR ; then
		return 0
		# Uncomment the line above if you want to allow changes of packages - this has not been checked and is still in development,
		# so no guarantees here. The reason? It's just better to wipe the caches if someone adds new pacakges, and I wanted to
		# release the code with other changes.
		# This is the well checked behavior, relying on having the caches and caches work dir created with all of the required packages
		# any change in packages would mean that the user would need to invalidate the caches themselves, as we rely on the fingerprint
		# or on the debootstrap done marker. Yo can comment out

		# All of this will not be called (unless you comment out the previous line), and is WIP. See comment above, don't be lazy
		verbose "deboostrap existed TODO - this is WIP and will waste a lot of time on regenerating caches, which is not wanted during regular development"
		if [ -z "$(pscg_debos__print_package_list)" ] ; then
			warn "No packages in the package list yet ($DEB_PACKAGE_LIST)"
			populate_deb_package_list
			hardDebug "Populated the package list locally TOOD fix that: $(pscg_debos__print_package_list)"
		fi
		warn "$(pscg_debos__print_package_list)"
		package_list=$(pscg_debos__print_package_list)
		if debos_common_naive_search_for_packages_in_caches "$package_list" $ROOTFS_DIR ; then
			if debos_common_naive_search_for_packages_in_dpkg "$package_list" $ROOTFS_DIR ; then
				return 0
			else
				warn "All packages are in the caches, but not all of the packages have been installed in the rootfs"
			fi
		fi
	fi
	# Now run the logical ( :-) ) logic
	info_do_or_die do_fetch
	info_do_or_die do_unpack
}

commonScriptPrologueLogRunAndEpilogue $@
