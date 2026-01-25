source /init-helpers/bsp/virtual/bsp-functions.sh

bsp_additional_parse_cmdline() {
	for arg in $(cat $cmdline_file); do
		case $arg in
			forward_pulseaudio=*)
				docker_forward_pulseaudio=${arg#*=} # this could be relevant also for an emulator, at least in MacOS
				debug docker_forward_pulseaudio=$docker_forward_pulseaudio
				export docker_forward_pulseaudio
				;;
			docker_use_bindmount_ota_partitions=*)
				docker_use_bindmount_ota_partitions=${arg#*=}
				debug docker_use_bindmount_ota_partitions=$docker_use_bindmount_ota_partitions
				export docker_use_bindmount_ota_partitions
				;;
			*)
			# other arguments have been processed before calling this function
			# the only reason we traverse a loop is that this function has to be called after
			# the bsp has been identified, which is done by parsing the cmdline in the first place
			;;
		esac
	done
}