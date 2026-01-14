# source this file
#
# Definitions of developer related code that can completely modify the init sequence.
# This includes sourcing a configuration file, executing an alternative (early) init code, setting
# the environment for docker with fake devices (whhich could be done also on real devices, 
# but there is no real reason to do so) etc.
#
check_for_hacking_configurations() {
	EARLY_CONFIG_FILE=/config.env
	if [ -f $EARLY_CONFIG_FILE ] ; then
		echo "Sourcing $EARLY_CONFIG_FILE ]. Do not do something like this if you don't want to handle the security consequences"
		source $EARLY_CONFIG_FILE ]
	fi	
	
	if check_for_docker ; then		
		export TTY_SHELL_JOB_CONTROL_PREFIX=""
	else
		export TTY_SHELL_JOB_CONTROL_PREFIX="setsid cttyhack"
	fi
}


#
# Variable definitions that must be done before anything else, to account for cases where you cannot
# control the kernel command line (i.e. docker or other containers, which we will address all as docker for the time being)
# This checks for a docker instance on MacOS or Microsoft Windows.
# It demonstrates some reliable heuristics (e.g. checking kernel versions)
#
# 
#
# When using Docker, we can just modify the entry point/environment variables.
# I will do it, but for the sake of having a common reference in the training, you should expect most testing under Linux (travelling, and don't, have
# another neither Windows or MacOS with me at the moment. Can test the other platforms at some later time if you want
#
# We set the block devices for a removable media and an "EMMC", supporting custom paths, and supporting some Android and DT shenanigans (in some versions)
# Since this ramdisk will be used both for emulators, containers, and real devices, we start by creating an abstractions for all
# Rationale: 
#	- serial console interfaces (although one could just use /dev/console/ see note below though)
#	- /dev/mmcblk0p...  or /dev/sda... or /dev/hda/... or /dev/vda...  or maybe even just some files to be used as a loopback device...
#
# If we have control of the kernel cmdline, we can decide almost everything from there. But if we don't - we need to figure it out. This wrapper function
# takes care of it
#
# Note that this can be run without anything mounted (we can test the existence of files and run uname because they use system calls which are properly configured by busybox)

#
# Checks for indications that we are running inside docker
# returns 0 if we do, and 1 otherwise
#
check_for_docker() {	
	if [[ $(uname -r) =~ linuxkit ]] || [[ $(uname -r) =~ microsoft ]] ; then 
		echo "You are running under docker or something like it. This is a (very) educated guess."
		export docker=true
	fi

	if [ -e /.dockerenv ] ; then 
		echo "You are running under docker and a /.dockerenv exists"
		export docker=true
	fi

	if [ -n "$DOCKERENV" ] ; then
		echo "You are running under docker and specified it explicitly"
		export docker=true
	fi

	if [ "$docker" = "true" ] ; then
		wip_after_check_for_docker
		return 0
	else
		export docker=false
		return 1
	fi
}

wip_after_check_for_docker() {
	serial_dev=/dev/null
	cmdline_file=/fakestuff/cmdline	# I gave a minor task to some of the team to replace linuxkit kernel/and control the cmdline, but it has not been completed yet. So we just set the cmdline in a file for this

	dod_shell [ -e $cmdline_file ]
	# we could just do if/else and then  fallbackToShell or do_fallback_to_shell. The latter also prints the command line, and we don't have it yet so it's not a good candidate for error displaying at this phase
		
			
	DEV_BLOCK_FOLDER=/dev # Although no one needs it here
	PARTITION_MARK="p"
	# EMMC_DEVICE will be decided later, after basic mounts etc
}
