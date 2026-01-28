#!/bin/bash

#
# In general, in Alpine there is no need to be super user on the unpacked tarball.
# There is though a need to operate with sudo on files added with the package manager (apk)
#
main() {
	verbose "Setting a default root password"
	sudo chroot $ROOTFS_DIR $TARGETSHELL -c "	
	set -e
	echo -e 'thepscg.com\nthepscg.com\n' | passwd root
	exit 0
	" || fatalError "Failed to set root password in chroot"

	verbose "Disable root password"
	sudo chroot $ROOTFS_DIR sh -c "passwd -d root"
	# This would also enable an empty password (we could also remove the x from the root line at /etc/shadow)	
	# echo sudo chroot $ROOTFS_DIR sh -c "sed -i 's/^root:[^:]*:/root::/' /etc/shadow"	

	verbose "Custom simple message of the day. You can further add files by adding files e.g. to etc/update-motd.d"
	cat << EOF | sudo tee $ROOTFS_DIR/etc/motd
A generic motd for you our friend
EOF


	if grep -qv "The PSCG" $ROOTFS_DIR/etc/issue ; then
		sed -i "/$/s/^/The PSCG says 'physically': /" $ROOTFS_DIR/etc/issue
	fi

	if [ ! -f $ROOTFS_DIR/etc/issue.net ] ; then
		echo "The PSCG says 'networkly':" > $ROOTFS_DIR/etc/issue.net
	elif grep -qv "The PSCG" $ROOTFS_DIR/etc/issue.net ; then
		sed -i "/$/s/^/The PSCG says 'networkly': /" $ROOTFS_DIR/etc/issue.net
	fi

	# The following is of course super insecure. In some of the courses you will have exercises in increasing the security of it.
	verbose "Enabling root passwordless ssh and scp access"

	# Enable dropbear in openrc:
	# It would refuse to work without populating (even an empty) /etc/network/interfaces, so we create it.
	# It also has the nice side effect of setting up the lo interface which is not up by default (strange, but it is like this)	
	cat << EOF | sudo tee ${ROOTFS_DIR}/etc/conf.d/dropbear || fatalError "Failed to configure the dropbear ssh server for easy insecure root login"
DROPBEAR_OPTS="-B -R -p 22"
EOF
	touch $ROOTFS_DIR/etc/network/interfaces 
	sudo chroot "$ROOTFS_DIR" rc-update add dropbear # assume that if it doesn't work - opnerc is not installed and then it is fine

	# Alternatively, or in sysvinit without openrc, one could just run the command directly from inittab
	# if ! grep dropbear $ROOTFS_DIR/etc/inittab ; then
	# 	echo '::sysinit:/usr/sbin/dropbear -B -R -p 22' >> $ROOTFS_DIR/etc/inittab  || fatalError "Failed to add dropbear ssh server to inittab"
	# fi

	verbose "Setting hostname (you can fruther play with the pretty names etc. Try emojis or all kind of unicodes, have some fun"
	sudo $TARGETSHELL -c "echo ${config_distro__hostname} > ${ROOTFS_DIR}/etc/hostname"
}

commonScriptPrologueLogRunAndEpilogue $@

