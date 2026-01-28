#!/bin/bash
#
# Compatible with: the pscg_alpineos training distro
#
# This layer is responsible for:
# - Installing minimal required packages for networking (although, one could use busybox, at ramdisk, to configure before switch_root, a handy trick!)

main() {
        source_file_or_die $LOCAL_DIR/packages.apk.buildconfig
        sudo chroot $ROOTFS_DIR sh -c "apk add $LOCAL_APK_FLAGS $pscg_alpineos__network_packages" || fatalError "Failed to run main logic"
}

commonScriptPrologueLogRunAndEpilogue $@