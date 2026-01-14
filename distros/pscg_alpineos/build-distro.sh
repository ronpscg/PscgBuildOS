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
#     - Video recorded: Apr 11: 2024
#

#
# $1: target dir
#
modify_etc_for_alpine() {
	local dst=$1
	if [ ! -d $dst/etc ] ; then
		verbose_do_or_die mkdir $dst/etc
	fi
	info "Updating some etc entries in rootfs such as version files, hostname, resolv.conf and inittab"
	echo -e VERSION=\"thepscg-alpine-$(date '+%y-%m-%d_%H-%M-%S')\" > $dst/etc/thepscgos-release

	echo -e "${config_distro}" | sudo tee >/dev/null $dst/etc/hostname

	sudo chroot $dst sh -c "echo -e 'thepscg.com\nthepscg.com\n' | passwd root" || fatalError "Failed to change root password"

	# This is required for installing pacakges in chroot. We could go the extra mile and mount dev and tmpfs in it but we won't
	sudo chroot $dst sh -c "echo nameserver 8.8.8.8 > /etc/resolv.conf" || fatalError "Failed to set resolv.conf"

	# In the post unpack commands we edited the inittab in one way (For the console).
	# Now we'll set host name in another way, so it will be nice on the eyes
	sudo chroot $dst sh -c "if ! grep '::sysinit:/bin/hostname -F /etc/hostname' /etc/inittab ; then
		echo '::sysinit:/bin/hostname -F /etc/hostname' >> /etc/inittab ; fi" || fatalError "Failed to set hostname in inittab"
}

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
# Educational: we show that the exact same code of the ramdisk as is,
# or a part of it (the busybox part) can be used as a rich rootfs
#
pscg_alpineos_build_rootfs_pre_pass() {

	pscg_alpineos__init_env $@
	# dod init_folders
	verbose "Building ${config_distro} rootfs..."

	info_do_or_die do_fetch
	# Kindly note how we added a post_unpack step to modify the inittab file
	info_do_or_die do_unpack
}

#
# add layers after a prepass
#
build_distro__add_rootfs_layers() {
	modify_etc_for_alpine $ROOTFS_DIR
	add_some_packages_for_alpine $ROOTFS_DIR
}

#
# distro specific function to do things in the rootfs before packing. Can, for example
# apply cleanups and so, e.g. after testing.
# This can be also a good place to unpack kernel modules and firmware onto a rootfs,
# (but for that I will need to test a crossdepmod stepp and see then)
#
pscg_alpineos_build_rootfs_post_pass() {
	# you could clean repositories if you wish too, e.g. remove var/cache/apk/APKINDEX.* etc...
	sudo rm -rf $ROOTFS_DIR/var/cache/apk/APKINDEX.* # that's fine there is read access for the directory so '*'' works
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
	# bash note: note that we avoided sourcing in pscg_alpineos.buildconfig.
	# Instead, the file is sourced here directly, as declared arrays are a mess upon sourcing.
	# This is an example of using complex bash concepts for brevity (most of the build system aims
	# to avoid them, for these reasons (and for easing up on those new to bash)
	#
	# Also, source_file_or_die does not play nicely with declared variables! So let's source directly
	# Then, let's verify that it has been sourced correctly, or blow up the run
	source "$DISTROS_DIR/pscg_alpineos/pscg_alpineos.minirootfs_upstream.buildconfig"
	eval_or_die "declare | grep -q ALPINEOS_MINI_ROOTFS_ARRAY"

	local archadj=$ARCH
	# Current version: v3.22.1. Currently supported archs: (aarch64 armhf armv7 loongarch64 ppc64le riscv64 s390x x86 x86_64)
	case $ARCH in
		x86_64)
			;;
		arm64)
			archadj=aarch64
			;;
		i386)
			archadj=x86
			;;
		arm)
			case $config_toplevel__arch_subarch in
				""|armv7)
					archadj=armv7
					;;
				armhf)
					archadj=armhf
					;;
				armel)
					fatalError "Please don't use armel with this distro - it does not refer to non armhf as Debian does do"
					;;
				*)
					fatalError "Invalid subarch for arm $config_toplevel__arch_subarch"
					;;
			esac
			;;
		riscv)
			archadj=riscv64
			;;
		loongarch)
			archadj=loongarch64
			;;
		powerpc)
			archadj=ppc64le
			;;
		s390)
			archadj=s390x
			;;
		*)
			fatalError "${config_distro} rootfs environment expects other architectures than $ARCH. Perhaps you can create one with
https://git.alpinelinux.org/aports/tree/scripts/bootstrap.sh, upload it + sha256 sum somewhere, and update the script"
			;;
	esac

	echo ${ALPINEOS_MINI_ROOTFS_ARRAY[@]}
	echo "$ARCH"
	echo "$archadj"

	fetch_remote_uri=${ALPINEOS_MINI_ROOTFS_ARRAY["${archadj}_tarball"]}
	fetch_expected_sha256=${ALPINEOS_MINI_ROOTFS_ARRAY["${archadj}_sha256"]}
	warn fetch_remote_uri=${ALPINEOS_MINI_ROOTFS_ARRAY["${archadj}_tarball"]}
	warn fetch_expected_sha256=${ALPINEOS_MINI_ROOTFS_ARRAY["${archadj}_sha256"]}
	if [ -z "$fetch_remote_uri" -o -z "fetch_expected_sha256" ] ; then
		fatalError "Your rootfs uri/sha256 are missing"
	fi
	fetch_local_target_path=$config_toplevel__downloads_base_path/$(basename $fetch_remote_uri) # we assume the URI ends with the tarball name
	# Note this unpacking will not be as super user. If you have a tarball and want to keep permissions, you should implement sudo for the unpack
	# which I have not done deliberately
	unpack_dest_path=$ROOTFS_DIR
	# Note: alpine hardcodes ttyS0 for all architectures

	post_unpack_command='sed -i "s/#ttyS0::respawn:\/sbin\/getty -L 115200 ttyS0 vt100/$CONSOLE_DEV_TTY::respawn:\/sbin\/getty -L $CONSOLE_DEV_TTY 115200 linux/" $unpack_dest_path/etc/inittab'

	# temp remove login - annoying but couldn't make /bin/sh -l easily
	post_unpack_command='sed -i "s/#ttyS0::respawn:\/sbin\/getty -L 115200 ttyS0 vt100/$CONSOLE_DEV_TTY::respawn:\/sbin\/getty -n -l \/bin\/sh -L $CONSOLE_DEV_TTY 115200 linux/" $unpack_dest_path/etc/inittab'

	# Could do something with less escaping, such as:
	# post_unpack_command='sed -i "s|#ttyS0::respawn:/sbin/getty -L 115200 ttyS0 vt100|$CONSOLE_DEV_TTY::respawn:/sbin/getty -L $CONSOLE_DEV_TTY 115200 linux|" $unpack_dest_path/etc/inittab'

	# for fun, let's add the addition of supporting the hvc0 console device, in case QEMU is used and we wish
	# to enable its hypervisor console as well
	if ! grep -q "hvc0::respawn:/sbin/getty -L 115200 hvc0 linux" $unpack_dest_path/etc/inittab ; then
		post_unpack_command="$post_unpack_command && echo 'hvc0::respawn:/sbin/getty -L 115200 hvc0 linux' >> $unpack_dest_path/etc/inittab"
	fi

	if ! grep -q "hvc0::respawn:/sbin/getty -L 115200 hvc0 linux" $unpack_dest_path/etc/inittab ; then
		post_unpack_command="$post_unpack_command && echo 'hvc0::respawn:/sbin/getty -L 115200 hvc0 linux' >> $unpack_dest_path/etc/inittab"
	fi

	if [ "$config_distro__add_oot_ota_code" = "true" ] ; then
		# add the ota-update.sh to inittab so that it runs at startup
		post_unpack_command="$post_unpack_command && echo '::sysinit:/opt/ota/ota-update.sh &' >> $unpack_dest_path/etc/inittab"
	fi
}
