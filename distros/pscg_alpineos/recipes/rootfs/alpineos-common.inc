#!/bin/bash
#
# Common definition files for Alpine based systems (e.g. pscg_alpineos).
# It is used to present some common variables use
#

alpineos_common_init_env() {	
	: ${config_pscg_alpineos__version="v${ALPINEOS_VERSION}"} # Using Alpine v3.23 (specifically 3.23.3)
	: ${config_pscg_alpineos__mirror_url="https://dl-cdn.alpinelinux.org"}
	: ${config_pscg_alpineos__arch="aarch64"}
	: ${config_pscg_alpineos__variant="minirootfs"} # Updated to minirootfs variant
	: ${config_pscg_alpineos__apk_url="${config_pscg_alpineos__mirror_url}"}
	
	export config_pscg_alpineos__version config_pscg_alpineos__arch config_pscg_alpineos__variant
}
export -f alpineos_common_init_env

alpineos_common_init_apk_caches_vars() {
	alpineos_common_init_env # TODO everything about this and the encapsulating function name
	ALPINE_ROOTFS_DONE_MARKER_PATH="/opt/.alpinerootfsdone" 	# relative to a rootfs folder
	CACHED_BASE_ROOTFS_DIR=$config_toplevel__caches_base_path/$ARCH/alpine-base-${config_pscg_alpineos__arch}-${config_pscg_alpineos__variant}-${config_pscg_alpineos__version}
	CACHED_APK_CACHES_WORKDIR=$config_toplevel__caches_workdir_base_path/$ARCH/workdir-alpinerootfsplusapkcaches-${config_pscg_alpineos__arch}-${config_pscg_alpineos__variant}-${config_pscg_alpineos__version}
	CACHED_APK_CACHES_DIR=$config_toplevel__caches_base_path/$ARCH/apkcaches-${config_pscg_alpineos__arch}-${config_pscg_alpineos__variant}-${config_pscg_alpineos__version}

	# This can be used to check if the caches are actual
	# If you see this comment, it means it is used for discussion but not implemented
	CACHED_APK_FINGERPRINT_PATH="/opt/.apkcachesfingerprint"

	# This is naive and easy (and an easy toctou target, but it is not the purpose)
	ALPINEOS_COMMON_CACHES_STATE_PATH="$config_toplevel__caches_workdir_base_path/$ARCH/stateinstructions-${config_pscg_alpineos__arch}-${config_pscg_alpineos__variant}-${config_pscg_alpineos__version}"
}

#
# The function looks for an indication that all the packages in $1 are present in the caches of $2
# $1 list of packages.
# $2 folder to look at
#
alpineos_common_naive_search_for_packages_in_caches() {
	local packages=$1
	local searchdir=$2/var/cache/apk
	if [ ! -d $searchdir ] ; then
		# We will be here only if we don't build from scratch, so we assume that the user intended to do it.
		if [ "$config_pscg_alpineos__postbuild_clean_apk_caches" = "true" ] ; then
			warn "$2 is not a directory. If you are retrying over a previously deleted cache dir that is OK. Otherwise, it's an error"
		else
			fatalError "$2 does not exist"
		fi
	fi

	for p in $packages ; do
		# Alpine packages are stored as <name>-<version>-r<revision>.apk
		if ! ls $searchdir/${p}-[0-9]*.apk &> /dev/null ; then
			warn "$p is not in the caches of $2"
			return 1
		fi
	done

	verbose "All of the packages in $1 are in the caches of $2"
}

#
# The function looks for an indication that all the packages in $1 are installed in $2
# $1 list of packages.
# $2 folder to look at
#
naive_search_for_packages_in_apk() {
	local packages=$1
	local searchfile=$2/lib/apk/db/installed
	local rc=0

	if [ ! -f $searchfile ] ; then
		rc=2
		fatalError "$2 is not properly set up for apk."
	fi

	for p in $packages ; do
		# Alpine's installed db uses "P:<name>" for package entries. 
		if ! grep -E "^P:$p$" $searchfile > /dev/null ; then
			warn "$p is not installed in $searchfile"
			rc=1
		fi
	done

	if [ "$rc" = "0" ] ; then
		verbose "All of the packages in $1 are in the apk installed file of $2"
	else
		return "$rc"
	fi
}
