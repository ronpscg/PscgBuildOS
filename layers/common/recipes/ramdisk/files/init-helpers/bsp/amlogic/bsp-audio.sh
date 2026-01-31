# For explanations about the controls - see the end of this file

export BSP_AUDIO_HMI_EVENT_FROM_FILE=false
export DEFAULT_AUDIO_SAMPLE_RATE=44100
export DEFAULT_AUDIO_NUM_CHANNELS=2
export DEFAULT_AUDIO_DEVICE_NUMBER=0

bsp_init_audio_set_output_hdmi() {
	# Initialize controls for HMDI play
	tinymix set 13 'I2S'        # AIU HDMI CTRL SRC
	tinymix set 12 'I2S'        # AIU SPDIF SRC SEL
	tinymix set 14 'DISABLED'   # AIU ACODEC SRC (disable analog)

	export DEFAULT_AUDIO_SAMPLE_RATE=44100
}

bsp_init_audio_set_output_headphone_jack() {
	# Initialize controls for headphone jack
	tinymix set 13 'DISABLED'   # AIU HDMI CTRL SRC (disable HDMI)
	tinymix set 14 'I2S'        # AIU ACODEC SRC
	tinymix set 15 1            # AIU ACODEC OUT EN Switch
	tinymix set 2 1             # ACODEC Playback Switch
	tinymix set 3 255 255       # ACODEC Playback Volume

	export DEFAULT_AUDIO_SAMPLE_RATE=44100
}

bsp_init_audio_check_hdmi_audio_parameters() {
	[ "$(grep sad_count /proc/asound/card0/eld\#4  | tr -s '\t' | cut -f 2)" -gt "0" ]
}

bsp_init_audio_playback() {
	case "$AUDIO_OUTPUT_BACKEND" in
		hdmi|HDMI)
			bsp_init_audio_set_output_hdmi
			;;
		headphone_jack)
			bsp_init_audio_set_output_headphone_jack
			;;
		*)
			warn "Please provide a proper pscgrd.hw.audio_output_backend parmeter (your provided: $AUDIO_OUTPUT_BACKEND)"
			if  bsp_init_audio_check_hdmi_audio_parameters ; then
				info "Detected an HDMI monitor. Will route sound through it"
				bsp_init_audio_set_output_hdmi
			else
				info "routing audio through the audio jack"
				bsp_init_audio_set_output_headphone_jack
			fi
			# we presented a simple "default" detection above. this is not good enough for real scenarios, but if you really work
			# with audio, you will definitely not keep at at the tinyalsa level in an initramfs, so it is perfect for our purposes.
			# As an exercise, you can auto detect if a monitor is detected etc. , and pay attention to insertion and removal events of cables.
			# you can also do it for the analog jack
			;;
	esac
	
	bsp_audio_playback_server &
	BSP_AUDIO_PLAYBACK_SERVER_PID=$!
	
	if grep gx-sound-card  /proc/asound/cards ; then
		info "Sound card detected"
	else
		warn "Sound card not detected. Disabling audio functions"
		return
	fi

	rc=0
	: # could do other things here, but we will leave the default volumes etc. especially if HDMI is involve
	return $rc
}

bsp_init_audio_recording() {
	warn "audio recording has not been tested on this device. it may be tested later via the headphone jack, or you could provide a USB codec device"
	return 1
}

#---------- Some explanations go below -----------

# tinymix  controls explanation (can vary and has varied on big architectural changes)
# below is the output of # tinymix controls .
# you can get more information with # tinymix contents (e.g. if HDMI - it will tell you also a hex dump of the EDID etc...)
if false ; then
Number of controls: 18
ctl     type    num     name                                            device
0       INT     1       AIU ACODEC I2S Lane Select                      0
1       ENUM    1       ACODEC Playback Channel Mode                    0
2       BOOL    1       ACODEC Playback Switch                          0
3       INT     2       ACODEC Playback Volume                          0
4       ENUM    1       ACODEC Ramp Rate                                0
5       BOOL    1       ACODEC Volume Ramp Switch                       0
6       BOOL    1       ACODEC Mute Ramp Switch                         0
7       BOOL    1       ACODEC Unmute Ramp Switch                       0
8       INT     8       Playback Channel Map                            4
9       IEC958  1       IEC958 Playback Mask                            4
10      IEC958  1       IEC958 Playback Default                         4
11      BYTE    128     ELD                                             4
12      ENUM    1       AIU SPDIF SRC SEL                               0
13      ENUM    1       AIU HDMI CTRL SRC                               0
14      ENUM    1       AIU ACODEC SRC                                  0
15      BOOL    1       AIU ACODEC OUT EN Switch                        0
16      ENUM    1       ACODEC Right DAC Sel                            0
17      ENUM    1       ACODEC Left DAC Sel                             0

# Below are examples for disconnected vs connected set
# the important thing is sad_count. It should be at least 2. If it's 0 there are absolutely no device connected or identified
# cat /proc/asound/card0/eld\#4 udhcpc: broadcasting discover
monitor_name
connection_type         HDMI
eld_version             [0x0] reserved
edid_version            [0x0] no CEA EDID Timing Extension block present
manufacture_id          0x0
product_id              0x0
port_id                 0x0
support_hdcp            0
support_ai              0
audio_sync_delay        0
speakers                [0x0]
sad_count               0

# cat /proc/asound/card0/eld\#4 
monitor_name            Philips FTV
connection_type         HDMI
eld_version             [0x2] CEA-861D or below
edid_version            [0x3] CEA-861-B, C or D
manufacture_id          0xc41
product_id              0x0
port_id                 0x0
support_hdcp            0
support_ai              0
audio_sync_delay        0
speakers                [0x1] FL/FR
sad_count               2
sad0_coding_type        [0x1] LPCM
sad0_channels           2
sad0_rates              [0x6e0] 32000 44100 48000 88200 96000
sad0_bits               [0xe] 16 20 24
sad1_coding_type        [0x2] AC-3
sad1_channels           6
sad1_rates              [0xe0] 32000 44100 48000
sad1_max_bitrate        640000
fi