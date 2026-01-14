: ${BSP_QEMU_SHOW_OFF_WITH_LIGHTS=true}

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
	:
}

bsp_hmi_software_flashing_start() {
	bsp_play_sound_from_file /assets/audio/${flashing_reason}.wav
	[ "$BSP_QEMU_SHOW_OFF_WITH_LIGHTS" = "true" ] || return
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
	bsp_play_sound_from_file /assets/audio/cheerful.wav
	[ "$BSP_QEMU_SHOW_OFF_WITH_LIGHTS" = "true" ] || return
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
	[ "$BSP_QEMU_SHOW_OFF_WITH_LIGHTS" = "true" ] || return
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
	bsp_play_sound_from_file /assets/audio/error.wav
}

bsp_hmi_fatal_failure() {
	[ "$BSP_QEMU_SHOW_OFF_WITH_LIGHTS" = "true" ] || return
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
	bsp_play_sound_from_file /assets/audio/fatalError.wav
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
	if [ "$docker" = "true" -o "$bsp"="qemu" ] ; then
		hardWarn "Will reboot upon enter key press - unless you take a stand!
		If you have things you dont want in the next boot,
		please shut down the target, modify what you want to modify, and then rerun the target
		"
		read
	fi
	stop_logging

	cd /
	umount -a
	if [ $(readlink -f $(which reboot)) = /bin/busybox ] ; then
		reboot -f
	else
		reboot
	fi
}