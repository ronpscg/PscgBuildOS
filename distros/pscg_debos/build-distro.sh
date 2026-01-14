#!/bin/bash
# Distro build script.
# Builds the different components of the distro, such as [bootloader], ramdisk, Linux kernel, a core rootfs, and layers on top of the rootfs
# Creates an installer image.
#
# With minor changes, can create the same (runtime) distro workable from a removable media (e.g. as in Raspberry Pi). This is not done now.
#

build_distro__add_rootfs_layers() {
	banner_and_do add_layer $LAYERS_DIR/pscg_debos/init
	banner_and_do add_layer $LAYERS_DIR/pscg_debos/archive_utils
	banner_and_do add_layer $LAYERS_DIR/pscg_debos/network_minimal
	banner_and_do add_layer $LAYERS_DIR/pscg_debos/rootpassword_sshconfig_and_motd
	banner_and_do add_layer $LAYERS_DIR/pscg_debos/kernel_modules

	banner_and_do add_layer $LAYERS_DIR/pscg_debos/common

	build_distro__add_rootfs_layers_extra
}

#
# This is a place to add more layers. Some are included from external files or command line options. 
# Important ones that depend on important featuers (for now, GRAPHICS) are included via a very clear ENABLE_feature environment variable (clearer on the eyes, and easier to understand)
#
build_distro__add_rootfs_layers_extra() {

	if [ "$ENABLE_GRAPHICS" = "true" ] ; then
		# Weston would be the minimal and effective way to demonstrate (Wayland) graphics. X could be easily supported as well, but these years, Wayland is the de-facto standard.
		banner_and_do add_layer $LAYERS_DIR/pscg_debos/graphics/graphics-weston
		# could alternatively use graphics-full which is bloated with display managers, desktop environments, and other stuff
		#banner_and_do add_layer $LAYERS_DIR/pscg_debos/graphics/graphics-full
	fi

	if [ -f "$config_pscgdebos__extra_layers_file" ] ; then
		# This is a file with layers to add, one per line, and comments are allowed
		while read -r layerline ; do
			if [ -n "$layerline" ] && [[ ! "$layerline" =~ ^#.* ]] ; then
				layerline=$(eval echo $layerline) # in case it has variables, e.g. $LAYERS_DIR. Super insecure, beware eval!
				banner_and_do add_layer $layerline
			fi
		done < "$config_pscgdebos__extra_layers_file"
	fi
}

#
# distro specific function to do things in the rootfs *before* setting up a Linux kernel
#
pscg_debos_build_rootfs_pre_pass() {
	info "debootstrap-rootfs and prepare caches if necessary"
	banner_and_do $DISTROS_DIR/${config_distro}/recipes/rootfs/debootstrap-rootfs.sh || fatalError "debootstrap failed"
	banner_and_do source $LAYERS_DIR/pscg_debos/ubuntu_apt_sources/ubuntu-common.inc # Definitions used when building the caches
	# todo: if this file is updated with more layers, one needs to force redownloading the caches
	banner_and_do $DISTROS_DIR/${config_distro}/build-caches.sh || fatalError "Failed to build caches"
}

#
# distro specific function to do things in the rootfs before packing. Can, for example
# apply cleanups and so, e.g. after testing.
# This can be also a good place to unpack kernel modules and firmware onto a rootfs,
# (but for that I will need to test a crossdepmod stepp and see then)
#
pscg_debos_build_rootfs_post_pass() {
	if [ "$config_pscgdebos__postbuild_clean_apt_caches" = "true" ] ; then
		hardWarn "Size before cleaning up: $(sudo du -sh $ROOTFS_DIR)"
		# Could do with a little bit more finness e.g. "apt autoremove -y ; apt clean ; rm -rf /var/lib/apt/lists" etc...
		sudo rm -rf $ROOTFS_DIR/var/lib/apt/*
		sudo rm -rf $ROOTFS_DIR/var/cache/apt/*
		hardWarn "Size after cleaning up: $(sudo du -sh $ROOTFS_DIR)"
	fi
}
