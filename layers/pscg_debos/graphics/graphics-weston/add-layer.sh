#!/bin/bash
#
# Compatible with: the debos training distro (do not confuse with the debos package, we became aware of years after this template O_o)
#
# This layer is responsible for:
# - Installing selected packages for running weston as the wayland compositor

LOCAL_APT_FLAGS="--no-install-recommends" # in this particular case, it is better to install recommends, unless you want to hand-pick and configure

do_populate_etc_profiled_file() {
	sudo tee << EOF $ROOTFS_DIR/etc/profile.d/pscg_debos_graphics_weston.sh > /dev/null || fatalError "Failed to create $ROOTFS_DIR/etc/profile.d/pscg_debos_graphics_weston.sh"
export XDG_RUNTIME_DIR=/tmp/xdg-runtime-dir
export WAYLAND_DISPLAY=wayland-1
EOF
}

#
# This should be done only for systemd. I will no longer support other init frameworks with respect to graphics. You are welcome to do so.
# The idea behind it is simple: graphics are heavy, weather you like that or not, so there is no harm in having a powerful init framework if we are already going heavy
#
# I will ***maybe*** also provide an alternative script, or maybe even just a set of scripts that take care of that
#
do_launch_weston_at_graphical_target_startup_systemd() {
	sudo cp -v $LOCAL_DIR/targetfiles/etc/systemd/system/weston.service $ROOTFS_DIR/etc/systemd/system/weston.service || fatalError "Failed to copy weston.service to the rootfs"
	sudo chroot $ROOTFS_DIR bash -c "systemctl enable weston.service" || fatalError "Failed to enable weston.service"
}

main() {
	### install packages
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

	### More adjustments after installation
	do_launch_weston_at_graphical_target_startup_systemd
	do_populate_etc_profiled_file
}


commonScriptPrologueLogRunAndEpilogue $@