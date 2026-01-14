enable_ethernet_via_dhcp_and_passwordless_telnet() {
	hardWarn "Enabling networking and telnet. Please connect via ethernet (assuming you want this feature...)"
	telnetd -l /bin/sh &
	/network/try-udhcpc.sh &
}

#
# Open virtual terminals (vts) on the system. This is useful for debugging or seeing what is going on if you have, e.g. HDMI or a monitor
# however, if you have DRM, you must have CONFIG_DRM_FBDEV_EMULATION enabled, which I personally dislike, given that
# a graphical user interface will either use Wayland or Android in most cases I work on.
# The rule of thumb is that if you see the Linux logo - you have this enabled
#
# If you use QEMU there is an invaluable trick to "move between the the vts" - you can use alt+<arrow> where <arrow is right or left,
# instead of struggling with your host and your keyboard, or having to use the QEMU monitor's sendkey command
#
open_vts() {
	# The extra vts are different from the console and the serial. Opening the serial here (if we just dumbly open getty) may result in
	# late display of other messages, so we will open it (and the main console) only right before the exec
	# (if we drop to ramdisk, if we don't we will let the rootfs handle it as it wishes)
	FIRSTVT=2 # dont set 1 here
	LASTVT=3
	if [ $FIRSTVT -gt 1 -a $LASTVT -ge $FIRSTVT ] ; then
		verbose "opening vts with shells from $$"
		for vt in $(seq $FIRSTVT $LASTVT ) ; do openvt -c $vt; done
	fi
}

#
# Open getty on the serial device (likely the console, so be careful with the kernel command line parameters, and know what you are doing)
#
open_serial_tty() {
	# see the comment on openMainVt - we assume it is the monitor/kbd and not the serial.
	# This is not good enough for the case hdmi is connected after we are running,  and if I have time I will figure out how to do that properly
	# (i.e. avoid the green screen)
	#
	# Also see importnat comments in the code before calling it (or before commenting it out)
	if [ -c $serial_dev ] ; then
		echo -e "\x1b[33mOpening getty on the serial device.\x1b[0m"
		getty -n 0 $serial_dev -l /bin/sh &
		verbose "opened vt from $$. serial /bin/sh runs on $!"
	else
		error "$serial_dev is not a character device file. Won't open getty on it"
	fi
}

#
# This could go into an emulator related BSP, but as this file is for debugging functionality, it's fine to keep it here
#
open_hvc_tty() {
	local hvc_dev=/dev/hvc0
	if [ -c $hvc_dev ] ; then
		echo -e "\x1b[33mOpening getty on the hvc.\x1b[0m"
		getty -n 0 $hvc_dev -l /bin/sh &
		verbose "opened vt from $$. hvc /bin/sh runs on $!"
	else
		error "$hvc_dev is not a character device file. Won't open getty on it"
	fi
}

openMainVtAndExecSh() {
	# we want to have the main vt on the init (assuming we work with screen and tty1!) so prioritze that.
	verbose "opening main vt from $$. Will exec upon change"
	# open the first vt only at the end. ensures shell runs on the first vt, although it doesn't really matter. do not create the vt - it was already created upon boot - just change to it
	if [ ! "$docker" = "true" ] ; then
		chvt 1
		exec $TTY_SHELL_JOB_CONTROL_PREFIX /bin/busybox sh
	else
		debug "exec shell in docker"
		warn "You may want to remove the previous fake stuff, to be friendly to your host's [or other containers'] kernel. You can do it with
		for i in \$(losetup -a | grep fakestuff | cut -d: -f1) ; do losetup -d \$i ; done
		"
		exec $TTY_SHELL_JOB_CONTROL_PREFIX /bin/busybox sh
	fi

}

#
# this organizes the activities to be done when we decide to fall back to shell, as it is quite tricky with the ttys. we sadly cannot easily open a tty here
# and then chroot as we would wish as the serial terminal (and only it) will not work well with debian (get stuck etc.). It's not a big deal and it does not affect anyone
# but the platform debuggers, but we do want to keep it
#
fallbackToShell() {
	openMainVtAndExecSh
}
#
#
#
stopAtShell() {
	info "You are left at the recovery shell. Press ^D or exit to continue the boot process (on your responsibility)"
	if [ ! "$docker" = "true" ] ; then
		chvt 1
	fi
	busybox /bin/sh
}

#
# This function is hardError + fatalError sound + falling back to shell
# it is added here and not in commonEnv.sh as it is a strict debugging mechanism, for rare cases, such as
# someone in pid 1 fatalError's, and instead of panicking, we want to give the developer a chance to debug
#
fatalError_do_fallback_to_shell() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[41m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
	bsp_hmi_fatal_failure
	# TODO: if pscgrd.debug.openvts is set to "all" or to "serial" - the next line will have to getty on the same device
	# 		which of course will make keyboard impossible to work with.
	#       Also, the next line will open a shell on tty0 (e.g. vt1) - if there is *no* serial device - and will just print otherwise,
	# 	    Unless FIRSTVT is 1.
	#		It is super not important as the recommendation is to not set pscgrd.debug.openvts at all, and it is documented here,
	# 	    as this is a debugging feature, which if you encounter or use, you will defintely meet the consequences described here.
	do_fallback_to_shell
}

###
# fallback and work from ramdisk
###
do_fallback_to_shell() {
	hardDebug "Will execute busybox shell now"
	call_if_exists bsp_debug_ttys
	call_if_exists type_debug_fb
	debug_cmdline > /dev/console
	debug_cmdline > /dev/tty0
	verbose "Enjoy your shell\n\n"
	fallbackToShell
}

open_tty_devices() {
	# This is a template - usually just don't open them. Too many things can go wrong, especially with DRM, or if you
	# set the console to be hvc, or in Debian and systemd... and emulators and non emulators may behave differently.
	# this is added to help you see the different behavior cases
	# All VT flows were heavily tested *not* on emulators. This change is new for emulators, so anyhow, careful, requires testing
	# But testing is learning! ( :-) )
	case "$OPEN_SERIAL_VT_EARLY" in
		all)
			open_serial_tty
			open_hvc_tty
			open_vts
			;;
		serial)
			info "Openning serial tty early in the boot process. This has negative effect on the terminal with debian rootfs"
			open_serial_tty
			;;
		hvc)
			# e.g. if you have virtio
			open_hvc_tty
			;;
		vts)
			open_vts
			;;
		*)
			error "Unknown OPEN_SERIAL_VT_EARLY value: $OPEN_SERIAL_VT_EARLY. Should be one of: all, serial, hvc, vts"
			;;
		esac
}

