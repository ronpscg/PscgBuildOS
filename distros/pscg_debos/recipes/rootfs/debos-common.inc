#
# Common definition files for Debian based systems.
# It is used to present some common variables use
#

debos_common_init_env() {
	: ${config_pscgdebos__debian_or_ubuntu="ubuntu"}
	: ${config_pscgdebos__debian_codename=REPLACEMEWITHAREALCODENAME} # for example: bullseye, buster,... (for Debian), focal, lunar,... (for Ubuntu)
	: ${config_pscgdebos__debian_base_url="http://deb.debian.org/debian/"}
	: ${config_pscgdebos__ubuntu_base_url="http://ports.ubuntu.com/ubuntu-ports/"}
	: ${config_pscgdebos__debian_variant=minbase}
	: ${config_pscgdebos__debian_arch=arm64}
	: ${config_pscgdebos__debian_url="${config_pscgdebos__ubuntu_base_url}"}

	case "${config_pscgdebos__debian_or_ubuntu}" in
		debian)
			config_pscgdebos__debian_url="${config_pscgdebos__debian_base_url}"
			;;
		ubuntu)
			config_pscgdebos__debian_url="${config_pscgdebos__ubuntu_base_url}"
			;;
		*)
			fatalError "Wrong config_pscgdebos__debian_or_ubuntu: ${config_pscgdebos__debian_or_ubuntu}"
			;;
	esac

	export config_pscgdebos__debian_or_ubuntu config_pscgdebos__debian_codename
}

debos_common_init_deb_caches_vars() {
	debos_common_init_env # TODO everything about this and the encapsulating function name
	DEBOOTSTRAP_DONE_MARKER_PATH="/opt/.debootstrapdone" 	# relative to a debootstrapped folder
	CACHED_DEBOOTSTRAP_DIR=$config_toplevel__caches_base_path/$ARCH/debootstrap-${config_pscgdebos__debian_arch}-${config_pscgdebos__debian_variant}-${config_pscgdebos__debian_codename}
	CACHED_DEB_CACHES_WORKDIR=$config_toplevel__caches_workdir_base_path/$ARCH/workdir-debootstrappluscaches-${config_pscgdebos__debian_arch}-${config_pscgdebos__debian_variant}-${config_pscgdebos__debian_codename}
	CACHED_DEB_CACHES_DIR=$config_toplevel__caches_base_path/$ARCH/debcaches-${config_pscgdebos__debian_arch}-${config_pscgdebos__debian_variant}-${config_pscgdebos__debian_codename}

	# This can be used to check if the caches are actual
	# If you see this comment, it means it is used for discussion but not implemented
	CACHED_DEB_FINGERPRINT_PATH="/opt/.debcachesfingerprint"

	# This is naive and easy (and an easy toctou target, but it is not the purpose)
	DEBOS_COMMON_CACHES_STATE_PATH="$config_toplevel__caches_workdir_base_path/$ARCH/stateinstructions-${config_pscgdebos__debian_arch}-${config_pscgdebos__debian_variant}-${config_pscgdebos__debian_codename}"
}

#
# The function looks for an indication that all the packages in $1 are present in the caches of $2
# $1 list of packages. Would usually be given
# $2 folder to look at
#
debos_common_naive_search_for_packages_in_caches() {
	local packages=$1
	local searchdir=$2/var/cache/apt/archives
	if [ ! -d $searchdir ] ; then
		# We will be here only if we don't build from scratch, so we assume that the user intended to do it.
		# In this case, we assume that their previous build configuration (cache-cleaning wise) is the same across building
		# In that case it is OK, otherwise it is an error
		if [ "$config_pscgdebos__postbuild_clean_apt_caches" = "true" ] ; then
			warn "$2 is not a directory. If you are retrying over a previously deleted cache dir that is OK. Otherwise, it's an error"
		else
			fatalError "$2 does not exist"
		fi
	fi

	for p in $packages ; do
		if ! ls $searchdir/${p}*.deb &> /dev/null ; then
			warn "$p is not in the caches of $2"
			return 1
		fi
	done

	verbose "All of the packages in $1 are in the caches of $2"
}

#
# The function looks for an indication that all the packages in $1 are installed in $2
# $1 list of packages. Would usually be given
# $2 folder to look at
#
# The way to do it would be chroot and look at the return code of dpkg-query -s <package> for example.
# To illustrate some dpkg concepts, we will look at the status file.
# This is not perfect though. If a package is not installed it will definitely not be in the status file.
# If the package is installed but its status is not ok - we could figure it out but it is not worth the effort,
# as it would be wiser to understand why it was not installed in the first place.
#
# Note: This is soms sort of optimization, for subsequent builds, and it has not been tested as much as the case
#       of having the caches set once, and then only working with a subset of them, and not adding to the caches
#
#
naive_search_for_packages_in_dpkg() {
	local packages=$1
	local searchfile=$2/var/lib/dpkg/status
	local rc=0

	if [ ! -f $searchfile ] ; then
		rc=2
		fatalError "$2 is not properly set up for dpkg."
	fi

	for p in $packages ; do
		# see function comments. note that if a package is Essential - it will be the next line after "Package: "
		# and if not, then the "Status: " will be the next line. You definitely DON'T want to parse files like we do here.
		# you want to use dpkg-query, dpkg, or other commands, but this is a very good exercise on system management,
		# and will serve you well when someone tinkers with your system and you need to debug it.
		#
		# Also, it is of course better to create a better grep pattern, rather than reopen the file, but that's fine for now.
		if ! grep "Package: $p" $searchfile > /dev/null ; then
			warn "$p is not in not installed in $searchfile"
			rc=1
		fi
	done

	if [ "$rc" = "0" ] ; then
		verbose "All of the packages in $1 are in the dpkg status file of $2"
	else
		return "$rc"
	fi
}

