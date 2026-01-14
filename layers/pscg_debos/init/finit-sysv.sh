#!/bin/bash
#
# Simple installation of the finit init framework. Since the modifications to the defaults are minimal, we do not provide and copy configuration files, but rather
# append the little required extra (serial console device).
#

: ${CONSOLE_DEV_TTY=ttyAMA0} 			# While this solves one of the exercises usually given, it helps with easy setting up of demos
LOCAL_APT_FLAGS="--no-install-recommends"	# for slimmer packages. if you want rsyslog as part of the installation, use the install recommends
LOCAL_APT_FLAGS="$LOCAL_APT_FLAGS -o Dpkg::Options::='--force-confnew'" # If you are reinstalling on an existing system - recreate the configuration file, and then do the changes. If you are building from scratch, it doesn't matter. If you are building from scratch, it doesn't matter


main() {
	source_file_or_die $LOCAL_DIR/packages.$(basename -s .sh $0).deb.buildconfig # the package config is sourced but there will not be duplication of packages (from the other sourcing for cache building) so that is fine

	sudo chroot $ROOTFS_DIR bash -c "
		export DEBIAN_FRONTEND=noninteractive
		set -e
		apt-get install -y $APT_FLAGS $LOCAL_APT_FLAGS $LOCAL_INSTALL_PACKAGES
		# Configure serial console for the init framework
		if grep -qv $CONSOLE_DEV_TTY $CONSOLE_DEV_TTY /etc/finit.d/available/getty.conf ; then
			echo tty [12345] /dev/$CONSOLE_DEV_TTY linux noclear nowait >> /etc/finit.d/available/getty.conf
		fi
	"
}

commonScriptPrologueLogRunAndEpilogue $@
