#
# play_note() was made instead of re-recording or resampling the asset files, that were tailored
# for QEMU PCM devices. It enables a generic way to generate some "meaningful" sounds,
# allowing the user to only specify its default DEFAULT_AUDIO_SAMPLE_RATE (as it is a critical element
# for every hardware, and without using ALSA software re-encoding abilities, which tinyalsa does not,
# different hardware will not work with different sample rates)
#
# Since some devices' hardware do not support such low sample rates, we create something
# that can be audible and seperable, instead of going through the bother of providing more files
# and increasing the size of the initramfs
#
# Several methods may be implemented here, to be a bit more plesant (less robotic).
# One can take the extra steps, add harmonics and make things sound more natural
#

#
# Sharp and to the point example:
# $1 note   - lower case, letter note marking, uses s for #  (e.g.   D# -->  ds  )
# $2 octave (default: 4). Each octave has 12 notes and semi notes (i.e..: A, A#, B, C, C#, D, D#, E, F, F#, G, G#)
#						  and yes, when I think about it it's weird to see only sharps and not flats (e.g. Ab, Eb,... :-) )
# $3 duration (default: 200ms)
play_note() {	
    # Calculation: distance from A ("La")
	# s: semi tone (e.g. cs is C# ("Do Diez/Sharp"))	
    case "$1" in
        c)  n=-9 ;; cs) n=-8 ;; d)  n=-7 ;; ds) n=-6 ;;
        e)  n=-5 ;; f)  n=-4 ;; fs) n=-3 ;; g)  n=-2 ;;
        gs) n=-1 ;; a)  n=0  ;; as) n=1  ;; b)  n=2  ;;
        *) return 1 ;;
    esac
    
    octave=${2:-4}
    duration=${3:-0.2}
	rate=${4:-$DEFAULT_AUDIO_SAMPLE_RATE}
	channels=${5:-$DEFAULT_AUDIO_NUM_CHANNELS}
	device=${6:-$DEFAULT_AUDIO_DEVICE_NUMBER}
    n=$(( n + (octave - 4) * 12 ))
    
    # Calculation: Samples = Rate * Duration. Bytes = Samples * 2 (Stereo) * 2 (if 16-bit, but we use 1-byte char)
    # For simplicity with %c%c, bytes = Rate * Duration * 2    
	bytes=$(awk -v d="$duration" -v r="$rate" 'BEGIN {print int(r * d * 2)}')


    # Note generation and playing . head is being used to ensure the pipe is not hanging
 	awk -v n="$n" -v d="$duration" -v r="$rate" 'BEGIN {
        f = 440 * (2 ^ (n/12));
        limit = r * d;
        for(i=0; i<limit; i++) {
            # Frequency is now relative to the variable sample rate
            s = 127 + 127 * sin(i * 6.283185 * f / r);
            printf "%c%c", s, s
        }
    }' | head -c "$bytes" | tinyplay - -r "$rate" -c $channels -D $device
}

#
# A bit more plaesant example
# $1 note   - lower case, letter note marking, uses s for #  (e.g.   D# -->  ds  )
# $2 octave (default: 4). Each octave has 12 notes and semi notes (i.e..: A, A#, B, C, C#, D, D#, E, F, F#, G, G#)
#						  and yes, when I think about it it's weird to see only sharps and not flats (e.g. Ab, Eb,... :-) )
# $3 duration (default: 200ms)
play_note_impl() {
    case "$1" in
        c)  n=-9 ;; cs) n=-8 ;; d)  n=-7 ;; ds) n=-6 ;;
        e)  n=-5 ;; f)  n=-4 ;; fs) n=-3 ;; g)  n=-2 ;;
        gs) n=-1 ;; a)  n=0  ;; as) n=1  ;; b)  n=2  ;;
        *) return 1 ;;
    esac
    
    octave=${2:-4}
    duration=${3:-0.2}
	rate=${4:-$DEFAULT_AUDIO_SAMPLE_RATE}
	channels=${5:-$DEFAULT_AUDIO_NUM_CHANNELS}
	device=${6:-$DEFAULT_AUDIO_DEVICE_NUMBER}

    n=$(( n + (octave - 4) * 12 ))
    bytes=$(awk -v d="$duration" -v r="$rate" 'BEGIN {print int(r * d * 2)}')

    awk -v n="$n" -v d="$duration" -v r="$rate" 'BEGIN {
        f = 440 * (2 ^ (n/12));
        limit = r * d;
        for(i=0; i<limit; i++) {
            # Decay factor: goes from 1.0 down to 0.0 over the duration
            decay = (limit - i) / limit;
            # Sine wave with volume envelope
            s = 127 + (127 * decay * sin(i * 6.283185 * f / r));
            printf "%c%c", s, s
        }
    }' | head -c "$bytes" | tinyplay - -r "$rate" -c $channels -D $device
}

# 
# A wrapper that aims to wait for some notes. Audio playing is not trivial, requires buffer synchronization
# and tinyalsa, to be gentle, is not happily willing to take care of (any)thing for you
# with tinyalsa and PCM it is very easy to get things stuck in buffers
# so we opportunisticly just kill it whenever we can
# 
play_note() {
	if pgrep tinyplay ; then
		sleep 0.2
		bsp_stop_current_sound_playback
		sleep 0.2
	fi
	play_note_impl $@
}

#
# made to easily change a delay to NOP for this hacky tinyalsa playing
#
artificial_delay_for_audio_playing() {
	return	
	sleep $@
}

#
# Generate some tunes with very basic PCM logic (a couple of notes on a couple of octaves)
#
bsp_play_sound_from_generated_on_the_fly_sequence() (
	# Note: we introduce "sleeps" just out of being lazy as it is an example.
	# The QEMU bsp has an example of a "sound server" that queues requests.
	# If you just play sounds in the foreground - you may jam your system, while it waits for buffer
	# If you just play sounds in the background - you may have the system playing them too quickly and having the PCM device unavailable so most will not play	
	local filename="$1"
	case $filename in
		hardware_buttons_recovery.wav|userspace_triggered_recovery.wav)
			(play_note c 4 0.15; play_note g 4 0.3) &
			artificial_delay_for_audio_playing 1			
			;;
		ota.wav|recovery.wav|installer.wav|installer_a_only.wav|installer_ab_copyoverotaextract.wav|installer_ab_directlyfromremovablemedia.wav)
		 	( for i in $(seq 1 3); do play_note a 4 0.5; done ) &
			artificial_delay_for_audio_playing 2
			;;
		blue.wav)
			( play_note d 4 0.4  ; play_note cs 4 0.4 ;  play_note c 4 0.7 ) &
			artificial_delay_for_audio_playing 2
			;;			
		error.wav)
			d1=0.15 ; d2=0.6;
			( play_note c 3 0.1; play_note c 2 0.4 ) &
			artificial_delay_for_audio_playing 0.5
			;;
		fatalError.wav)
			( for i in $(seq 1 3 ); do play_note fs 5 0.05 ; play_note c 5 0.05 ; done ; play_note c 4 0.5 ) &
			artificial_delay_for_audio_playing 2
            ;;
		cheerful.wav)
			d1=0.15 ; d2=0.6;
			( play_note c 4 $d1  ; play_note d 4 $d1; play_note e 4 $d1; play_note f 4 $d1 ; play_note g 4 $d1 ; play_note a 4 $d1 ; play_note b 4 $d1 ; play_note c 5 $d2 ) &
			artificial_delay_for_audio_playing 2
			;;
		*)
			warn "***Unknown event $1***"
			return
			;;
	esac
)