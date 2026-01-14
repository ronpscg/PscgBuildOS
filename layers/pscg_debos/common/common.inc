#!/bin/bash

#-------------- this was in NB
# everything needs to be refactored, but it's not going to happen soon (Written: March 2022)


###########################
# variable definitions
###########################

# This is a drop in, and should be moved somewhere else
: ${src_system_files="$( cd "$( dirname "${BASH_SOURCE[0]}")" && pwd )"} # this is not the path that will be kept. those quick and dirty hacks will be moved to another project
: ${target_mounted_rootfs=$ROOTFS_DIR}

INSTALLER_DIR=$target_mounted_rootfs/home/installer

###########################
# function definitions
###########################
#
# The function copies  $src_system_files/${1} to $target_mounted_rootfs/${1} can start with /  and can be without - but must be under the layer directory
# 	The target folder must exist. 
#	If it fails, the script will exit.
# $1 - source file - can start with /  and can be without - but must be under the layer directory. 
# $2 - target file - absolute path with respect to the target
#
copySrcToTarget() {
	sudo cp $src_system_files/${1} $target_mounted_rootfs/${1} || fatalError "Failed to copy $src_system_files/$1 --> $target_mounted_rootfs/$1"
}

#------------endof this was in NB
#
#

# TODO probably refactor etc... but I did use this function
#
# The function copies  $targetfiles/${1} to $targetdir/${1} can start with /  and can be without - but must be under the layer directory
#       The target folder must exist.
#       If it fails, the script will exit.
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
export copyToRootfs
