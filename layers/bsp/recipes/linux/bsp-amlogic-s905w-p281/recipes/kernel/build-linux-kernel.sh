# While we could provide our own prebuilt DTBs, and we could build DTSs also outside of the kernel directory
# there is a reasonably good support for the device in the kernel upstream, so we will use it
# However, one may want to modify the device tree, by either patching the kernel sources (we deliberately avoid patching in this project, for clarity!)
# adding another file to the source tree prior to building (which we also avoid at this point, for clarity and reproducibility), or just patching the resulted dtb,
# or building outside of the kernel directory
#
kernel__do_dtbs_install() {
	if [ ! "$config_kernel__do_dtbs" = "true" ] ; then
		warn "User opted out of installing dtbs"
		return
	fi

	for c in "$config_kernel__list_of_dtbs" ; do
		local destdir="${kernel__dtbs_install_workdir}/$(dirname $c)"
		do_or_die mkdir -p $destdir
		verbose_do_or_die cp $LINUX_BUILD_DIR/arch/$ARCH/boot/dts/$c $destdir
	done
}
