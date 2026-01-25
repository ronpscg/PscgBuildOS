source /init-helpers/bsp/virtual/bsp-functions.sh

BSP_AUDIO_PLAYBACK_SERVER_PID=""
BSP_AUDIO_PLAYBACK_SERVER_FIFO=/tmp/bsp_audio_playback_fifo
#
# An example of a trivial audio playback server
#
bsp_audio_playback_server() {
	local MAX_AUDIO_FILE_LENGTH_SEC=5 # for timeout. tinyalsa will not always exit on its own
	if [ -e $BSP_AUDIO_PLAYBACK_SERVER_FIFO ] ; then
		rm -f $BSP_AUDIO_PLAYBACK_SERVER_FIFO || warn "Failed to remove old fifo $BSP_AUDIO_PLAYBACK_SERVER_FIFO"
	fi
	mkfifo $BSP_AUDIO_PLAYBACK_SERVER_FIFO || fatalError "Failed to create fifo $BSP_AUDIO_PLAYBACK_SERVER_FIFO"

	info "Starting audio playback server with fifo $BSP_AUDIO_PLAYBACK_SERVER_FIFO"
	while true ; do
		read -r file < $BSP_AUDIO_PLAYBACK_SERVER_FIFO || break
		timeout $MAX_AUDIO_FILE_LENGTH_SEC tinyplay "$file" || warn "Failed to play sound from file $file"
	done
}

#
# $1: input file name
#
bsp_play_sound_from_file() {
	if [ ! -e $BSP_AUDIO_PLAYBACK_SERVER_FIFO ] ; then
		# hardError does not play a sound so we use it. It is very unlikely that this will happen.
		hardError "Audio server is not ready yet. Ignoring you request to play sound from file $1"
	fi
	# When playing sounds, if the device is busy - tinyalsa will rightfully fail to play another sound
	# So we enqueue the sound, in the background. If enqueing does not succeed, we ignore it.
	# We made for error, so we don't want the device to have multiple errors while playing and error.
	# Attention though: this has mostly been tested without enqueing, and just warning about failure.
	# If there are many consecutive failures, you may hear several sounds, and they will be delayed, so you could
	# replace this with just calling tinyplay and hoping for the best (in other word: you can comment out the next line:)
	#tinyplay $1 warn "Failed to play sound from file $1"

	# enqueue the sound to the fifo. do not wait on the fifo
	echo $1 > "$BSP_AUDIO_PLAYBACK_SERVER_FIFO" &
}
#
# $1 output file name (recommendation: to play trivially with tinyplay, save the file as .wav)
# $2 recording length [seconds]
#
bsp_record_sound_to_file() {
	# just a prepration function
	tinycap $1 -t $2 -c 2 -r 16000Hz -b 16 || warn "Failed to record $2 seconds of sound to file $1"
}

# This is useful in case of a playback or recording that is in progress (possibly a dangling overlapping sound) before we want to get to the richos or to a recovery shell
bsp_stop_current_audio_activities() {
	bsp_stop_current_sound_playback
	bsp_stop_current_sound_recording
}
