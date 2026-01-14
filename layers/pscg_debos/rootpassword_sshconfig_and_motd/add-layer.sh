#!/bin/bash
#
# Compatible with: the debos training distro (do not confuse with the debos package, we became aware of years after this template O_o)
#
# This layer is responsible for:
# - default root password (insecure to be hardcoded!)
# - ssh root login (insecure, exercise: secure that)
# - setting hostname
# - setting pretty host name and other pretty names for hostnamectl (and for neighboring devices)
# - adding message of the day


###########################
# function definitions (TODO: add to common utilities)
###########################
#
# The function copies  $src_system_files/${1} to $target_mounted_rootfs/${1} can start with /  and can be without - but must be under the layer directory
# 	The target folder must exist.
#	If it fails, the script will exit.
# $1 - source file - can start with /  and can be without - but must be under the layer directory.
# $2 - target file - absolute path with respect to the target
#
copyToRootfs() {
	local srcdir=targetfiles/
	local targetdir=$ROOTFS_DIR # TODO - add another script, or parameter or reomve local if, e.g. we want to do it in data dir
	if [ ! -d $(dirname $targetdir/${1}) ] ; then
		warn "You should not copy directories without taking care of the proper permissions!"
	fi
	sudo cp $srcdir/${1} $targetdir/${1} || fatalError "Failed to copy $srcdir/$1 --> $targetdir/$1"
}

#
# Make things easier to follow then adding escapes and evals when using some of the print macro functions
#
populate_etc_thepscgos_release_file() {
	: ${config_osrelease_name=pscgdebos}
	: ${config_osrelease_version=$pscgdebos_version}
	sudo bash -c "echo -e 'NAME=\"$config_osrelease_name\"\nVERSION=\"$config_osrelease_version\"\nID_LIKE=\"debian\"' > $ROOTFS_DIR/etc/thepscgos-release" || fatalError "Failed to set the version to $config_osrelease_version"
}

### TODO: add the banner function

main() {
	: ${pscgdebos_version=pscg-os-555}
	cd $LOCAL_DIR

	# set version file. encapsulated in a function so that it is easier to follow the code itself, without decyphering wrapping printing methods escape characters
	banner_and_do populate_etc_thepscgos_release_file || fatalError "Failed to set the version file"

	# Demostrate some chroot and direct file population capabilities
	banner_and_do $LOCAL_DIR/set_rootpassword_sshconfig_hostname_and_motd.sh || fatalError "Failed to run main logic"

	# Demonstrate copying from targetfiles/.../
	# Note the numbering and order in motd. The lower the number - the earlier it shows. Then, /etc/motd itself would be last.
	banner_and_do copyToRootfs etc/update-motd.d/01-versions-and-stats || fatalError "Failed to copy yet another motd"
}


commonScriptPrologueLogRunAndEpilogue $@