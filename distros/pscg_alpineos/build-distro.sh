#!/bin/bash
# Specific distro build script. Levarages the generic build-distro-*.sh
#
# About the design of the pscg_alpine root filesystem:
#
# 1. We take a tarball from the minimal base of alpine
# 2. We use it as the root filesystem
# 3. The rest is as per the generic linux distro mechanism
#
# Important build system concept introduced here:
#  - https://www.youtube.com/watch?v=z5knWzLTGt8&list=PLBaH8x4hthVysdRTOlg2_8hL6CWCnN5l-&index=42
#     - Video recorded: Apr 11 2024
#  - https://www.youtube.com/watch?v=iBHb7rhtGCk&list=PLBaH8x4hthVysdRTOlg2_8hL6CWCnN5l-&index=132
#     - Video recorded: Jan 29 2026

#
# $1: target dir
#
add_some_packages_for_alpine() {
	local dst=$1
	if [ -z "$dst" -o "$dst" = "/" ] ; then
		fatalError "Refusing to let you destroy your own host!"
	fi
	# We use a subshell to allow cleanups as I decided to give the speed up solution here, and not demonstrate the slowness at this time
	# Foreign architectures may not enjoy the speedup as you wish, so to quickly demonstrate several builds,
	# if the ARCH is not the local arch I don't bother installing the packages. Remember, this is an answer to a meetup question!
	# I just felt kind and responded
	(
	if ! test -c  $dst/dev/null ; then
		verbose_do_or_die sudo mknod $dst/dev/null c 1 3 # this is not the issue for alpine apk in chroot
	fi
	verbose_do_or_die sudo mount -t tmpfs none $dst/tmp # this is absolutely an issue for alpine apk in chroot, at least as per the time of writing it. mounting tmpfs significantly speeds up packaage installations
	if [ "$config_distro__add_oot_ota_code" = "true" ] ; then
			# install this to allow running tune2fs from the command line
			verbose_do_or_die sudo chroot $dst sh -c "apk add e2fsprogs e2fsprogs-extra"
	fi

	if [ "$(uname -m)" = "x86_64" -a "$ARCH" = "x86_64" ] ; then
		verbose_do_or_die sudo chroot $dst sh -c 'apk add cmatrix'
		verbose_do_or_die sudo chroot $dst sh -c "apk add dropbear"
	fi

	) || error=true


	sudo rm $dst/dev/null || error "Can't cleanup dev/null"
	sudo umount $dst/tmp || fatalError "Can't unmount /dev/null and this can end up bad for your host. Please fix it manually before building again!"

	if [ "$error" = "true" ] ; then
		fatalError "Failed to do chroot stuff"
	fi

}

#
# Source more config files that are specific to the distro
#
build_distro__source_distro_specific_configs() {
	:
}

#
# distro specific function to do things in the rootfs *before* setting up a Linux kernel
#
pscg_alpineos_build_rootfs_pre_pass() {
	info "get the distro's rootfs tarballs and prepare caches if necessary"
	banner_and_do $DISTROS_DIR/${config_distro}/recipes/rootfs/debootstrap-equivalent-rootfs.sh || fatalError "debootstrap equivalent failed"		
	banner_and_do $DISTROS_DIR/${config_distro}/build-caches.sh || fatalError "Failed to build caches"
}


#
# add layers after a prepass
#
build_distro__add_rootfs_layers() {
	banner_and_do add_layer $LAYERS_DIR/pscg_alpineos/init
	banner_and_do add_layer $LAYERS_DIR/pscg_alpineos/network_minimal	
	banner_and_do add_layer $LAYERS_DIR/pscg_alpineos/rootpassword_sshconfig_and_motd
	banner_and_do add_layer $LAYERS_DIR/pscg_alpineos/common
}

#
# distro specific function to do things in the rootfs before packing. Can, for example
# apply cleanups and so, e.g. after testing.
# This can be also a good place to unpack kernel modules and firmware onto a rootfs,
# (but for that I will need to test a crossdepmod stepp and see then)
#
pscg_alpineos_build_rootfs_post_pass() {
	if [ "$config_pscg_alpineos__postbuild_clean_apk_caches" = "true" ] ; then
		# you could clean repositories if you wish too, e.g. remove var/cache/apk/APKINDEX.* etc...
		sudo rm -rf $ROOTFS_DIR/var/cache/apk/APKINDEX.* # that's fine there is read access for the directory so '*'' works
		sudo rm -rf $ROOTFS_DIR/var/cache/apk/*.apk
	fi

	# Do note that us downloading caches and keeping them is not apk's default behavior! we only do it to avoid
	# redownloading and unpacking if not necessary. Trade-offs, as explained in multiple places for multiple distros...
}

#
# Alpine Linux's downloads page does not support riscv so we don't support it.
# this is just a demonstration (which can be used to later provide a different distro layer hierarchy, for alpine apk package management on build time)
# so it is not as extensive as the Debian builds (which start with debootstrap)
#
# Not all architecture combinations have been tested, and this one was hacked in minutes - so don't count on it, at least yet
#
# Good indication of running the wrong things: "request_module: modprobe binfmt-464c cannot be processed, kmod busy with 50 threads for more than 5 seconds now"
#
pscg_alpineos__init_env() {
	# moved to debootstrap
	:
}
