#!/bin/bash
#
# Alpine targets only (e.g. pscg_alpineos). Run this script as super user (otherwise we'd need a fakeroot et. al)
# This code aims to take a target directory (in the caches directory), and download the apk-packages into them.
# Then, one can copy the resulting caches directories over their actual rootfs, and install packages without needing
# an active network connection.
#
# It is meant to do a "massive do_fetch" that will also resolve dependencies, without setting up a local mirror for
# the packages (which is also possible, but it is another thing to teach, and what we care about is the concepts, not
# external mechanisms (note that we implement everything with bash, to not force you to learn too many things, and appreciate that! ;-) ))
#
# Some more things you can do: (and of course make sure to reflect it in your target system):
# - update /etc/ files (e.g. apk repositories, apk keys,
# perhaps even cron files or other update-motd files that do periodic software update checks on the target)
# - more, know how things work, and just do it :-)
#
# Note that while one can add multiple repositories and support alien architectures, this is meant
# to be run for one architecture. You can change it but it is not recommended, as your caches may
# potentially get huge
#


init_env() {
	pscg_alpineos__set_arch_specific_variables_if_needed # also sources the minirootfs_upstream_buildconfig
	source $BUILD_TOP/distros/pscg_alpineos/recipes/rootfs/alpineos-common.inc # no need to hide behind variables - this is very specific to this distro
	alpineos_common_init_env
	alpineos_common_init_apk_caches_vars
}

populate_apk_package_list_external_layers() {
	if [ -f "$config_pscg_alpineos__extra_layers_file" ] ; then
		# This is a file with layers to add, one per line, and comments are allowed
		while read -r layerline ; do
			if [ -n "$layerline" ] && [[ ! "$layerline" =~ ^#.* ]] ; then
				verbose "Searching more configs in $layerline"
				layerline=$(eval echo $layerline) # in case it has variables, e.g. $LAYERS_DIR. Super insecure, beware eval!
				# Note: the cache mechanism runs very early during the build, so it is an excellent place to do validation and fail the build if the file is bad
				[ -d "$layerline" ] || fatalError "$layerline does not exist or is not a layer directory"
				for f in $(find $layerline -name packages*apk.buildconfig) ; do
					verbose "Sourcing $f"
					source $f || fatalError "Failed to source $f. Please fix your config_pscg_alpineos__extra_layers_file file"
				done
			fi
		done < "$config_pscg_alpineos__extra_layers_file"
	fi
	# One could do the equivalent for other distros
}

# TODO: can/should probably build the package config in the build_distro but I'll look at it later,
# 		for now I just want to see that the cache mechanism works
#		this actually attempts to get all packages it encounters which is WRONG in the presence
#		of different apk sources and needs to be fixed but I won't do that now
populate_apk_package_list() {
	for f in $(find $BUILD_TOP -name packages*apk.buildconfig) ; do
		source $f
	done

	populate_apk_package_list_external_layers # Added: December 2025 as part of a huge refactoring.

	# TODO: see the comment for this function. It is important!
	hardDebug PackageList=$(pscg_alpineos__print_package_list)
	hardDebug ConflictingPackageList=$(pscg_alpineos__print_conflicting_package_list)
}


#
# Populate extra files
# In this quickly made demonstration we just do the minimum, which is updating the DNS
# as the default minimal Alpine tarball does not come with /etc/resolv.conf, and so apk would fail
#
populate_extra_required_files() {
	: ${DEFAULT_RESLOVCONF_LINES="nameserver 8.8.8.8"}
	if [ ! -e $CACHED_APK_CACHES_WORKDIR/etc/resolv.conf ] ; then	
		echo $DEFAULT_RESLOVCONF_LINES | sudo tee $CACHED_APK_CACHES_WORKDIR/etc/resolv.conf > /dev/null
	fi	
}

#
# Copy from a cached base rootfs. The reason for copying and not working directly on it, is
# to allow different configurations, reusing state caches.
# As an educational note, this is a good place to discuss the docker strategy for managing layers
# [it depends on the "driver", but the most common approach is to use a huge set of overlays mountable
# via overlayfs (you can see it in their cache mechanism as well, at every RUN statement)  ]
#
copy_from_base_rootfs() {
	verbose "Copying from base rootfs: $CACHED_BASE_ROOTFS_DIR --> $CACHED_APK_CACHES_WORKDIR"
	if [ ! -d "$CACHED_BASE_ROOTFS_DIR" ] ; then
		error "$CACHED_BASE_ROOTFS_DIR does not exist. Did you mess with the caches? You would likely have to clean up your rootfs dir, or use cleanup flags"
		warn "Try to cleanup $ROOTFS_DIR/$ALPINE_ROOTFS_DONE_MARKER_PATH perhaps, or remove the rootfs dir"
	fi
	do_or_die sudo cp -aT $CACHED_BASE_ROOTFS_DIR $CACHED_APK_CACHES_WORKDIR
}

#
# Update caches. This takes a base rootfs directory (or a previous version), and runs
#
update_caches_in_working_directory() {
	info_do_or_die populate_apk_package_list	# just assign the package list variable

	info_do_or_die populate_extra_required_files $CACHED_APK_CACHES_WORKDIR 

	# local flags=""
	# If you are sure you do not need an update step (e.g. you always use the same base, and never touch the repos),
	# you can take off this line to speed things up
	#

	# Note the usage of eval_or_die
	verbose_eval_or_die 'sudo chroot $CACHED_APK_CACHES_WORKDIR sh -c "apk update"'
	# Alpine equivalent of --download-only is fetch --recursive
	verbose_eval_or_die 'sudo chroot $CACHED_APK_CACHES_WORKDIR sh -c "apk fetch --recursive -o /var/cache/apk/ $(pscg_alpineos__print_package_list)"'

	verbose_eval_or_die 'sudo chroot $CACHED_APK_CACHES_WORKDIR sh -c "rm /var/cache/apk/APKINDEX*.* && apk index -o /var/cache/apk/APKINDEX.tar.gz /var/cache/apk/*.apk"'

	# A naive demonstration of a fingerprinting mechanism for the package caches
	local fingerprint=$(date)
	hardVerbose "New apkcaches fingerprint: $fingerprint"
	echo $fingerprint | sudo tee $CACHED_APK_CACHES_WORKDIR/$CACHED_APK_FINGERPRINT_PATH > /dev/null

	info "done updating caches at $CACHED_APK_CACHES_WORKDIR"
}

copy_from_working_directory_to_caches_dir() {
	verbose "Copying caches: $CACHED_APK_CACHES_WORKDIR --> $CACHED_APK_CACHES_DIR"
	do_or_die mkdir -p $CACHED_APK_CACHES_DIR
	do_or_die sudo cp -a $CACHED_APK_CACHES_WORKDIR/{etc,var} $CACHED_APK_CACHES_DIR

	# A naive demonstration of a fingerprinting mechanism for the package caches
	sudo mkdir -p $CACHED_APK_CACHES_DIR/$(dirname $CACHED_APK_FINGERPRINT_PATH) || warn Failed to create fingerprinting directory
	do_or_die sudo cp $CACHED_APK_CACHES_WORKDIR/$CACHED_APK_FINGERPRINT_PATH $CACHED_APK_CACHES_DIR/$CACHED_APK_FINGERPRINT_PATH
}

copy_from_caches_dir_to_rootfs_dir() {
	verbose "Copying caches: $CACHED_APK_CACHES_DIR --> $ROOTFS_DIR"
	do_or_die mkdir -p $CACHED_APK_CACHES_DIR
	do_or_die sudo cp -a $CACHED_APK_CACHES_DIR/{etc,var} $ROOTFS_DIR
	do_or_die sudo cp $CACHED_APK_CACHES_DIR/$CACHED_APK_FINGERPRINT_PATH $ROOTFS_DIR/$CACHED_APK_FINGERPRINT_PATH
}

#
# Checks if the packages caches already exist in the working directory, so that it does not need to be created again
# this applies not only for a cached dir, or a working directory for creating in, but also for
# an already populated rootfs
#
# $1 a folder to check for prepared cache (can be an intended target rootfs, a working dir or a cache dir)
# $2 if equal "dontdelete", do not delete $1. Otherwise, delete $1.
# returns 0 if the contents needs to be updated (recreated, or perhaps updated if $2 is nodelete), 1 otherwise
#
# Note that we could theoretically also check for apk status - but we won't. it does not serve the purpose
#
check_for_existing_caches_update() {
	verbose "Checking for existing apkcaches in $1"
	debug "relevant configs: $config_pscg_alpineos__expected_apkcaches_fingerprint/$config_pscg_alpineos__recreate_apkcaches_on_unmatching_fingerprints"
	if [ -f $1/$CACHED_APK_FINGERPRINT_PATH ] ; then
		if [ -n "$config_pscg_alpineos__expected_apkcaches_fingerprint" ] ; then
			if ! grep -q "$config_pscg_alpineos__expected_apkcaches_fingerprint" $1/$CACHED_APK_FINGERPRINT_PATH ; then
				warn "Unmatching fingerprints. Expected: $config_pscg_alpineos__expected_apkcaches_fingerprint ; Actual: $(cat $1/$CACHED_APK_FINGERPRINT_PATH)"
				if [ "$config_pscg_alpineos__recreate_apkcaches_on_unmatching_fingerprints" = "true" ] ; then
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

		populate_apk_package_list
		package_list=$(pscg_alpineos__print_package_list)

		if alpineos_common_naive_search_for_packages_in_caches "$package_list" "$1" ; then
			verbose "Skipping recreating of apkcaches"
			return 1
		else
			warn "Not all packages have been found in the caches of $1. The caches will be recreated"
			return 0
		fi
	else
		verbose "No fingerprint detected for $1. Will repopulate from caches"
		return 0
	fi
}

check_for_cache_state_instructions() {
	debug $ALPINEOS_COMMON_CACHES_STATE_PATH: $(cat $ALPINEOS_COMMON_CACHES_STATE_PATH)
	if grep -q invalidatecaches $ALPINEOS_COMMON_CACHES_STATE_PATH ; then
		warn "Invalidating all previous caches"
		for d in $ROOTFS_DIR $CACHED_APK_CACHES_WORKDIR $CACHED_APK_CACHES_DIR ; do
			debug_do_or_die sudo rm -f  $d/$CACHED_APK_FINGERPRINT_PATH
		done
		echo allgood > $ALPINEOS_COMMON_CACHES_STATE_PATH
	fi
}

#
# Update caches if necessary and update them.
#
main() {
	init_env

	check_for_cache_state_instructions

	check_for_existing_caches_update $ROOTFS_DIR dontdelete || return 0

	# If we are here, it means we need to update the rootfs caches.
	if check_for_existing_caches_update $CACHED_APK_CACHES_DIR ; then
		info "Caches dir update required"
		if check_for_existing_caches_update $CACHED_APK_CACHES_WORKDIR ; then
			info "Updating caches working dir"
			info_do_or_die copy_from_base_rootfs
			info_do_or_die update_caches_in_working_directory
		fi
		info "Updating the caches dir"
		info_do_or_die copy_from_working_directory_to_caches_dir
	fi

	info "Updating the rootfs"
	info_do_or_die copy_from_caches_dir_to_rootfs_dir
}

commonScriptPrologueLogRunAndEpilogue $@
