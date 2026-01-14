
init_env_ubuntu_common() {
	# for the sake of simplicity, assume only one type/uri/suite, and support multiple components
	: ${pscgdebos_apt_sources_components="main universe"} # avoid restricted and multiverse by default
	LOCAL_APT_TYPE="deb"
	LOCAL_APT_URI="http://ports.ubuntu.com/ubuntu-ports"
	LOCAL_APT_SUITE="${config_pscgdebos__debian_codename}"
	LOCAL_APT_COMPONENTS="$pscgdebos_apt_sources_components"
	LOCAL_APT_SOURCES_LIST=/etc/apt/sources.list	# To simplify things, we override the main file, like the distros do. More things should go into etc/apt/sources.list.d/*

	if [ "${config_pscgdebos__debian_arch}" = "amd64" -o "${config_pscgdebos__debian_arch}" = "i386" ] ; then
		LOCAL_APT_URI=http://archive.ubuntu.com/ubuntu/	# TODO: can change that to the ${config_pscgdebos__debian_url}
	fi
}

#
# $1: debootstrapped directory
#
update_deb_sources_ubuntu_common() {
	verbose "Updating $1/$LOCAL_APT_SOURCES_LIST"
	# In the statement below, note the use of backslash to escape the dollar sign of variable i (e.g. \$i and not just $i, inside quotes)
	# This illustrates some of the things you should be awaere of when doing all kind of smart one liners, and is a suggestions that executing scripts
	# inside a chroot may be easier to work with (but may also be more work. up to you, we present you some tradeoffs and caveats)
	sudo chroot $1 bash -c "
		set -e
		echo \"# Created by $0, $(date)\" > $LOCAL_APT_SOURCES_LIST	# truncate
		for i in $LOCAL_APT_COMPONENTS ; do
			echo $LOCAL_APT_TYPE $LOCAL_APT_URI $LOCAL_APT_SUITE \$i >> $LOCAL_APT_SOURCES_LIST
		done
	" || fatalError "Failed to poupulate the apt sources list"

	# Could call apt modernize sources, but it is not needed. Can always do it later
}

#
# $1: debootstrapped directory
#
update_deb_caches_ubuntu_common() {
	verbose "Updating apt caches" 	# do not do this for an offline build

	# Note: you may need to mount tmp, proc, dev, devpts and create /dev/null in order to update from some of the sources.
	# Note: another option can be to preopulate gpg keys, and we won't do that.
	sudo chroot $1 bash -c "DEBIAN_FRONTEND=noninteractive apt-get update" || fatalError "Failed to update the apt cache"


	# Note: Once done, you will see that the caches could easily take over 100MB. So when designing your embedded systems, and your update systems,
	# you may want to be aware of that and plan your strategy accordingly
}

export -f init_env_ubuntu_common update_deb_sources_ubuntu_common update_deb_caches_ubuntu_common

#
# This example shows an entire flow of updating things. I leave it here, as you may want
# to add other sources list, and test them regarldess of the cache mechanisms.
# While the names say "ubuntu" this is applicable for every Debian based system, and you
# would of course want to modify the apt sources
#
# This expects to have an already debootrapped system
#
# $1: debootstrapped directory
#
example_update_ubuntu_sources_flow() {
	if [ ! -f $DEBOOTSTRAP_DONE_MARKER_PATH ] ; then
		fatalError "Trying to update a non debootsrapped directory"
	fi
	init_env_ubuntu_common $1
	update_deb_sources_ubuntu_common $1
	update_deb_caches_ubuntu_common $1
}
