#!/bin/bash
#
# Compatible with: the debos training distro (do not confuse with the debos package, we became aware of years after this template O_o)
#
# This layer is responsible for:
# - Installing selected packages for graphics
#
# Since the level of customization here is huge, and getting into details can lead to not ever publishing the project, I leave it now
# as a placeholder, that one would want to specify with command line arguments, mostly.
#
# Otherwise, the default example would be:
# Without DRM support:
# - lightdm (which is not light at all, size-wise) for a Display Manager (read: greeter)
# - xfce4 for a desktop environment (also not light).  with lightdm, this pretty much provides for a raspberry pi experience
#
# With DRM support
# - weston (for wayland)
#

#LOCAL_APT_FLAGS="--no-install-recommends" # in this particular case, it is better to install recommends, unless you want to hand-pick and configure

do_lightdm_fixups() {
	if ! echo $pscg_debos_graphics_packages | grep -q lightdm ; then
		return
	else
		sudo grep -q "lightdm" $ROOTFS_DIR/etc/passwd || fatalError "No lightdm user available in $ROOTFS_DIR"
	fi
	verbose "Applying lightdm fixups"
	sudo chroot $ROOTFS_DIR chown lightdm:lightdm /var/lib/lightdm || fatalError "Failed to modify lightdm permissions. If you let this through, you will likely have bad errors, and will have to start your Desktop Environment yourself"
}

#
# This should be done only for systemd. I will no longer support other init frameworks with respect to graphics. You are welcome to do so.
# The idea behind it is simple: graphics are heavy, weather you like that or not, so there is no harm in having a powerful init framework if we are already going heavy
#
do_set_default_display_manager() {
	if [ -n "$pscg_debos_graphics_default_dm" ] ; then
		if [ -e $ROOTFS_DIR/lib/systemd/system/${pscg_debos_graphics_default_dm}.service ] ; then
			sudo chroot $ROOTFS_DIR bash -c "\
				rm -rf /etc/systemd/system/display-manager.service && \
				ln -s /lib/systemd/system/${pscg_debos_graphics_default_dm}.service /etc/systemd/system/display-manager.service ;\
			" || fatalError "Filed to change the default Display Manager (greeter) to ${pscg_debos_graphics_default_dm}"
		else
			fatalError "$pscg_debos_graphics_default_dm does not exist. Verify that you installed it and the unit file exists"
		fi
	fi

	# otherwise, leave whatever was selected by the packages
}

main() {
	source_file_or_die $LOCAL_DIR/packages.deb.buildconfig # the package config is sourced but there will not be duplication of packages (from the other sourcing for cache building) so that is fine
	if [ "$config_bsp__graphics_has_fbdev" = "true" ] ; then
		pscg_debos_graphics_packages+=" $pscg_debos_graphics_fbdev_packages"
	fi
	if [ "$config_bsp__graphics_has_dri" = "true" ] ; then
		pscg_debos_graphics_packages+=" $pscg_debos_graphics_dri_packages"
	fi

	pscg_debos_graphics_packages+=" $pscg_debos_graphics_common_packages"

	sudo chroot $ROOTFS_DIR bash -c "export DEBIAN_FRONTEND=noninteractive ;  apt-get install -y $LOCAL_APT_FLAGS $pscg_debos_graphics_packages " || fatalError "Failed to run main logic"

	# The if/else makes code a bit uglier, but the are here to emphasize the split to very optional packages, that may well be empty
	if [ -n "$pscg_debos_graphics_terminal_emulators_packages" ] ; then
		sudo chroot $ROOTFS_DIR bash -c "export DEBIAN_FRONTEND=noninteractive ;  apt-get install -y $LOCAL_APT_FLAGS $pscg_debos_graphics_terminal_emulators_packages " || fatalError "Failed to add terminal emulators"
	fi

	# More adjustments after installation
	do_lightdm_fixups
	do_set_default_display_manager
}


commonScriptPrologueLogRunAndEpilogue $@