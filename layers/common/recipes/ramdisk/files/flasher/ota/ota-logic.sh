#!/bin/sh

inc_reflash_counter() {
	if [ ! -f $OTA_REFLASH_COUNTER_FILE ] ; then
		current_reflash_counter=1
	else
		current_reflash_counter=$(get_reflash_counter)
		current_reflash_counter=$((current_reflash_counter+1))
	fi
	echo $current_reflash_counter > $OTA_REFLASH_COUNTER_FILE
	if [ "$current_reflash_counter" -gt  "$MAX_REFLASH_COUNTER" ] ; then
		if [ "$(get_state)" = "pendingInstallerReflash" ] ; then
			hardError "Failed reflashing $current_reflash_counter times. You are running from an install media, so we are giving you the chance to continue"
			return
		fi
		do_reboot_full
	fi

}

get_reflash_counter() {
	current_reflash_counter=$(cat $OTA_REFLASH_COUNTER_FILE)
	echo $current_reflash_counter
}

# Reboot the system completely. On the current implementation, it means we will reboot to ramdisk, and if things are OK/recoverable, to userspace in bank A
# If there is no bank B and verification, this means the device is done upon failure
do_reboot_full() {
	info "Starting reboot sequence"
	cd /
	sync
	umount -a
	warn "System is going for an immediate reboot..."
	reboot -f
}

check_if_reflash_is_needed() {
	state=$(get_state)
	if [ "$state" = "awaitingReboot" ] ; then
		# Note the text. This is closely related to the userspace logic
		info "Reflash was requested, but there was reboot in userspace before setting the state to pendingReflash. Setting it to pendingReflash"
		set_state "pendingReflash"
	fi

	state=$(get_state) # important to always call get_state. it does not set directly the state variable
	case "$state" in
		"pendingReflash"|"pendingInstallerReflash"|"recoveryPendingReflash")
			inc_reflash_counter
			info "Reflash requested. Will do the OTA sequence for $state. This is reflash attempt #$current_reflash_counter"
			return 0
			;;
		"reflashing")
			warn "Reflashing in state $state. This usually indicates a failing reflashing attempt. Number of previous failures: $current_reflash_counter"
			inc_reflash_counter # Note: for now this also does the reboot to system logic. maybe it will be modified
			return 0
			;;
		"reflashFailed")
			warn "Reflashing in state $state. This usually indicates a failing reflashing attempt. Number of previous failures: $current_reflash_counter"
			inc_reflash_counter # Note: for now this also does the reboot to system logic. maybe it will be modified
			return 0
			;;
		*)
			return 1
			;;
	esac
}

check_if_verification_is_needed() {
	# we want to verify immediately after reflashing, without rebooting. so if we even reach the verification function, it means there was a reboot before verification,
	# and we consider this a failure
	state=$(get_state)
	if [ "$state" = "pendingReflashVerification" ] ; then
		warn "Verifying reflashing in state $state. This usually indicates a failing reflash verification attempt. Number of previous failures: $current_reflash_counter"
		inc_reflash_counter
	else
		return 1
	fi
}

#
# This is meant to support system A/B update
#
# function side-effects (outputs):
# next_boot_pn=${PARTITION_MARK}<int>
# next_system_pn=${PARTITION_MARK}<int>
# Examples for ${PARTITION_MARK}<int>: p1 (for emmc0p1) 5 (for sda5 or vda5) etc.
#
decide_next_partitions_to_flash_to() {

	# Note: this is reference code. on OTA it is absolutely not acceptable to not be able to do OTA and then you'll have to reboot to recovery if you somehow put a ramdisk that is not workable"
	SYSTEMA_PN=${PARTITION_MARK}5
	SYSTEMB_PN=${PARTITION_MARK}12
	BOOTA_PN=${PARTITION_MARK}1
	BOOTB_PN=${PARTITION_MARK}2

	# TODO: convention is different. my recommendation is to actually have OTA has a separate project, use the same commonEnv.sh, and use the scripts (must make it ash-able and not just bashable - and last time I worked on it it was like this)
	# TODO seems like a copy paste from init. revise and refactor both together...
	cbp_device=$(cat $LAST_VALID_ACTIVE_BOOT_PARTITION_FILE)   # current boot partition device
	csp_device=$(cat $LAST_VALID_ACTIVE_SYSTEM_PARTITION_FILE) # current system partition device

	if [ -z $cbp_device ] ; then
		warn "No previous boot partition - will use defaults."
		next_boot_pn=$BOOTA_PN
		# Note: In general, it is preferable to not A/B the boot partition on the first versions, I intended to do it only after finalization of factory and environment
		# So the boot flow is not implemented in this reference now
	else
		debug "Previous active boot partition is $cbp_device"
		# Read the following message carefully if you want to do A/B on the boot partition. In general, you shouldn't. We can decide, e.g. to extend the recovery with "recover only ramdisk, recover only kernel, recover only... but that would be too much work for the time allocated for this task (which is nothing, and Ron Munitz was just extremely kind to give you a working template of a solution."
		hardVerbose "If you are looking into this, understand that in order to make the u-boot life easier, we keep looking sequentially for the boot partition (with the config scripts etc.). So what you would want to do in order to implement an A/B sequence is simply to put the next stuff in the new partition, relabel (actually only for some debugging tricks, Linux should not care about the boot partition at all), and remove the u-boot scripts from the old (let's say first) one."
		next_boot_pn=$BOOTA_PN # this is intentional, see previous log and message (last two lines. Yes, I am very explicit for a reason!"
	fi

	if [ -z $csp_device ] ; then
		warn "No previous system partition - will use defaults."
		next_system_pn=$SYSTEMA_PN
		# Note: In general, it is preferable to not A/B the boot partition on the first versions, I intended to do it only after finalization of factory and environment
	else
		debug "Previous active system partition is $csp_device"
		# NOTE that a refactoring would likely be much better. as this is reference I am not doing it yet, and referring directly to some things. will refer to other things later"
		if [ "$csp_device" = "${EMMC_DEVICE}${SYSTEMA_PN}" ] ; then
			next_system_pn=${SYSTEMB_PN}
		elif [ "$csp_device" = "${EMMC_DEVICE}${SYSTEMB_PN}" ] ; then
			next_system_pn=${SYSTEMA_PN}
		else
			fatalError "Flashing an A/B sequence from an unsupported partition $csp_device. If you work on this code, instead of this you want to add your own recovery logic"
		fi
	fi

	set_next_boot_partition "${EMMC_DEVICE}${next_boot_pn}"
	set_next_system_partition "${EMMC_DEVICE}${next_system_pn}"

	hardDebug "This is your prospective update scenario: $csp_device --> ${next_system_pn} ; $cbp_device --> ${next_boot_pn} "
}

set_reflash_reason() {
	flashing_reason=ota
	state=$(get_state)
	case "$state" in
		pendingInstallerReflash)
			flashing_reason=installer_ab_${INSTALLER_MEDIA_INSTALLER_AB_STRATEGY}
			;;
		recoveryPendingReflash)
			flashing_reason=recovery
			;;
		*)
			:
			;;
	esac
}

do_reflash_from_ota_extract_or_installer_partition() {
	info "Flashing the files..."
	verbose "Determining the next partition to flash to..."

	# The next line will decide the partitions for the next flash. Note the (intended) side effects inside the function
	# we export them deliberately, as we want, at the first phase, to have that logic handled in the flasher script (less changes). this should be refactored
	decide_next_partitions_to_flash_to || fatalError "Failed to decide partitions. The system may not be ready for A/B updates yet"

	export next_boot_pn next_system_pn # exporting the variables only for the subshell opened in the next line
	if  (
			SRC_INSTALL_PARTITION_MOUNT_POINT=$(get_wip_extract_working_dir)
			set_reflash_reason
			target_boot_partition=${EMMC_DEVICE}${next_boot_pn}
			target_system_partition=${EMMC_DEVICE}${next_system_pn}
			target_boot_label=BOOT_EMMC # careful - this means no A/B on boot
			target_system_label=$OTA_TESTED_CANDIDATE_SYSTEM_PARTITION_LABEL	# marks this is a canididate. Label must be less than 16 bytes, this particular example is 15

			# TODO: these were in main_common_installer_ota_flasher - look at them again if/when we do ota
			PRINTVARS="next_boot_pn next_system_pn"
			debug "$0 pre-exported var debug:\n$(echo_vars $PRINTVARS)"

			main_common_installer_ota_flasher
	) ; then
		info "Reflashed successfully"
		set_state "pendingReflashVerification"
		do_reflash_verification
	else
		error "Reflash did not succeed"
		set_state "reflashFailed"
		bsp_play_sound_from_file /assets/audio/blue.wav # temporary we don't really want to do those sounds, a fatal error is good enough
	fi
}

#
# Checks if init_ramfs_exists in $1. returns 0 if so, and 1 otherwise,
# $1: the directory to check for initramfs files
# Side effect: returns also a global variable INITRAMFS_FILE_SUFFIX to the first initramfs found
#
# It is the responsibility of the caller to clear INITRAMFS_FILE_SUFFIX after using the results of the function, to avoid
# other code from accidently using it (but it's OK if they don't)
#
initramfs_exists() {
	local types=".cpio .cpio.gz .cpio.xz .cpio.bz2"
	local tmpdir=$1
	for t in $types ; do
		if [ -f $tmpdir/initramfs$t ] ; then
			INITRAMFS_FILE_SUFFIX=$t
			return 0
		fi
	done
	INITRAMFS_FILE_SUFFIX=""
	return 1
}

#
# Unpacks initramfs to the current working directory
# $1 ramdisk file to unpack
#
unpack_initramfs() {
	ramdiskfile=$1
	case "$INITRAMFS_FILE_SUFFIX" in
		".cpio.gz")
			gunzip -c $initramfsfile | cpio -id
			;;
		".cpio.xz")
			xzcat $initramfsfile | cpio -id
			;;
		".cpio.bz2")
			bunzip2 -c $initramfsfile | cpio -id
			;;
		".cpio")
			cpio -id < $initramfsfile
			;;
		*)
			error "Unknown initramfs file suffix: $INITRAMFS_FILE_SUFFIX"
			return 1
			;;
	esac
}

#
# This is an helper function that acknowledges the different type of initramfs.
# $1: the directory to check for initramfs files
#
do_verify_initramfs() {
	# This is temporary just to run something and check something while we are at it.
	# real OTA will unpack some verify script in them
	# we should just have a signed manifest and check that the boot files match the manifest

	local tmpdir=$1
	local suffix=$INITRAMFS_FILE_SUFFIX
	local initramfsfile=$tmpdir/initramfs$suffix
	local workdir=/tmp/verifyinitramfs # you must have enough memory to work here. BRB
	if  (	rm -rf $workdir &&
			mkdir $workdir &&
			cd $workdir &&
			( unpack_initramfs ) &&
			ls $workdir &&
			chroot $workdir /bin/sh -c "grep VERSION /etc/thepscgos-release" &&
			rm -rf $workdir
	) ; then
		hardInfo "initramfs unpacking test: success!"
	else
			umount $tmpdir
			rmdir $tmpdir
			errorExitScope "Failed to verify the boot partition using a simple heuristic"
	fi
}

# Should probably be done in another file as an easier migration template, but then we need to add more sources etc. and I don't feel like doing it at the moment
do_verify_boot_partition() (
	local next_boot_partition=$(get_next_boot_partition)
	verbose "Verifying boot partition $next_boot_partition"
	local tmpdir=$(mktemp -dt -p /tmp verbootworkdir-XXXXXXX) || errorExitScope "Failed to create directory"
	mount -o ro $next_boot_partition $tmpdir || errorExitScope "Failed to mount $next_boot_partition to $tmpdir"
	if [ -f $tmpdir/verifyScript ] ; then
		if ( cd $tmpdir && ./verifyScript ) ; then
			hardInfo "boot partition verifyScript test: success!"
		else
			umount $tmpdir
			rmdir $tmpdir
			errorExitScope "Failed to verify boot partition using verifyScript"
		fi
	elif initramfs_exists $tmpdir ; then
		do_verify_initramfs $tmpdir
	else
		warn "No boot verification method has been devised, you may want to add some"
		# e.g if you have an initramfs with a u-boot header skip 64 and then unpac ramdisk etc...
		# won't get into implementing more of those now
	fi
	# no need to check those, if we fail on cleanup we don't care as long as it is a ro system
	umount $tmpdir
	rmdir $tmpdir
)


# Should probably be done in another file as an easier migration template, but then we need to add more sources etc. and I don't feel like doing it at the moment
do_verify_system_partition() (
	local next_system_partition=$(get_next_system_partition)
	verbose "Verifying system partition $next_system_partition"
	tmpdir=$(mktemp -dt -p /tmp versystemworkdir-XXXXXXX) || errorExitScope "Failed to create directory"
	mount -o ro $next_system_partition $tmpdir || errorExitScope "Failed to mount $next_system_partition to $tmpdir"
	if [ -f $tmpdir/verifyScript ] ; then # well, if it's there, I would not run it as is
		(chroot $tmpdir /verifyScript) || { umount $tmpdir ; rmdir $tmpdir ; errorExitScope "Failed to verify system partition using verifyScript"; }
	else
		chroot $tmpdir sh -c "cat /etc/thepscgos-release" >& /dev/null || { umount $tmpdir ; rmdir $tmpdir ; errorExitScope "Failed to verify system partition using a simple heuristic"; }
		# we can add all kinds of other checks
	fi
	# no need to check those, if we fail on cleanup we don't care as long as it is a ro system
	umount $tmpdir
	rmdir $tmpdir
)

do_reflash_verification() (
	info "Verifying the reflashing... This will require much thought/discussion. The first version will just boot the system and assume it works"

	warn "Going for the trivial verification for the non A/B thing. if this doesn't work, you are on your own"
	# TODO: manifests for files/partitions/signed digests, etc.
	# TODO: chroot, mount, check some things, etc. the code below is a somewhat naive recommendation

	# TODO: tell somewhere else what has actually been flashed, and then verify only what has been flashed
	should_verify_boot_partition=true
	should_verify_system_partition=true
	if [ "$config_imager__allow_missing_system_installation" = "true" ] ; then
		warn "$FUNCNAME:$LINENO Skipping system partition verification"
		should_verify_system_partition=false
	fi

	if [ "$should_verify_boot_partition" = "true" ] ; then
		do_verify_boot_partition || hardErrorExitScope "Failed to verify system partition"
		info "boot partition verified (not reliable!)"
	fi

	if [ "$should_verify_system_partition" = "true" ] ; then
		do_verify_system_partition || hardErrorExitScope "Failed to verify boot partition"
		info "system partition verified(not reliable!)"
	fi
	set_state "reflashOK"
	return 0
)

#
# Runs the common code that utilizes the state partitions to decide whether flashing is required
# returns 0 if the caller should proceed (in our design, with the rootfs activities, whether
# on the existing system, or on a newly flashed system by product of this function operation
# and another value upon an error, allowing the caller to decide what to do upon failure.
#
# The function is meant to be run in a subshell, as some macros call exit to manage state
#
main_ota_logic() {
	. /commonEnv.sh
	. /flasher/ota/otaCommon.sh
	source /flasher/common-installer-ota-flasher.sh

	init_ota_directories # TODO: will need to unify that
	redirect_logs_to_ota_extract_partition

	if [ ! -f "$OTA_STATE_FILE" ] ; then
		warn "No ota state file. ota logic is ignored"
		exit 0
	fi

	# TODO If the source directory is an installer / a live media, we want to run other commands
	debug_run_commands_from_filesystem $OTA_EXTRACT_BASE_DIR || error "ota-logic($OTA_EXTRACT_BASE_DIR) failed to debug_run_commands_from_filesystem $?"  # TODO: only if a command line allows that, but now everything is hacky as there is no development time quota for that (May 2022)

	if check_if_reflash_is_needed  ; then
		info "Reflash requested"
		do_reflash_from_ota_extract_or_installer_partition
		if [ "$?" = "0" ] ; then
			# A user openning a "stopatramdisk" shell and having an error there, can lead to a 0 return code here, and still failing to flash
			# So this message might be confusing, and perhaps the state should be checked anyway. Flashing is very subtle, so I am just leaving the message
			# I do prefer that upon a failing reflashing, the user will return to the richos and not open a debug shell. If this file exits with 1
			# a debug shell will be opened. If it exits with 0, the main system (a.k.a richos) will proceed to boot
			info "Flashing and flashing verficiation seems to have succeeded. If all is good we can now switch labels (but as I said \"below\" the flashing script takes care of it"
		else
			error "Failed to reflash"
			exit 1
		fi

	elif check_if_verification_is_needed ; then
		info "Revisiting reflash verficiation"
		do_reflash_verification
		if [ "$?" = "0" ] ; then
			info "Verification seems to have succeeded. If all is good we can now switch labels (but perhaps we will do it from the other system). For now the flashing script shall take care of it"
		else
			error "Failed to verify the latest reflashing. It is likely this would lead to a continuous state of error"
			bsp_play_sound_from_file /assets/audio/blue.wav # temporary we don't really want to do those sounds, a fatal error is good enough
			exit 2
		fi
	fi


	state=$(get_state)
	case "$state" in
		"idle"|"downloading"|"downloaded"|"verifying"|"verified"|"unpacking"|"unpacked"|"testingReflashedImages"|"otaCompletedSuccessfully"|"livepatchCompletedSuccessfully")
			info "ota state is $state. Proceeding with normal boot sequence"
			;;
		"awaitingReboot")
			warn "ota state is $state. Proceeding with normal boot sequence (we are not supposed to be here)"
			;;
		"pendingReflash" | "reflashing" | "pendingReflashVerification")
			set_state "reflashFailed"
			;;
		"reflashOK")
			info "Reflash verification in ramdisk seems to be OK"
			;;
		*)
			warn "OTA: Won't do anything in $state. Instead, will reboot to main system."
			;;
	esac

	warn "OTA: Won't do anything in $state. Instead, will proceed to the main system." # or whatever else /init would like to do after running the OTA logic
	# proceed with regular boot
	exit 0 # we may want to specify different error values for some states, to force keeping the system in ramdisk recovery
}