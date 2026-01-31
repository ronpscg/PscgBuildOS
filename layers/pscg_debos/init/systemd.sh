#!/bin/bash
#
# Simple installation of the finit init framework. Since the modifications to the defaults are minimal, we do not provide and copy configuration files, but rather
# append the little required extra (serial console device).
#

LOCAL_APT_FLAGS="--no-install-recommends"	# for slimmer packages. if you want rsyslog as part of the installation, use the install recommends

set_default_terminal_properties() {
	local profiledfile=pscg_debos_term_properties.sh
	sudo tee << EOF $ROOTFS_DIR/etc/profile.d/$profiledfile > /dev/null || fatalError "Failed to create $ROOTFS_DIR/etc/profile.d/profiledfile"
export TERM=linux
EOF
}

main() {
	source_file_or_die $LOCAL_DIR/packages.$(basename -s .sh $0).deb.buildconfig # the package config is sourced but there will not be duplication of packages (from the other sourcing for cache building) so that is fine

	# This is a hack introduced in bookworm with graphics. There should be better ways to do it. The idea is to prevent such a line in /var/lib/dpkg/statoverride from
	# failing a tty-less (e.g. debootstrap) apt-get install:
	# root messagebus 4754 /usr/lib/dbus-1.0/dbus-daemon-launch-helper
	debug "Hacking statoverride for systemd reinstallation (a known problem in reusing images in Bookworm when dbus is installed (relevanat for the graphics only really, but needs to be handled in this step))"
	sudo chroot $ROOTFS_DIR bash -c "sed -i '/messagebus/d' /var/lib/dpkg/statoverride"

	sudo chroot $ROOTFS_DIR bash -c "
	export DEBIAN_FRONTEND=noninteractive
	set -e
	apt-get install -y $APT_FLAGS $LOCAL_APT_FLAGS $LOCAL_INSTALL_PACKAGES
	# Configure serial console for the init framework
	if grep -qv $CONSOLE_DEV_TTY /usr/lib/systemd/system/getty-static.service ; then
		## Exercise: The following is a valid solution - but would still need to disable things for 'green status':  Add this (don't deal with udev and systemd just yet
		#sed -i \"/ExecStart=/ s/$/ getty@$CONSOLE_DEV_TTY.service/\"  /usr/lib/systemd/system/getty-static.service
		# Keep not dealing with udev and systemd and disable the relevant service (Exercise: open getty by udev). Dont' be confused - systemd does not work on debootstrap - but disabling is just setting a link to /dev/null
		# You can 'just make things work' if you install the udev package. Otherwise - the following speeds up boot time (NOTE the masking, as the service would bet started by default otherwise), and get a getty on the console device REGARDLESS of whether it has been properly set up by udev (which is unnecessary for a serial device really)
		systemctl mask serial-getty@$CONSOLE_DEV_TTY.service
		systemctl enable console-getty

	fi
	" || fatalError "Failed to install and setup systemd"

	set_default_terminal_properties # TODO: can do something like this for the other distros as well. I only did it because the default of VT220 sometimes makes things look bad and it's hard to understand that the TERM= is the reason
}

commonScriptPrologueLogRunAndEpilogue $@
