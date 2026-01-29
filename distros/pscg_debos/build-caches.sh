#!/bin/bash
#
# Debian/Ubuntu targets only (e.g. pscg_debos). Run this script as super user (otherwise we'd need a fakeroot et. al)
# This code aims to take a target directory (in the caches directory), and download the apt-packages into them.
# Then, one can copy the resulting caches directories over their actual rootfs, and install packages without needing
# and apt.
#
# It is meant to do a "massive do_fetch" that will also resolve dependencies, without setting up a local mirror for
# the packages (which is also possible, but it is another thing to teach, and what we care about is the concepts, not
# external mechanisms (note that we implement everything with bash, to not force you to learn too many things, and appreciate that! ;-) ))
#
# Some more things you can do: (and of course make sure to reflect it in your target system):
# - update /etc/ files (e.g. apt sources list, apt flags and policies,
# perhaps even cron files or other update-motd files that do periodic software update checks on the target)
# - more, know how things work, and just do it :-)
#
# Note that while one can add multiple repositories and support alien architectures, this is meant
# to be run for one architecture. You can change it but it is not recommended, as your caches may
# potentially get huge
#


init_env() {
	source $BUILD_TOP/distros/pscg_debos/recipes/rootfs/debos-common.inc # no need to hide behind variables - this is very specific to this distro
	debos_common_init_deb_caches_vars
}

populate_deb_package_list_external_layers() {
	if [ -f "$config_pscgdebos__extra_layers_file" ] ; then
		# This is a file with layers to add, one per line, and comments are allowed
		while read -r layerline ; do
			if [ -n "$layerline" ] && [[ ! "$layerline" =~ ^#.* ]] ; then
				verbose "Searching more configs in $layerline"
				layerline=$(eval echo $layerline) # in case it has variables, e.g. $LAYERS_DIR. Super insecure, beware eval!
				# Note: the cache mechanism runs very early during the build, so it is an excellent place to do validation and fail the build if the file is bad
				[ -d "$layerline" ] || fatalError "$layerline does not exist or is not a layer directory"
				for f in $(find $layerline -name packages*deb.buildconfig) ; do
					verbose "Sourcing $f"
					source $f || fatalError "Failed to source $f. Please fix your config_pscgdebos__extra_layers_file file ($config_pscgdebos__extra_layers_file - $layerline)"
				done
			fi
		done < "$config_pscgdebos__extra_layers_file"
	fi
	# One could do the equivalent for other distros
}

# TODO: can/should probably build the package config in the build_distro but I'll look at it later,
# 		for now I just want to see that the cache mechanism works
#		this actually attempts to get all packages it encounters which is WRONG in the presence
#		of different apt sources and needs to be fixed but I won't do that now
populate_deb_package_list() {
	for f in $(find $BUILD_TOP -name packages*deb.buildconfig) ; do
		source $f
	done

	populate_deb_package_list_external_layers # Added: December 2025 as part of a huge refactoring. If something does not work well it is t-h-e candidate, as the rest of the code has YEARS of testing endurance, and this, as per the time of writing this comment (prior to writing the function, eh) zero picoseconds of testing :-)  TODO - remove this comment after some time

	# TODO: see the comment for this function. It is important!
	hardDebug PackageList=$(pscg_debos__print_package_list)
	hardDebug ConflictingPackageList=$(pscg_debos__print_conflicting_package_list)
}


#
# Populate apt sources (and perhaps flags) before an apt-update
#
populate_apt_sources_list() {
	case "${config_pscgdebos__debian_or_ubuntu}" in
		debian)
			;;
		ubuntu)
			config_pscgdebos__debian_url="${config_pscgdebos__ubuntu_base_url}"
			# This uses Ubuntu as an example because I showed how to add some apt sources to it
			# But you can change it for your own distros, or trivially generalize the concept programtically
			debug_do_or_die init_env_ubuntu_common $1
			debug_do_or_die update_deb_sources_ubuntu_common $1
			debug_do_or_die update_deb_caches_ubuntu_common $1
			;;
		*)
			fatalError "Wrong config_pscgdebos__debian_or_ubuntu: ${config_pscgdebos__debian_or_ubuntu}"
			;;
	esac
}

#
# Copy from a cached debootstrap. The reason for copying and not working directly on it, is
# to allow different configurations, reusing state caches.
# As an educational note, this is a good place to discuss the docker strategy for managing layers
# [it depends on the "driver", but the most common approach is to use a huge set of overlays mountable
# via overlayfs (you can see it in their cache mechanism as well, at every RUN statement)  ]
#
copy_from_base_debootstrap() {
	verbose "Copying from debootstrap: $CACHED_DEBOOTSTRAP_DIR --> $CACHED_DEB_CACHES_WORKDIR"
	if [ ! -d "$CACHED_DEBOOTSTRAP_DIR" ] ; then
		error "$CACHED_DEBOOTSTRAP_DIR does not exist. Did you mess with the caches? You would likely have to clean up your rootfs dir, or use cleanup flags"
		warn "Try to cleanup $ROOTFS_DIR/$DEBOOTSTRAP_DONE_MARKER_PATH perhaps, or remove the rootfs dir"
	fi
	do_or_die sudo cp -aT $CACHED_DEBOOTSTRAP_DIR $CACHED_DEB_CACHES_WORKDIR
}

#
# Update caches. This takes a debootstrapped directory (or a previous version), and runs
#
update_caches_in_working_directory() {
	info_do_or_die populate_deb_package_list	# just assign the package list variable

	info_do_or_die populate_apt_sources_list $CACHED_DEB_CACHES_WORKDIR 	# update package list

	local flags="-y --download-only"
	# You can uncomment this line and add more things to it to modify apt-get behavior
	# flags="$flags --allow-downgrades --reinstall"
	# If you are sure you do not need an update step (e.g. you always use the same deboostrap base, and never touch the apt sources),
	# you can take off this line to speed things up
	#

	# Note the usage of eval_or_die - in this case, you must enclose everything in quotes, or the quotes after the bash -c will be gone and the expression will break
	verbose_eval_or_die 'sudo chroot $CACHED_DEB_CACHES_WORKDIR bash -c "apt-get update"'
	verbose_eval_or_die 'sudo chroot $CACHED_DEB_CACHES_WORKDIR bash -c "apt-get install $flags $(pscg_debos__print_package_list)"'

	# A naive demonstration of a fingerprinting mechanism for the package caches
	local fingerprint=$(date)
	hardVerbose "New debcaches fingerprint: $fingerprint"
	echo $fingerprint | sudo tee $CACHED_DEB_CACHES_WORKDIR/$CACHED_DEB_FINGERPRINT_PATH > /dev/null

	info "done updating caches at $CACHED_DEB_CACHES_WORKDIR"
}

copy_from_working_directory_to_caches_dir() {
	verbose "Copying caches: $CACHED_DEB_CACHES_WORKDIR --> $CACHED_DEB_CACHES_DIR"
	do_or_die mkdir -p $CACHED_DEB_CACHES_DIR
	do_or_die sudo cp -a $CACHED_DEB_CACHES_WORKDIR/{etc,var} $CACHED_DEB_CACHES_DIR

	# A naive demonstration of a fingerprinting mechanism for the package caches
	sudo mkdir -p $CACHED_DEB_CACHES_DIR/$(dirname $CACHED_DEB_FINGERPRINT_PATH) || warn Failed to create fingerprinting directory
	do_or_die sudo cp $CACHED_DEB_CACHES_WORKDIR/$CACHED_DEB_FINGERPRINT_PATH $CACHED_DEB_CACHES_DIR/$CACHED_DEB_FINGERPRINT_PATH
}

copy_from_caches_dir_to_rootfs_dir() {
	verbose "Copying caches: $CACHED_DEB_CACHES_DIR --> $ROOTFS_DIR"
	do_or_die mkdir -p $CACHED_DEB_CACHES_DIR
	do_or_die sudo cp -a $CACHED_DEB_CACHES_DIR/{etc,var} $ROOTFS_DIR
	do_or_die sudo cp $CACHED_DEB_CACHES_DIR/$CACHED_DEB_FINGERPRINT_PATH $ROOTFS_DIR/$CACHED_DEB_FINGERPRINT_PATH
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
# Note that we could theoretically also check for dpkg status - but we won't. it does not serve the purpose
#
check_for_existing_caches_update() {
	verbose "Checking for existing debcaches in $1"
	debug "relevant configs: $config_pscgdebos__expected_debcaches_fingerprint/$config_pscgdebos__recreate_debcaches_on_unmatching_fingerprints"
	if [ -f $1/$CACHED_DEB_FINGERPRINT_PATH ] ; then
		if [ -n "$config_pscgdebos__expected_debcaches_fingerprint" ] ; then
			if ! grep -q "$config_pscgdebos__expected_debcaches_fingerprint" $1/$CACHED_DEB_FINGERPRINT_PATH ; then
				warn "Unmatching fingerprints. Expected: $config_pscgdebos__expected_debcaches_fingerprint ; Actual: $(cat $1/$CACHED_DEB_FINGERPRINT_PATH)"
				if [ "$config_pscgdebos__recreate_debcaches_on_unmatching_fingerprints" = "true" ] ; then
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

		#echo invalidatecaches > $DEBOS_COMMON_CACHES_STATE_PATH
		populate_deb_package_list
		package_list=$(pscg_debos__print_package_list)

		if debos_common_naive_search_for_packages_in_caches "$package_list" "$1" ; then
			verbose "Skipping recreating of debcaches"
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
	debug $DEBOS_COMMON_CACHES_STATE_PATH: $(cat $DEBOS_COMMON_CACHES_STATE_PATH)
	if grep -q invalidatecaches $DEBOS_COMMON_CACHES_STATE_PATH ; then
		warn "Invalidating all previous caches"
		for d in $ROOTFS_DIR $CACHED_DEB_CACHES_WORKDIR $CACHED_DEB_CACHES_DIR ; do
			debug_do_or_die sudo rm -f  $d/$CACHED_DEB_FINGERPRINT_PATH
		done
		echo allgood > $DEBOS_COMMON_CACHES_STATE_PATH
	fi
}

#
# Update caches if necessary and update them. This is planned in a way that allows no downloading unless necessary
# and the return statements here represent it.
# There is an important exception to the logic: if the main function receives an "invalidate everything"
# statement (in a state file), it means that the debootstrap cache has been updated, and so all caches and the target rootfs
# must be updated (it is not necessarily the case always, but it is a very bad practice to mix caches!!!)
#
# This aims to support providing just the cache dir (Without the work dir), e.g. from another source, so if the fingerprint
# is OK for the cache dir (including when not requesting for a fingerprint, but having the respective file), we don't build
# the work dir for it. Essentially, it means that you can separate the workdir for the cache, and it would be a good practice,
# the only "problem" with it is whether you want to put it in the build folder or not, as you may not want to delete it when the rest
# of the work is done. So this will also be left as a config parameter
#
# So, having said that, the flow is:
# - Check if the rootfs needs an update (if not return)
# - Check if the caches need an update (if not update the rootfs and return)
# - Check if the workdir needs an update, and if so, recreate it and copy to the caches and then to the rootfs dir
#
main() {
	init_env

	check_for_cache_state_instructions

	check_for_existing_caches_update $ROOTFS_DIR dontdelete || return 0

	# If we are here, it means we need to update the rootfs caches.
	# We will do what we can do avoid internet access, if the work caches and debcaches are properly updated,
	# and will go to the internet otherwise

	if check_for_existing_caches_update $CACHED_DEB_CACHES_DIR ; then
		info "Caches dir update required"
		if check_for_existing_caches_update $CACHED_DEB_CACHES_WORKDIR ; then
			info "Updating caches working dir"
			info_do_or_die copy_from_base_debootstrap
			info_do_or_die update_caches_in_working_directory
		fi
		info "Updating the caches dir"
		info_do_or_die copy_from_working_directory_to_caches_dir
	fi

	info "Updating the rootfs"
	info_do_or_die copy_from_caches_dir_to_rootfs_dir
}


commonScriptPrologueLogRunAndEpilogue $@
