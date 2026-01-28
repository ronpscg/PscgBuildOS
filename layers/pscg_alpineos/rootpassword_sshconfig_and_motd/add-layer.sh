#!/bin/bash
#
# Compatible with: the pscg_alpineos training distro (do not confuse with the debos package, we became aware of years after this template O_o)
#
# This layer is responsible for:
# - default root password (insecure to be hardcoded!)
# - ssh root login (insecure, exercise: secure that)
# - setting hostname
# - adding message of the day


#
# Make things easier to follow then adding escapes and evals when using some of the print macro functions
#
populate_etc_thepscgos_release_file() {
	local dst=$1
	echo -e VERSION=\"thepscg-alpineos-${ALPINEOS_VERSION}-$(date '+%y-%m-%d_%H-%M-%S')\" > $dst/etc/thepscgos-release

	return
	# TODO: Can unify this function across all distors essentially. I deliberately did not touch /etc/os-release (which appears for Debian and Alpine)
}

main() {
	: ${pscgdebos_version=pscg-os-555}
	cd $LOCAL_DIR

	export TARGETSHELL=sh

	# set version file. encapsulated in a function so that it is easier to follow the code itself, without decyphering wrapping printing methods escape characters
	banner_and_do populate_etc_thepscgos_release_file $ROOTFS_DIR || fatalError "Failed to set the version file"

	# Demostrate some chroot and direct file population capabilities
	banner_and_do $LOCAL_DIR/set_rootpassword_sshconfig_hostname_and_motd.sh || fatalError "Failed to run main logic"

	# I think I made an equivalent for update-motd.d for busyboxos and alpineos but perhaps it is not in this project
	# It's just an example, so for now leaving it as is. BTW - the file is populated by the OTA layer anyhow. It is OK to have 
	# a default as in debos (in case there is no OTA at all). 
}


commonScriptPrologueLogRunAndEpilogue $@