#!/bin/bash
#
# Compatible with: the debos training distro (do not confuse with the debos package, we became aware of years after this template O_o)
#
# This layer is responsible for:
# - Installing minimal required packages for networking (although, one could use busybox, at ramdisk, to configure before switch_root, a handy trick!)

LOCAL_APT_FLAGS="--no-install-recommends"

main() {
	source_file_or_die $LOCAL_DIR/packages.deb.buildconfig # the package config is sourced but there will not be duplication of packages (from the other sourcing for cache building) so that is fine
	sudo chroot $ROOTFS_DIR bash -c "DEBIAN_FRONTEND=noninteractive ;  apt-get install -y $LOCAL_APT_FLAGS $pscg_debos_ubuntu_network_packages " || fatalError "Failed to run main logic"
}


commonScriptPrologueLogRunAndEpilogue $@