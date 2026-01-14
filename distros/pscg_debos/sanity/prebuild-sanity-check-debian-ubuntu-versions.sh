#!/bin/bash

#
# This script aims to do some validity check of Debian/Ubuntu versions, to avoid mixing Debian with Ubuntu versions and vice versa, early enough in the build stage.
# It also illustrates the concept of indexed array without using declare -a while at it (Shell scripting courses)
# All inline comments are as per the time of writing (i.e. maybe the script was written when Debian Stable is Debian 12 - and you will see it when it is Debian 1413152 )
#
# Last updated: 2025-08-19. Why is this important? Because Debian and Ubuntu versions change all the time, so this script needs to be updated accordingly.
#

# Comprehensive list of Debian codenames, from oldest to newest
debian_codenames=(
	"buzz"
	"rex"
	"bo"
	"hamm"
	"slink"
	"potato"
	"woody"
	"sarge"
	"etch"
	"lenny"
	"squeeze"
	"wheezy"
	"jessie"
	"stretch"
	"buster"
	"bullseye"
	"bookworm"
	"trixie"	# stable - Debian 13
	"forky" 	# unstable - Debian 14
	"duke"  	# future - Debian 15
	"sid"     	# unstable (exactly the same as unstable)
	"stable"
	"testing"
	"unstable"
)

debian_ports_codenames=(
	experimental
	sid
	unreleased
	unstable
)

# Comprehensive list of Ubuntu codenames, from oldest to newest
ubuntu_codenames=(
	"warty"
	"hoary"
	"breezy"
	"dapper"
	"edgy"
	"feisty"
	"gutsy"
	"hardy"
	"intrepid"
	"jaunty"
	"karmic"
	"lucid"
	"maverick"
	"natty"
	"oneiric"
	"precise"
	"quantal"
	"raring"
	"saucy"
	"trusty"
	"utopic"
	"vivid"
	"wily"
	"xenial"
	"yakkety"
	"zesty"
	"artful"
	"bionic"
	"cosmic"
	"disco"
	"eoan"
	"focal"
	"groovy"
	"hirsute"
	"impish"
	"jammy"
	"kinetic"
	"lunar"
	"mantic"
	"noble"
	"oracular"
	"plucky"
	"questy"
	"resolute" # future - Ubuntu 26.10
)

# Comprehensive list of architectures currently in the Ubuntu archive project (archive is the main Ubuntu project, not the ports)
ubuntu_architectures=(
	"amd64"
	"i386"
)

# Comprehensive list of architectures currently in the Ubuntu ports project
ubuntu_ports_architectures=(
	"arm64"
	"armhf"
	"ppc64el"
	"riscv64"
	"s390x"
)

# Comprehensive list of architectures currently in the debian archive project (archive is the main Debian project, not the ports)
debian_architectures=(
	"amd64"
	"arm64"
	"armel"
	"armhf"
	"i386"
	"ppc64el"
	"riscv64"
	"s390x"
)

# Comprehensive list of architectures currently in the debian ports project
debian_ports_architectures=(
	"alpha"
	"hppa"
	"hurd-amd64"	# hurd is not Linux
	"hurd-i386"	# hurd is not Linux
	"m68k"
	"loong64"
	"powerpc"
	"ppc64"
	"sh4"
	"sparc64"
	"x32"
)

is_valid_codename() {
	local -n codename_list

	case "${config_pscgdebos__debian_or_ubuntu}" in
		debian)
			codename_list=debian_codenames
			;;
		ubuntu)
			codename_list=ubuntu_codenames
			;;
		*)
			fatalError "Please either provide debian or ubuntu. You provided: ${config_pscgdebos__debian_or_ubuntu}."
			;;
	esac

	info "Checking if '${config_pscgdebos__debian_codename}' is a valid version of '${config_pscgdebos__debian_or_ubuntu}'..."
	for name in "${codename_list[@]}"; do
		if [[ "${config_pscgdebos__debian_codename}" == "$name" ]]; then
			return 0
		fi
	done
	return 1
}

#
# This can be set to mark some known versions. As it is tidious, only doing it for now for i386
# which has been missing packages (although still workable for quite a lot of things!) for half a decade now
#
check_architecture_recommendation() {
	: ${config_pscgdebos_action_on_unrecommended_rootfs_arch="fail"} # fail|warn
	if [ "${config_pscgdebos__debian_or_ubuntu}" = "ubuntu" ] && [ "$ARCH" = "i386" ] ; then
		if [ "$config_pscgdebos_action_on_unrecommended_rootfs_arch" = "fail" ] ; then
			fatalError "Ubuntu does not support i386 architecture in the latest versions. It is recommended that you don't build Ubuntu for i386. You can set config_pscgdebos_action_on_unrecommended_rootfs_arch=warn to continue anyway"
		else
			warn "Ubuntu does not support i386 architecture in the latest versions. It is recommended that you don't build Ubuntu for i386."
		fi
	fi
}

#
# Debian ports would only accept a subset of versions - so we need to check it
#
check_debian_ports() {
	# a separate function, as there is only one tested version of the Debian ports at this point, and I saw no reason
	# to do the bsp name fixup for the others, just yet. This can be a nice exercise as extra curriculum activity for the course
	if [ ! "${config_pscgdebos__debian_or_ubuntu}" = "debian" ] ; then
		return
	fi

	local -n codename_list
	local name
	case $ARCH in
		loongarch)
		codename_list=debian_ports_codenames
		for name in "${codename_list[@]}"; do
			echo "comparing ${config_pscgdebos__debian_codename} with $name"
			if [[ "${config_pscgdebos__debian_codename}" == "$name" ]]; then
				return 0
			fi
		done
		fatalError "You are trying to use Debian ports with a codename that is not supported: ${config_pscgdebos__debian_codename}. Please use one of the following: ${codename_list[@]}"
		;;
		*)
			# ignore for now, see comment about the fixup above
			;;
	esac
}

main() {
	if ! is_valid_codename "${config_pscgdebos__debian_or_ubuntu}" "${config_pscgdebos__debian_codename}"; then
		fatalError "${config_pscgdebos__debian_codename} is not a valid version of ${config_pscgdebos__debian_or_ubuntu}. Please set config_pscgdebos__debian_codename to a proper value"
	fi

	check_architecture_recommendation
	check_debian_ports
}

commonScriptPrologueLogRunAndEpilogue $@
