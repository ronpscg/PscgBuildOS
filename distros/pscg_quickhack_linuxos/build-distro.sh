#!/bin/bash
#
# Specialized distro build script for the quick hacker. You can use this as a template.
#
#
#
# About the design of this quick hacked program
#
# 0. We take a ready system built by pscg_debos or pscg_busyboxos and reuse everything but the rootfs as is
# 1. We copy the rootfs
# 2. We add some minor but noticable additions to it
# 3. The imager takes care of the rest
#

# Developer note:
# This evals quickly demonstrate how to n. ot use any specific function names, if you want to copy paste it to another distro/file
# (i.e.: 1. Make a folder 2. Create a .buildconfig (if you wish) 3. Copy this file into this folder, and modify the file )
# although I might just not call a function based on the distro name in the first place, there is only one
# distro building at a given time

#
# Source more config files that are specific to the distro
# The example below shows an empty implementation, but you can remove it if you want, as it is called conditionally
#
build_distro__source_distro_specific_configs() {
	:
}

#
# Rootfs contents before building a kernel (e.g. initial setup)
#
eval "${config_distro}_build_rootfs_pre_pass() { local_distro_build_rootfs_pre_pass ; }"

#
# Rootfs cleanups or some additional thing you want right before packing
#
eval "${config_distro}_build_rootfs_post_pass() { local_distro_build_rootfs_post_pass ; }"


qd_extract_alpine_tarball_to_rootfs() {
	verbose_do_or_die sudo tar -C $ROOTFS_DIR -xf $tarball
	quick_demonstration_modify_hostname_and_versions_file $ROOTFS_DIR
}

qd_copy_alpine_tarball_to_overlays() {
	local dst=$distro__image_materials_installables_overlays_dir/system
	verbose_do_or_die mkdir -p $dst
	verbose_do_or_die cp -a $tarball $dst
}

qd_copy_alpine_tarball_to_writableoverlays() {
	local dst=$distro__image_materials_installables_writableoverlays_dir/system
	verbose_do_or_die mkdir -p $dst
	verbose_do_or_die cp -a $tarball $dst
}

local_distro_build_rootfs_pre_pass() {
	tarball=/tmp/alpine-minirootfs-3.19.1-x86_64.tar.gz
	if [ ! -e $tarball ] ; then
		do_or_die wget https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-x86_64.tar.gz -O $tarball
	fi
	sudo rm -rf $ROOTFS_DIR
	do_or_die mkdir $ROOTFS_DIR

	# demonstration: these three are mutual exclusive, before showing a combination solution
	# qd_extract_alpine_tarball_to_rootfs 		# What we have done in the previous video - refactored into a function
	# qd_copy_alpine_tarball_to_overlays			# demonstrate tarball overlays
	# qd_copy_alpine_tarball_to_writableoverlays	# demonstrate writable overlays

	combination_solution # hide the implementation - we'll get to that after we cover the rest


	unset tarball

}
#
# This example updates the /etc/thepscgos-release and hostname (latter mostly to be obvious on the console output)
#
# $1: target dir (most likely a rootfs in our design)
#
quick_demonstration_modify_hostname_and_versions_file() {
	local dst=$1
	if [ ! -d $dst/etc ] ; then
		verbose_do_or_die mkdir $dst/etc
	fi
	info "Hacking the version file of the rootfs"
	echo -e VERSION=\"thepscg-${distro#*_}-$(date '+%y-%m-%d_%H-%M-%S')\" | sudo tee >/dev/null $dst/etc/thepscgos-release

	echo -e "${config_distro}" | sudo tee >/dev/null $dst/etc/hostname

}


build_distro__add_rootfs_layers() {
	:
}

local_distro_build_rootfs_post_pass() {
	:
}

#
# After running this, you will be able to type in the serial console, and you will see your shiny hacky hostname instead of (none), after running # hostname -F /etc/hostname
#
combination_solution() {
	qd_copy_alpine_tarball_to_overlays # could also use the copying as is
	# Now, I can create an overlayfs structure on the host, and edit the files (e.g. delete) from the merged directory
	# This is necessary only if I delete, not if I modify, otherwise I can use "upper"
	#
	# But since we know how "deleting" works, let's go ahead and do just that. For changes, we will introduce another file

	local folder=/tmp/blablaexample
	local tarball=/tmp/blabla.tar	# we can also use just tar
	do_or_die rm -rf $folder $tarball
	do_or_die mkdir -p $folder/etc

	cd $folder/etc
	mknod inittab -m a= c 0 0
	echo "hacky-hostname" > hostname
	# you will still see (none) because /etc/hostname is only processed when someone calls hosname
	cd -

	debug_do_or_die tar -C $folder -cvf $tarball .

	local dst=$distro__image_materials_installables_writableoverlays_dir/system
	verbose_do_or_die mkdir -p $dst
	verbose_do_or_die cp -a $tarball $dst
}

return # cut the rest of the file


#
# Rootfs "layers and recipes" you would like to add
#
build_distro__add_rootfs_layers() {
	# Note that this is the same directory! I deliberately show the other usages!
	debug_do_or_die quick_demonstration_modify_hostname_and_versions_file $ROOTFS_DIR
	debug_do_or_die quick_demonstration_change_rootfs_stuff $distro__image_materials_installables_system_dir
}

###
### Implementation of specific examples is below
###

#
# This example reuses the rootfs of another prebuilt image materials
#
local_distro_build_rootfs_pre_pass() {
	info "Copying rootfs - and slightly hacking it"
	debug_do_or_die remove_target_and_link_if_src_exists $distro__prebuilt_image_materials_installables_system_dir $distro__image_materials_installables_system_dir sudo
}

#
# This example cleans up caches if the prebuilt system was debian
#
local_distro_build_rootfs_post_pass() {
	hardWarn "Size before cleaning up: $(sudo du -sh $ROOTFS_DIR)"
	sudo rm -rf $ROOTFS_DIR/var/lib/apt/*
	sudo rm -rf $ROOTFS_DIR/var/cache/apt/*
	hardWarn "Size after cleaning up: $(sudo du -sh $ROOTFS_DIR)"
}


#
# This example hacks some more stuff
# $1: target dir (most likely a rootfs in our design)
#
quick_demonstration_change_rootfs_stuff() {
	local dst=$1
	info "$FUNCNAME: hacking $dst"
	verbose "setting root autologin"
	echo tty [12345] /dev/$CONSOLE_DEV_TTY linux noclear nowait nologin  | sudo tee $dst/etc/finit.d/available/getty.conf

	# If bash exists, use it
	if [ "$(readlink $dst/bin/sh)" = "dash" \
			-a -x  $dst/bin/bash ] ; then
		sudo rm $dst/bin/sh
		sudo ln -s bash $dst/bin/sh
	fi
}
