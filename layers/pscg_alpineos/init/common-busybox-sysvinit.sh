#!/bin/bash
#
# Simple customization of the busybox init framework that is common for both the Alpine's minirootfs default init (busybox)
# which does not need to be installed, and to the openrc init manager.
# Here we just take care of inittab which is used for both.
# Since the modifications to the defaults are minimal, we do not provide and copy configuration files, but rather
# append the little required extra (serial console device).
#

main() {
	# Unconditionally remove the commented line for the default interface, and replace it with the right console device if needs be
	sed -i "s|#ttyS0::respawn:/sbin/getty -L 115200 ttyS0 vt100|$CONSOLE_DEV_TTY::respawn:/sbin/getty -L 115200 $CONSOLE_DEV_TTY linux|" $ROOTFS_DIR/etc/inittab
	if [ "$config_pscg_alpineos__inittab_skip_console_login" = "true" ] ; then		
		# remove login
		sed -i "s|/sbin/getty -L 115200 $CONSOLE_DEV_TTY linux|/sbin/getty -n -l /bin/sh -L 115200 $CONSOLE_DEV_TTY linux|" $ROOTFS_DIR/etc/inittab
	else
		# Allow root login on tty (if it is not automatically enabled by avoiding login in the inittab)
		if ! grep -q $CONSOLE_DEV_TTY ${ROOTFS_DIR}/etc/securetty ; then
			echo $CONSOLE_DEV_TTY >> ${ROOTFS_DIR}/etc/securetty
		fi
	fi
	
	for a in $ADDITIONAL_CONSOLE_DEV_TTY_NODES ; do
	# add device, e.g. hvc0 console device, in case QEMU is used and we wish to enable its hypervisor console as well
	# Note: it is very likely that if you run the rootfs in docker - it will continuosly complain that hvc0 does not exist
	# so we modified it to be a build parameter
		if ! grep -q "$a::respawn:/sbin/getty -L 115200 $a linux" $ROOTFS_DIR/etc/inittab ; then
			echo "$a::respawn:/sbin/getty -L 115200 $a linux" >> $ROOTFS_DIR/etc/inittab
		fi
	done
	
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
