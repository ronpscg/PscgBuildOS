#!/bin/bash
# Distro build script.
# Builds the different components of the distro, such as [bootloader], ramdisk, Linux kernel, a core rootfs, and layers on top of the rootfs
# Creates an installer image.
#
# With minor changes, can create the same (runtime) distro workable from a removable media (e.g. as in Raspberry Pi). This is not done now.
#

#
# About the design of the pscg_busyboxos root filesystem:
#
# The design aims to be super simple: same ramdisk or same busybox code built in the ramdisk,
# plus some additions such as inittab and OTA code.
#
#
# This is meant to demonstrate the following: We already have a ramdisk built. Two distros share
# the same ramdisk. We made an OTA code that would work on busybox as well, so we are going to
# "nicely cheat:"
#
# 1. We will copy to ramdisk from the other distro and use it as our own (proof that the richos is interchangable!)
# 2. We will copy additional code into that ramdisk [ as opposed to adding a layer to the rootfs - which is the change here ]
# 3. We will add more layers/code that we want to the ramdisk [e.g inittab for a rootfs instead of an init script on an initramfs]
# 4. We will repackage what we built (busyboxfs and rootfs based on this busyboxfs) in the image
#

#
# $1 ramdisk (or busybox install dir) path to copy
# $2 folder to copy to
quick_demonstration_reuse_ramdisk_as_the_flashable_rootfs() {
	local src=$1
	local dst=$2
	do_or_die [ -d $src ]
	if [ ! -d  $dst ] ; then
		do_or_die mkdir $dst
	fi
	debug_do_or_die cp -a $src/* $dst/

	# assure some expected folders exist for the ramdisk mount moving prior to switch_root
	# we could change the ramdisk code, but it is unreasonable to use a file system that is not
	# at least close to the LSB, so we make sure we at least have the dignity to provide such
	[ -d $dst/proc ] || verbose_do_or_die mkdir $dst/proc
	[ -d $dst/sys ] || verbose_do_or_die mkdir $dst/sys
	[ -d $dst/dev ] || verbose_do_or_die mkdir $dst/dev
	[ -d $dst/tmp ] || verbose_do_or_die mkdir $dst/tmp
}

# Despite the DHCP notes below (read them, as they were an important exercise) - we will make things
# easier for you, and for me as a user ( :-) ) by copying the relevant networking code (DHCP hooks)
# which is useful for automatically setting eth0 etc.
quick_demonstration_add_more_files_to_the_flashable_rootfs() {
	local dst=$1
	do_or_die [ -d $src ]
	cp -rp $LAYERS_DIR/common/recipes/ramdisk/files/network   $dst || fatalError "Failed to copy the ramdisk network setup code"
	if [ "$config_distro__add_oot_ota_code" = "true" ] ; then
		$BUILD_TOP/layers/common/prebuilts/copy-prebuilts-e2fsprogs-to-ramdisk.sh $dst || fatalError "Failed to copy e2fsprogs prebuilts to the rootfs at $dst"
	fi
}

#
# This example updates the /etc/pscgos-release files and demonstrates adding an /etc/inittab for busybox
#
# $1: target dir (most likely a rootfs in our design where the initramfs has a hand crafted init)
#
# Educational:
# If /etc/inittab not exist, and the init is busybox (/sbin/init), you will get a prompt
# to hit enter, such as "Please press Enter to activate this console."
# (that is askfirst::-/bin/sh. the '-' sign by the way enables job control)
#
# But if we want to for example get networking called (otherwise no OTA) and ota-update.sh code
# executed automagically, we need to tell init to do so, via an inittab.
# It is a good example to show how this fascilitates automatic networking, so we show here
# what happens WITHOUT explicitly copying from the ramdisk the /network/ code from the ramdisk sources.
# What would happen then, is that you would not have a DHCP hook, and consequently will have to
# call udhcpc and a set of ip commands (set link up, assign the lease address statically, and set the default gw)
# For example (this is just showing off, and is unwise - using dhcp hooks is wise):
# ip link set eth0 up && udhcpc 2>/tmp/dhcp.err && \
# addr=$(grep "lease of" /tmp/dhcp.err | cut -d' ' -f4) && \
# gw=$(grep "lease of" /tmp/dhcp.err | cut -d' ' -f7 | tr -d ',') && \
# ip addr add  $addr dev eth0 && ip route add default dev eth0  && rm /tmp/dhcp.err
#
# This does not set, i.e. dns entries, subnet masks, etc., so it is definitely not the way to do things!
#
# In other words, after experimenting a bit with the result, you may want to use the ramdisk as is, perhaps
# without copying more prebuilts into it / or copy explicitly.
#
quick_demonstration_make_inittab_for_busybox() {
	local dst=$1
	if [ ! -d $dst/etc ] ; then
		verbose_do_or_die mkdir $dst/etc
	fi
	info "Updating the version file of the rootfs, just for fun (ramdisk copy doesn't need it, busybox only 'does')"
	echo -e VERSION=\"thepscg-busyboxos-$(date '+%y-%m-%d_%H-%M-%S')-rootfs\" > $dst/etc/thepscgos-release

cat << EOF > $dst/etc/inittab
::sysinit:/bin/echo -e "\x1b[42mThePSCG says: Hello sysinit!\x1b[0m"
::respawn:-/bin/sh
::sysinit:/bin/echo -e "\x1b[43mThePSCG says: Hello after login shell sysinit - will still appear before an askfirst\x1b[0m"
::sysinit:/network/try-udhcpc.sh
# One could go ahead and respawn it but it not a good idea, as respawning processes can end up with an infinite respawning loop if the process exits (even normally) after running
# Note: if you don't run in the background, and run it in sysinit, you will not see shell until it returns. If it does not return, well...
::sysinit:/opt/ota/ota-update.sh &
EOF
}

build_distro__add_rootfs_layers() {
	quick_demonstration_make_inittab_for_busybox $ROOTFS_DIR
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
pscg_busyboxos_build_rootfs_pre_pass() {
	## In this example we use the ramdisk as is. A
	local use_ramdisk_as_is=true
	local sourcedirtouse

	# First build busybox. It will be used whether we use the ramdisk as is, or just use busybox build as is
	banner_and_do $LAYERS_DIR/common/recipes/$config_ramdisk__shell_swissknife/build-$config_ramdisk__shell_swissknife.sh     || fatalError "build-$config_ramdisk__shell_swissknife failed"

	# Could do with busybox. Yes, we will build the ramdisk twice here, but that's just a quick and dirty hack...
	# that I might get out of the way later
	if [ "use_ramdisk_as_is" = "true" ] ; then
		info build-initramfs before the rootfs
		banner_and_do $LAYERS_DIR/common/recipes/ramdisk/build-initramfs.sh     || fatalError "build-initramfs failed"
		verbose "Already built initramfs so we will not do it again"
		config_buildtasks__do_build_ramdisk=false
		sourcedirtouse=$RAMDISK_DIR
	else
		info "Using busybox install as the initramfs copy in the richos rootfs"
		sourcedirtouse=$BUSYBOX_INSTALL_DIR
	fi

	info "Copying initramfs into the image and using it as a flashable  rootfs"
	quick_demonstration_reuse_ramdisk_as_the_flashable_rootfs $sourcedirtouse $ROOTFS_DIR

	if [ ! "use_ramdisk_as_is" = "true" ] ; then
		quick_demonstration_add_more_files_to_the_flashable_rootfs $ROOTFS_DIR
	fi
}

#
# distro specific function to do things in the rootfs before packing. Can, for example
# apply cleanups and so, e.g. after testing.
# This can be also a good place to unpack kernel modules and firmware onto a rootfs,
# (but for that I will need to test a crossdepmod stepp and see then)
#
pscg_busyboxos_build_rootfs_post_pass() {
	:
}


