#!/bin/bash
#
# Simple installation of the finit init framework. Since the modifications to the defaults are minimal, we do not provide and copy configuration files, but rather
# append the little required extra (serial console device).
#

: ${CONSOLE_DEV_TTY=ttyAMA0} 			# While this solves one of the exercises usually given, it helps with easy setting up of demos

set_default_terminal_properties() {
	local profiledfile=pscg_alpineos_term_properties.sh
	sudo tee << EOF $ROOTFS_DIR/etc/profile.d/$profiledfile > /dev/null || fatalError "Failed to create $ROOTFS_DIR/etc/profile.d/$profiledfile"
export TERM=linux
EOF
}

main() {
	source_file_or_die $LOCAL_DIR/packages.$(basename -s .sh $0).apk.buildconfig # the package config is sourced but there will not be duplication of packages (from the other sourcing for cache building) so that is fine	
	sudo chroot $ROOTFS_DIR sh -c "apk add $LOCAL_APK_FLAGS $LOCAL_INSTALL_PACKAGES" || fatalError "Failed to install openrc"

	verbose_do_or_die $LOCAL_DIR/common-busybox-sysvinit.sh
	
	set_default_terminal_properties
}

commonScriptPrologueLogRunAndEpilogue $@
