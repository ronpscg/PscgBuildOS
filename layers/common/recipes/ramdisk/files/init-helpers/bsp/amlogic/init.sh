
bsp_init_blockdev_variables() {	
	DEV_BLOCK_FOLDER=/dev 														# in Android it could be under /dev/block/ . In Linux this is the standard path
	EMMC_DEVICE=$DEV_BLOCK_FOLDER/${emmc_device:-mmcblk1} 						# cmdline: emmc_device
	REMOVABLE_MEDIA_DEVICE=$DEV_BLOCK_FOLDER/${removablemedia_device:-mmcblk0} 	# cmdline: removablemedia_device
	PARTITION_MARK="p"
}

#
# Avoid patching the kernel sources and set in userspace - it is said that the p281 (s905w) is an s905x - with a clock rate of 1.2GHz and not 1.5Ghz as the latter.
# The default causes bit-flipping, observable by impossible memory values - and would panic under load when using both the CPU and the GPU, so decrease the frequency.
#
bsp_amlogic_p281_frequency_dec() {
	# Actually using 1500000 has been observed to work, but the default of 1512000 does not.
	echo 1200000 > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
}

bsp_amlogic_init() {	
	bsp_amlogic_p281_frequency_dec # the sooner the better

	hardDebug "Hello from your favorite $bsp init script"

	# source audio early enough to allow indications
	bsp_audio_file=/init-helpers/bsp/$bsp/bsp-audio.sh
	more_files_to_source="$bsp_audio_file"

	for f in $more_files_to_source ; do
		if [ -e $f ] ; then
			source $f
		fi
	done

	bsp_init_audio_playback || error "Failed to initialize audio playback"
	bsp_init_audio_recording || error "Failed to initialize audio recording" # Recording (really not needed now, but let's do so anyway as it's nice to demonstrate)
}
