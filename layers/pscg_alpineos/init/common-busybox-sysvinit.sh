#!/bin/bash
#
# Simple customization of the busybox init framework that is common for both the Alpine's minirootfs default init (busybox)
# which does not need to be installed, and to the openrc init manager.
# Here we just take care of inittab which is used for both.
# Since the modifications to the defaults are minimal, we do not provide and copy configuration files, but rather
# append the little required extra (serial console device).
#

: ${CONSOLE_DEV_TTY=ttyAMA0} 			# While this solves one of the exercises usually given, it helps with easy setting up of demos

main() {
	sed -i "s|#ttyS0::respawn:/sbin/getty -L 115200 ttyS0 vt100|$CONSOLE_DEV_TTY::respawn:/sbin/getty -L 115200 $CONSOLE_DEV_TTY linux|" $ROOTFS_DIR/etc/inittab	
	# remove login
	sed -i "s|/sbin/getty -L 115200 $CONSOLE_DEV_TTY linux|/sbin/getty -n -l /bin/sh -L 115200 $CONSOLE_DEV_TTY linux|" $ROOTFS_DIR/etc/inittab
	
	# add hvc0 console device, in case QEMU is used and we wish to enable its hypervisor console as well
	# Note: it is very likely that if you run the rootfs in docker - it will continuosly complain that hvc0 does not exist	
	if ! grep -q "hvc0::respawn:/sbin/getty -L 115200 hvc0 linux" $ROOTFS_DIR/etc/inittab ; then
		echo 'hvc0::respawn:/sbin/getty -L 115200 hvc0 linux' >> $ROOTFS_DIR/etc/inittab
	fi
	
	# Force setting the hostname for logins. Otherwise, you will see (none) as the hostname (or whatever the kernel config, or initramfs set)
	
	if ! grep '::sysinit:/bin/hostname -F /etc/hostname' $ROOTFS_DIR/etc/inittab ; then
		echo '::sysinit:/bin/hostname -F /etc/hostname' >> $ROOTFS_DIR/etc/inittab  || fatalError "Failed to set hostname in inittab"
	fi
	
	if [ "$config_distro__add_oot_ota_code" = "true" ] ; then
		# add the ota-update.sh to inittab so that it runs at startup
		echo '::sysinit:/opt/ota/ota-update.sh &' >> $ROOTFS_DIR/etc/inittab
	fi
}

commonScriptPrologueLogRunAndEpilogue $@
