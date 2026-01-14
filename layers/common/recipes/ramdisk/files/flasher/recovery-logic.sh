#
# Implementation of a recovery mechanism which relies on
# - having a tarball in a dedicated partition
# - extracting it to the OTA partition and setting the state
# - carrying out a reflashing as if it were an OTA
#
# We do it to illustrate mechanism reusing. Usually you will have the bootloader taking care of state keeping, and of presenting
# a way to the system to identify some key combination, or a previous command (e.g. from rich operating system) to go to recovery mode
#
# Note that while the design is solid, there are many things to consider when designing recovery images,
# and you can be sure that the PSCG knows how to build flawless recovery images!
# Note: given the note above, I will attempt to avoid writing further notes...
: ${RECOVERY_GOLDEN_IMAGE_MOUNT_POINT=/mnt/$partition_label_recovery_tarball}

#
# This is an auxilary function that mounts $1 onto $2 only if $2 is not already a mount point. Otherwise, it assumes that the mount is indeed the intended mount, so it is up to the developers to know what they are doing.
# Otherwise, if $2 is not empty, it will refuse to mount it. If it does not exist it will create it
#
# $1: LABEL to mount
# $2: designated mountpoint
mount_by_label_if_not_mounted() {
	local label target
	label=$1
	target=$2
	if ! mountpoint $target ; then
		if [ ! -d $target ] ; then
			mkdir -p $target || fatalError "Failed to create the $target directory"
		fi
		if [ ! "$(ls -A $target)" = "" ] ; then
			fatalError "Will not mount onto a non empty directory - $target"
		else
			mount LABEL=$label $target || fatalError "Failed to mount $label onto $target"
		fi
	else
		info "$target is already mounted: $(mount | grep $target)"
	fi
}

mount_recoverytarball_partition() {
	mount_by_label_if_not_mounted $partition_label_recovery_tarball $RECOVERY_GOLDEN_IMAGE_MOUNT_POINT
}

unmount_recoverytarball_partition() {
	umount $RECOVERY_GOLDEN_IMAGE_MOUNT_POINT || fatalError "Failed to unmount $RECOVERY_GOLDEN_IMAGE_MOUNT_POINT"
}

verify_recovery_tarball_digest() {
	recovery_tarball_actual_digest=$(eval "$cmd_calc_digest") || fatalError "Could not calculate $recovery_tarball_digest_type"
	if [ "$recovery_tarball_actual_digest" = "$recovery_tarball_expected_digest" ] ; then
		info "Recovery taball $recovery_tarball_digest_type match ($recovery_tarball_actual_digest)"
		return 0
	else
		error "$recovery_tarball_digest_type mismatch: expected=$recovery_tarball_expected_digest\nActual=$recovery_tarball_actual_digest"
		return 1
	fi
}

#
# It is a recovery image, so we assume that whoever prepares the image, knows very well what they are doing.
# If they don't, they would brick the device at usage.
# So we allow ourselves to exit with fatal errors or fallback to shell if the manifest is incorrect
#
init_recovery_file_variables() {
	local recovery_manifest=$RECOVERY_GOLDEN_IMAGE_MOUNT_POINT/installer.manifest
	dod_shell [ -f $recovery_manifest ]
	dod_shell [ -f $RECOVERY_GOLDEN_IMAGE_MOUNT_POINT/installer.digest ] # Not really used, but need to clean it up in other places in the project as well. TODO probably remove this
	recovery_tarball=$RECOVERY_GOLDEN_IMAGE_MOUNT_POINT/$(get_value_by_key_file $recovery_manifest original_blob_filename)
	recovery_tarball_expected_digest=$(get_value_by_key_file $recovery_manifest blob_digest)
	recovery_tarball_digest_type=$(get_value_by_key_file $recovery_manifest digest_type)
	case "$recovery_tarball_digest_type" in
		"sha256") cmd_calc_digest="sha256sum $recovery_tarball | cut -f1 -d' '" ;;
		"sha1") cmd_calc_digest="sha1sum $recovery_tarball | cut -f1 -d' '" ;;
		"sha512") cmd_calc_digest="sha512sum $recovery_tarball | cut -f1 -d' '" ;;
		"md5") cmd_calc_digest="md5sum $recovery_tarball | cut -f1 -d' '" ;;
		*) fatalError "Unsupported digest_type $recovery_tarball_digest_type"
	esac

	dod_shell [ -n "$recovery_tarball_expected_digest" ]
	dod_shell [ -f "$recovery_tarball" ]
}

#
# You can see this as the main recovery function assuming the recovery is given in a tarball
#
do_extract_recovery_tarball() (
	source_files_if_they_exist="/commonEnv.sh /flasher/ota/otaCommon.sh"	# sourced here to make it clear that this code could run independently of the rest of the ramdisk/initramfs/smallos!
	for f in $source_files_if_they_exist ; do
		if [ -f $f ] ; then
			source $f
		fi
	done
	mount_recoverytarball_partition # takes care of errors itself

	init_recovery_file_variables

	verify_recovery_tarball_digest || fatalError "Failed to verify recovery manifest" # we can save some seconds by not verifying this...
	set_state "recoveryUnpacking"
	cleanup_ota_extract

	if [ -f $RECOVERY_GOLDEN_IMAGE_MOUNT_POINT/installer.manifest ] ; then
		info "Setting the recovery installer manifest as the wip manifest"
		if [ ! -d "$OTA_STATE_WIP_DIR" ] ; then
			warn "$OTA_STATE_WIP_DIR does not exist. Seems like your previous state was not set up correctly. Creating it now, and trying to recover from that for you."
			dod_shell mkdir -p $OTA_STATE_WIP_DIR
		fi
		dod_shell cp $RECOVERY_GOLDEN_IMAGE_MOUNT_POINT/installer.manifest $NEW_WIP_MANIFEST_FILE
	else
		: # The current userspace flasher will want the manifest for its last update state, so if you don't have it
		: # you might just do an a-only scheme instead
	fi

	info "Extracting the recovery tarball..."
	# Note about tarfiles: busybox does not support sparse files and does not support (or need) --warning=no-timestamp
	# so to be portable, we may have a wasteful image, and if you find yourself implementing tarball extraction on a richer os image
	# you may run into messages such as "time is in the past..." if you don't have, e.g. an RTC or other clock in the device
	# The latter is safe in busybox, but do know that.
	tar  -C $OTA_EXTRACT_BASE_DIR -xvf $recovery_tarball || fatalError "Failed to extract $recovery_tarball onto $OTA_EXTRACT_BASE_DIR"
	set_state "recoveryUnpacked"

	unmount_recoverytarball_partition
	info "Done extracting the recovery tarball"
)

do_recovery_sequence() {
	local logTag=recovery
	hardInfo "Starting recovery sequence"
	if ! do_extract_recovery_tarball ; then
		info "Trying to revert the state"
		set_state "recoveryFailed"
		return 1
	else
		info "Setting status to the equivalent of OTA reflashing"
		set_state recoveryPendingReflash
	fi
}