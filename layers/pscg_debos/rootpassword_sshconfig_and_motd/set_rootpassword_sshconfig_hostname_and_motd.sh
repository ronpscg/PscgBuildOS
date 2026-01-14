#!/bin/bash

main() {

	verbose "Setting default root password"
	sudo chroot $ROOTFS_DIR bash -c "
	export DEBIAN_FRONTEND=noninteractive
	set -e
	echo -e 'thepscg.com\nthepscg.com\n' | passwd root
	exit 0
	" || fatalError "Failed to set root password in chroot"

	# later I might do that
	# copySrcToTarget etc/update-motd.d/11-motd # could also remove the other things etc (TODO: after OTA is tested again in 2025)

	verbose "Custom simple message of the day. You can further add files by adding files e.g. to etc/update-motd.d"
	cat << EOF | sudo tee $ROOTFS_DIR/etc/motd
A generic motd for you our friend
EOF


	if grep -qv "The PSCG" $ROOTFS_DIR/etc/issue ; then
		sudo sed -i "/$/s/^/The PSCG says 'physically': /" $ROOTFS_DIR/etc/issue
	fi

	if grep -qv "The PSCG" $ROOTFS_DIR/etc/issue.net ; then
		sudo sed -i "/$/s/^/The PSCG says 'networkly': /" $ROOTFS_DIR/etc/issue.net
	fi

	# The following is of course super insecure. In some of the courses you will have exercises in increasing the security of it.
	verbose "Enabling root ssh and scp access"
	cat << EOF | sudo tee ${ROOTFS_DIR}/etc/ssh/sshd_config
Port 22
PermitRootLogin yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
AcceptEnv LANG LC_*
# The next line is mostly to be on the safe side as sftp is better than scp. Since OpenSSH 9.0 the scp utility uses the SFTP protocol by default.
Subsystem       sftp    /usr/lib/openssh/sftp-server

Banner /etc/issue.net
PrintMotd yes
EOF


	verbose "Setting hostname (you can fruther play with the pretty names etc. Try emojis or all kind of unicodes, have some fun"
	sudo bash -c "echo ${config_distro__hostname} > ${ROOTFS_DIR}/etc/hostname"
	# Some examples to explore with the output of hostnamectl
	cat << EOF | sudo tee ${ROOTFS_DIR}/etc/machine-info
PRETTY_HOSTNAME="Some nice text for earth habitats 🌎 "
ICON_NAME=video-display
CHASSIS=Super Strong Chassis
DEPLOYMENT=development
HARDWARE_VENDOR=The PSCG
HARDWARE_MODEL=Some Debian Related Training 5009
EOF
}

commonScriptPrologueLogRunAndEpilogue $@

