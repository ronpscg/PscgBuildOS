#
# This file has some common definitions that each bsp may or should override
#
bsp_wait_for_removable_media() {
	:
}

bsp_wait_for_removable_media_done() {
	:
}

bsp_play_sound_from_file() {
	:
}

bsp_record_sound_to_file() {
	:
}

bsp_stop_current_sound_playback() {
	pkill -9 tinyplay ||  true
}

bsp_stop_current_sound_recording() {
	pkill -9 tinycap || true
}

# This is useful in case someone wants to release a DRM lock, or do some indication before moving to the richos or starting a recovery shell etc.
bsp_stop_current_graphics_activities() {
	:
}

bsp_hmi_software_flashing_start() {
	bsp_hmi_event ${flashing_reason}
	[ "$BSP_SHOW_OFF_COLORFUL_LIGHT_BULBS_ON_CONSOLE" = "true" ] || return
	local COLORON="\x1b[5m"
	local COLOROFF="\x1b[0m"
	echo -e "\
$COLORON    _...._      $COLOROFF
$COLORON  .'      '.    $COLOROFF
$COLORON /          \   $COLOROFF
$COLORON |---~~~~---|   $COLOROFF
$COLORON  \        /    $COLOROFF
$COLORON  \`\      /\`     $COLOROFF
$COLORON    |    |      $COLOROFF
$COLORON    |____|      $COLOROFF
$COLORON     vvvv       $COLOROFF
	"
}

bsp_hmi_software_flashing_completed() {
	bsp_hmi_event flashing_completed
	[ "$BSP_SHOW_OFF_COLORFUL_LIGHT_BULBS_ON_CONSOLE" = "true" ] || return
	local COLORON="\x1b[32;5m"
	local COLOROFF="\x1b[0m"
	echo -e "\
$COLORON    _...._      $COLOROFF
$COLORON  .'      '.    $COLOROFF
$COLORON /          \   $COLOROFF
$COLORON |---~~~~---|   $COLOROFF
$COLORON  \        /    $COLOROFF
$COLORON  \`\      /\`     $COLOROFF
$COLORON    |    |      $COLOROFF
$COLORON    |____|      $COLOROFF
$COLORON     vvvv       $COLOROFF
	"
}

bsp_hmi_failure() {
	[ "$BSP_SHOW_OFF_COLORFUL_LIGHT_BULBS_ON_CONSOLE" = "true" ] || return
	local COLORON="\x1b[31m"
	local COLOROFF="\x1b[0m"
	echo -e "\
$COLORON    _...._      $COLOROFF
$COLORON  .'      '.    $COLOROFF
$COLORON /          \   $COLOROFF
$COLORON |---~~~~---|   $COLOROFF
$COLORON  \        /    $COLOROFF
$COLORON  \`\      /\`     $COLOROFF
$COLORON    |    |      $COLOROFF
$COLORON    |____|      $COLOROFF
$COLORON     vvvv       $COLOROFF
	"	
	bsp_hmi_event "error"
}

bsp_hmi_fatal_failure() {
	[ "$BSP_SHOW_OFF_COLORFUL_LIGHT_BULBS_ON_CONSOLE" = "true" ] || return
	local COLORON="\x1b[31;5m"
	local COLOROFF="\x1b[0m"
	echo -e "\
$COLORON    _...._      $COLOROFF
$COLORON  .'      '.    $COLOROFF
$COLORON /          \   $COLOROFF
$COLORON |---~~~~---|   $COLOROFF
$COLORON  \        /    $COLOROFF
$COLORON  \`\      /\`     $COLOROFF
$COLORON    |    |      $COLOROFF
$COLORON    |____|      $COLOROFF
$COLORON     vvvv       $COLOROFF
	"
	bsp_hmi_event "fatalError"
}

. /init-helpers/bsp/common/audio/pcm-audio-note-generator.sh

#
# Do some noticable things on specific events. Each BSP will select whether to implement the functions or not
# Some indications: playing sounds or a file, flashing leds, displaying some things on screen, etc.
# For some events, there are specific functions.
#
# The main reason this function was written was to allow a common and easy way to play back per event
# audio files, without specifying the file names or worrying about the sample rate. Providing the sample rate of
# every hardware can make the ramdisk grow significantly, so we provided what was supported by QEMU, and from this
# point and on, each BSP can select what to do, as a demonstration (including removing incompatible asset files before repackaging 
# the ramdisk at build time, and simply replacing the assets
# The default 
#
# $1 event
bsp_hmi_event() {
	local event=$1
	local filename=""
	case $1 in
		hardware_buttons_recovery|userspace_triggered_recovery)
			filename="${recovery}_recovery.wav"
			;;
		ota|recovery|installer|installer_a_only|installer_ab_copyoverotaextract|installer_ab_directlyfromremovablemedia)
			filename="${event}.wav"
			;;
		reflash_failed)
			filename="blue.wav"
			;;
		error|fatalError)
			filename="${event}.wav"
			;;
		flashing_completed)
			filename="cheerful.wav"
			;;
		*)
			warn "***Unknown event $1***"
			return
			;;
	esac

	# We only keep 16000Hz sample rate sampes - so it is not for every bsp.
	# Therefore, we will also allow some other simple mechanism to generate sounds
	if [ "$BSP_AUDIO_HMI_EVENT_FROM_FILE" = "true" ] ; then
		bsp_play_sound_from_file /assets/audio/$filename
	else
		# We can generate the "files" and keep them and play from file instead	
		# for now we will generate things as we go (and use very short sequences)
		bsp_play_sound_from_generated_on_the_fly_sequence $filename
	fi
}


#
# This is a generic sequence, that aims to prevent automatic rebooting in case here is a removable media
# Each BSP can specify its own sequence, and perhaps warn the user in this way or another.
# It can be used, for example, depending on the BSP properties (Audio, Graphics, etc.) to notify the user to
# remove the removable media, or to press a key to continue.
#
do_reboot_to_state() {
	local state
	if [ -n "$1" ] ; then
		state=$1
		set_state "$state"
	else
		state=$(get_state)
		verbose "Rebooting and keeping the latest state $state"
	fi

	sync
	warn "Will now reboot to state ($state)"	
	hardWarn "Will reboot upon enter key press - unless you take a stand!
	If you have things you dont want in the next boot,
	please shut down the target, modify what you want to modify, and then rerun the target
	"
	read
	
	stop_logging

	cd /
	umount -a
	if [ $(readlink -f $(which reboot)) = /bin/busybox ] ; then
		reboot -f
	else
		reboot
	fi
}