# Set global variables as these are used indirectly by commonEnv (for playing sounds)
# and it sources this file and sets some things prior to calling any function
export BSP_AUDIO_HMI_EVENT_FROM_FILE=true
export DEFAULT_AUDIO_SAMPLE_RATE=16000
export DEFAULT_AUDIO_NUM_CHANNELS=2
export DEFAULT_AUDIO_DEVICE_NUMBER=0

bsp_init_blockdev_variables() {
	DEV_BLOCK_FOLDER=/dev 														# TODO: if we still want to support android partitioning, do it by the kernel version
	EMMC_DEVICE=$DEV_BLOCK_FOLDER/$emmc_device 									# cmdline: emmc_device
	REMOVABLE_MEDIA_DEVICE=$DEV_BLOCK_FOLDER/$removablemedia_device 			# cmdline: removablemedia_device
	PARTITION_MARK=""															# no partition mark for the emulator
}

bsp_init_audio_playback() {
	bsp_audio_playback_server &
	BSP_AUDIO_PLAYBACK_SERVER_PID=$!

	if grep -q virtio-snd  /proc/asound/card0/pcm0p/info ; then
		verbose "virtio-snd deteted. won't configure audio playback, as as per the time of writing, it has no controls, and we won't to avoid an unnecessary tinymix error"
		return
	fi

	rc=0
	tinymix set 'Master Playback Switch' 1 || rc=1
	tinymix set 'Master Playback Volume' 50 || rc=1

	return $rc
}

bsp_init_audio_recording() {
	if grep -q virtio-snd  /proc/asound/card0/pcm0c/info ; then
		verbose "virtio-snd deteted. won't configure audio recording, as as per the time of writing, it has no controls, and we won't to avoid an unnecessary tinymix error"
		return
	fi

	rc=0
	tinymix set 'Capture Switch' 1 || rc=1 # won't consider the error mes
	tinymix set 'Capture Volume' 50 || rc=1
	return $rc
}

bsp_qemu_init() {
	hardDebug "Hello from your favorite $bsp init script"

	bsp_init_audio_playback || error "Failed to initialize audio playback"
	bsp_init_audio_recording || error "Failed to initialize audio recording" # Recording (really not needed now, but let's do so anyway as it's nice to demonstrate)
}