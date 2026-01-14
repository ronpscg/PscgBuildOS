#!/bin/bash
#
# Compatible with: the debos training distro (do not confuse with the debos package, we became aware of years after this template O_o)
#
# This layer is responsible for:
# - Installing minimal required packages for networking (although, one could use busybox, at ramdisk, to configure before switch_root, a handy trick!)

LOCAL_APT_FLAGS="--no-install-recommends"

do_auto_dhcp_in_systemd_networkd() {
	if [ "${config_pscgdebos__network_manager}" = "systemd-networkd" ] ; then
		info "Auto enabling systemd-networkd with DHCP"
		sudo tee << EOF $ROOTFS_DIR/etc/systemd/network/20-wired.network > /dev/null || fatalError "Failed to create network enabling file"
[Match]
Name=en* wl* eth* wlan*

[Network]
DHCP=yes
EOF
	# Note that systemd does not enable a network service by default. So we enable it in the next line
	sudo chroot $ROOTFS_DIR bash -c "systemctl enable systemd-networkd" || fatalError "Failed to enable systemd-networkd.service"
	fi
}

main() {
	source_file_or_die $LOCAL_DIR/packages.deb.buildconfig # the package config is sourced but there will not be duplication of packages (from the other sourcing for cache building) so that is fine
	sudo chroot $ROOTFS_DIR bash -c "DEBIAN_FRONTEND=noninteractive ;  apt-get install -y $LOCAL_APT_FLAGS $pscg_debos_ubuntu_network_packages " || fatalError "Failed to run main logic"

	do_auto_dhcp_in_systemd_networkd
}


commonScriptPrologueLogRunAndEpilogue $@