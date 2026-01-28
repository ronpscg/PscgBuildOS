#!/bin/bash
#
# Compatible with: the pscg_alpineos training distro.
#

main() {
        source_file_or_die $LOCAL_DIR/packages.apk.buildconfig
        sudo chroot $ROOTFS_DIR sh -c "apk add $LOCAL_APK_FLAGS $pscg_alpineos__misc_common_packages" || fatalError "Failed to run main logic"
}

commonScriptPrologueLogRunAndEpilogue $@