#!/bin/bash
#
# TODO: hardcoding for now - this must be done before repacking the ramdisk assuming the flasher (partitioner) is in the ramdisk
# 	we can calculate sizes right before packing, automagically, but for now we will just populate some files
#

# they will all go into the imager.buildconfig
# MBR/DOS partitioning scheme
export config_imager__partition_start_formatable_emmc_part
export config_imager__partition_size_p1
export config_imager__partition_size_p2
export config_imager__partition_size_p3
export config_imager__partition_start_p4
export config_imager__partition_start_p2
export config_imager__partition_start_p3
export config_imager__partition_start_p4

export config_imager__partition_size_system
export config_imager__partition_size_ota_state
export config_imager__partition_size_ota_extract
export config_imager__partition_size_config
export config_imager__partition_size_roconfig
export config_imager__partition_size_data
export config_imager__partition_size_system_overlay
export config_imager__partition_size_recovery_tarball



#
# Set default values for MBR/DOS partitionsing scheme - pscg_debos
# The sizes below are more than enough if the apt caches are cleaned. Otherwise, with graphics involved, they need to be increased
# Also, the OTA extract may need more space if you plan to keep the previous version as a fast OTA state test (skipping downloading and tarball extraction)
#
imager__set_default_emmc_partition_layout_pscgdebos() {
	# The default units for all of these are 512 byte sectors, unless they are specified with M.
	# Then, they will be relative
	# The units are taken from some common Android devices ported to Linux
	: ${config_imager__partition_start_formatable_emmc_part=$((4*$BYTES_PER_MIB/$BYTES_PER_SECTOR))}	# allow space for data not managed by our system (e.g. U-Boot and ATF)
	: ${config_imager__partition_start_p1=${config_imager__partition_start_formatable_emmc_part}}
	: ${config_imager__partition_size_p1=$((66*$BYTES_PER_MIB/$BYTES_PER_SECTOR))}
	: ${config_imager__partition_size_p2=$((66*$BYTES_PER_MIB/$BYTES_PER_SECTOR))}
	: ${config_imager__partition_size_p3=$((66*$BYTES_PER_MIB/$BYTES_PER_SECTOR))}
	: ${config_imager__partition_start_p4=$((1076*$BYTES_PER_MIB/$BYTES_PER_SECTOR))} # Start of the extended partition. Arbitrarily 2MB after the end of partition 3.
	# Note the partition sizes from here and on: we use the fdisk jargone (+<size>M)
	: ${config_imager__partition_size_system="+3072M"} # +700M was OK for debos without graphics, 3000M was ok for systemd and weston, 4000M was OK for adding firefox
	: ${config_imager__partition_size_ota_state="+10M"}
	: ${config_imager__partition_size_ota_extract="+3072M"} # just to also install the recovery tarball
	: ${config_imager__partition_size_config="+10M"}
	: ${config_imager__partition_size_roconfig="+10M"}
	: ${config_imager__partition_size_data="+512M"} # this is a placeholder - for when data gets its own partition
	: ${config_imager__partition_size_system_overlay="+1000M"} # this now includes data  (reduced it from 2600)
	: ${config_imager__partition_size_recovery_tarball="+2000M"} # 1250M was good for debos without graphics, 1450M was good for systemd and weston, 2000M for the latter+firefox
}

#
# Set default values for MBR/DOS partitionsing scheme - pscgbusyboxos
#
imager__set_default_emmc_partition_layout_pscgbusyboxos() {
	# The default units for all of these are 512 byte sectors, unless they are specified with M.
	# Then, they will be relative
	# The units are taken from some common Android devices ported to Linux
	: ${config_imager__partition_start_formatable_emmc_part=$((4*$BYTES_PER_MIB/$BYTES_PER_SECTOR))}	# allow space for data not managed by our system (e.g. U-Boot code, FPGA data, Android partitions, other things)
	: ${config_imager__partition_start_p1=$partition_start_formatable_emmc_part}
	: ${config_imager__partition_size_p1=$((66*$BYTES_PER_MIB/$BYTES_PER_SECTOR))}
	: ${config_imager__partition_size_p2=$((66*$BYTES_PER_MIB/$BYTES_PER_SECTOR))}
	: ${config_imager__partition_size_p3=$((66*$BYTES_PER_MIB/$BYTES_PER_SECTOR))}
	: ${config_imager__partition_start_p4=$((1076*$BYTES_PER_MIB/$BYTES_PER_SECTOR))} # Start of the extended partition. Arbitrarily 2MB after the end of partition 3.
	# Note the partition sizes from here and on: we use the fdisk jargone (+<size>M)
	: ${config_imager__partition_size_system="+500M"} # +700M was OK for debos without graphics, 3000M was ok for systemd and weston, 4000M was OK for adding firefox
	: ${config_imager__partition_size_ota_state="+10M"}
	: ${config_imager__partition_size_ota_extract="+1000M"}
	: ${config_imager__partition_size_config="+10M"}
	: ${config_imager__partition_size_roconfig="+10M"}
	: ${config_imager__partition_size_data="+100M"} # this is a placeholder - for when data gets its own partition
	: ${config_imager__partition_size_system_overlay="+1000M"} # this now includes data  (reduced it from 2600)
	: ${config_imager__partition_size_recovery_tarball="+1250M"} # 1250M was good for debos without graphics, 1450M was good for systemd and weston, 2000M for the latter+firefox
}

#
# Populate (build system independent) config file with the partition definitions
# $1: path to create config in
#
create_emmc_partition_config_file() {
	if [ ! -d "$(dirname $1)" ] ; then
		mkdir -p $(dirname $1) || fatalError "failed to create $(dirname $1)"
	fi

	echo "# $(date) autgenerated (hardcoded) for ${config_distro} by $0" > $1 || return 1
cat >> $1 << EOF
# RONz
: \${partition_start_formatable_emmc_part=${config_imager__partition_start_formatable_emmc_part}}
: \${partition_start_p1=\$partition_start_formatable_emmc_part}
: \${partition_size_p1=${config_imager__partition_size_p1}}
: \${partition_size_p2=${config_imager__partition_size_p2}}
: \${partition_size_p3=${config_imager__partition_size_p3}}
: \${partition_start_p4=${config_imager__partition_start_p4}}
# Note the partition sizes from here and on: we use the fdisk jargone (+<size>M)
: \${partition_size_system="${config_imager__partition_size_system}"}
: \${partition_size_ota_state="${config_imager__partition_size_ota_state}"}
: \${partition_size_ota_extract="${config_imager__partition_size_ota_extract}"}
: \${partition_size_config="${config_imager__partition_size_config}"}
: \${partition_size_roconfig="${config_imager__partition_size_roconfig}"}
: \${partition_size_data="${config_imager__partition_size_data}"}
: \${partition_size_system_overlay="${config_imager__partition_size_system_overlay}"}
: \${partition_size_recovery_tarball="${config_imager__partition_size_recovery_tarball}"}
EOF
}

#
# Some more variable names that might be useful
#
add_to_emmc_partition_config_file_common() {
	[ -f $1 ] || { echo "$1 does not exist" ; exit 1 ; }

	echo -e '\n### parition name definitions ###
: ${partition_label_boot=BOOT_EMMC}
: ${partition_label_boot_b=BOOT_EMMCB}
: ${partition_label_primary_partition_placeholder=PLACEHOLDER}
: ${partition_label_p1=$partition_label_boot}
: ${partition_label_p2=$partition_label_boot_b}
: ${partition_label_p3=$partition_label_primary_partition_placeholder}
# p4 is extended partition in this scheme
: ${partition_label_system=system}
: ${partition_label_ota_extract=otaextract}
: ${partition_label_ota_state=otastate}
: ${partition_label_config=config}
: ${partition_label_roconfig=configro}
: ${partition_label_data=datarw}
: ${partition_label_recovery_tarball=recoverytarball}
: ${partition_label_system_b=systemB}
: ${partition_label_system_overlay=systemrw}


: ${partition_number_p1=1}
: ${partition_number_p2=2}
: ${partition_number_p3=3}
: ${partition_number_p4=4}	# This is really just a marker for the extended partition.
: ${partition_number_system=5}
: ${partition_number_ota_extract=6}
: ${partition_number_ota_state=7}
: ${partition_number_config=8}
: ${partition_number_roconfig=9}
: ${partition_number_data=10}
: ${partition_number_recovery_tarball=11}
: ${partition_number_system_b=12}
: ${partition_number_system_overlay=13}
' >> $1
}

#
# Populate formatting functions. They will be called from the flasher on the target itself
#
add_formatting_functions_to_config_file_common() {
	echo '
#
# Create the first primary and extended partitions
#
create_primary_and_extended_partitions() {
	verbose "Removing all previous partitions..."
	echo -e "\
		o\nw\nq\n\
		" | fdisk $EMMC_DEVICE || fatalError "Failed to clear up partition table"

	verbose "Creating the primary partitions and one extended partition..."
	echo -e	"\
		n\np\n${partition_number_p1}\n$partition_start_p1\n+$partition_size_p1\nt\nc\n\
		n\np\n${partition_number_p2}\n$(($partition_start_p1+$partition_size_p1+1))\n+$partition_size_p2\nt\n2\nc\n\
		n\np\n${partition_number_p3}\n$(($partition_start_p1+$partition_size_p1+1+$partition_size_p2+1))\n+$partition_size_p3\nt\n3\nc\n\
		n\ne\n4\n${partition_start_p4}\n     \n\
		w\nq\n\
		" | fdisk $EMMC_DEVICE || fatalError "Failed to create the primary and extended partitions"
}


# For now we assume less space for a writable overlay etc.
# Ubuntu 23.04 with systemd and some networking packages took more than the size I had in mind,
# so these numbers will definitely change
#
#
# Note that we fill all of the 4 primary/extended partitions, "just in case" [no harm done].
# Therefore, everything coming after it in fdisk will not have a prompt for the partition number,
# nor will it have for the type of the partition. This means that for all of the logical partitions we will use
# a line like:
# 		n\n\n${partition_size_whatever}\n\
#
# Otherwise, that line would become something like this (where l is "logical" and "5" is the partition number...):
#		n\nl\n5\n\n${partition_size_whatever}\n\
#
create_emmc_partition_table() {
	trivial_installer_size_sanity_checks $EMMC_DEVICE # Check first. if we know it is going to fail, just fail the process before you do any more damage
	info "Recreating your partition table..."
	create_primary_and_extended_partitions
	verbose "Creating the logical partitions..."
	echo -e	"\
		n\n\n${partition_size_system}\n\
		n\n\n${partition_size_ota_extract}\n\
		n\n\n${partition_size_ota_state}\n\
		n\n\n${partition_size_config}\n\
		n\n\n${partition_size_roconfig}\n\
		n\n\n${partition_size_data}\n\
		n\n\n${partition_size_recovery_tarball}\n\
		n\n\n${partition_size_system}\n\
		n\n\n${partition_size_system_overlay}\n\
		w\nq\n\
		" | fdisk $EMMC_DEVICE || fatalError "Failed to create the logical partitions"

	info "Recreated the partition table"
}


#
# Formats the common partitions.
#
format_emmc_partitions() {
	## Boot partitions
	# This is a necessary to support first time flashing
	format_partition_vfat ${EMMC_DEVICE}${PARTITION_MARK}${partition_number_p1} ${partition_label_p1}
	format_partition_vfat ${EMMC_DEVICE}${PARTITION_MARK}${partition_number_p2} ${partition_label_p2}
	format_partition_vfat ${EMMC_DEVICE}${PARTITION_MARK}${partition_number_p3} ${partition_label_p3}

	## ext4  partitions
	# NOTE: it is important in general that the numbers will be in the right order for the fdisk part. The formatting order does not matter necessarily

	# Unless you are absolutely sure you want to erase the system partition, then it is better to not format it, because
	# assuming the system.img exists and is valid, you can save time by not formatting it - as it will be replaced with a dd-able system.img
	# Another reason we want to keep the system partition, is in case we want to wait until OTA verification (on an A/B case)
	# On an OTA, anyhow, it would be strongly recommended to not modify the partition structure, and so it is very reasonable to not
	# call this code at all, but only on an a_only installer scenario
	#
	# This code is NOT supposed to be called other than on an a_only case, unless someone hacks some demonstration
	#
	if [ "$config_imager__installer_runtime_format_system_partition" = "true" ] ; then
		format_partition_ext4 ${EMMC_DEVICE}${PARTITION_MARK}${partition_number_system} ${partition_label_system}
	fi

	format_partition_ext4 ${EMMC_DEVICE}${PARTITION_MARK}${partition_number_ota_extract} ${partition_label_ota_extract}
	format_partition_ext4 ${EMMC_DEVICE}${PARTITION_MARK}${partition_number_ota_state} ${partition_label_ota_state}

	format_partition_ext4 ${EMMC_DEVICE}${PARTITION_MARK}${partition_number_config} ${partition_label_config}
	format_partition_ext4 ${EMMC_DEVICE}${PARTITION_MARK}${partition_number_roconfig} ${partition_label_roconfig}
	format_partition_ext4 ${EMMC_DEVICE}${PARTITION_MARK}${partition_number_data} ${partition_label_data}

	format_partition_ext4 ${EMMC_DEVICE}${PARTITION_MARK}${partition_number_recovery_tarball} ${partition_label_recovery_tarball}
	format_partition_ext4 ${EMMC_DEVICE}${PARTITION_MARK}${partition_number_system_b} ${partition_label_system_b} # Note: system_b is a name only for initial flashing, afther that A/B change at every flash
	format_partition_ext4 ${EMMC_DEVICE}${PARTITION_MARK}${partition_number_system_overlay} ${partition_label_system_overlay}
}
' >> $1
}

add_sanity_checks_to_config_file_common() {
	echo '
#
# Sanity checks for sizes - helps to identify misconfigurations (can/should also use it at build time if sizes are known)
# This will only print an error and not more than that. It is used as a scripted fdisk will not exit on the first error, and if
# e.g., the partition sizes are too small to get in the disk, it is important to know that
# $1 - target emmc device (or image file), if exists
#
# Side effect: if you do not provide a parameter, the variable ballpark_required_storage_bytes will be available outside of the function,
#			   so you can use it for estimations
#
trivial_installer_size_sanity_checks() {
	local extended_megs=$(echo 0 $partition_size_system  $partition_size_ota_extract  $partition_size_ota_state \
	$partition_size_config  $partition_size_roconfig  $partition_size_data  $partition_size_recovery_tarball  \
	$partition_size_system $partition_size_system_overlay \
	| tr -d M  | bc)
	ballpark_required_storage_bytes=$(($partition_start_p4*512 + $extended_megs*1024*1024))
	if [ -n "$1" ] ; then
		local device_size=$(fdisk -l $1 | head -1 | cut -d, -f2 | cut -d" " -f2)

		if [ "$device_size" -lt "$ballpark_required_storage_bytes" ] ; then
			fatalError "Your storage at $1 is too small for your partition scheme ($device_size < $ballpark_required_storage_bytes)"
		fi
	else
		debug "Your estimated required storage size is $ballpark_required_storage_bytes ($(($ballpark_required_storage_bytes/1024/1024))MiB)"
	fi
}
	' >> $1
}

#
# Add some more things that are configuration related
#
add_more_definitions_to_config_file_common() {
	echo "
export config_imager__installer_runtime_recreate_partitions=$config_imager__installer_runtime_recreate_partitions
" >> $1
	if [ "$config_imager__allow_missing_system_installation" = "true" ] ; then
		echo "
export config_imager__allow_missing_system_installation=$config_imager__allow_missing_system_installation
export config_imager__installer_runtime_format_system_partition=$config_imager__installer_runtime_format_system_partition
" >> $1
	fi
}

main() {
	local outfile=$1
	case ${config_distro} in
		pscg_debos)
			info_do_or_die imager__set_default_emmc_partition_layout_pscgdebos
			;;
		pscg_busyboxos)
			info_do_or_die imager__set_default_emmc_partition_layout_pscgbusyboxos
			;;
		pscg_*)
			# do the busybox flow, and if you need more size, you can modify the function or copy from it and change according to what you want or need
			info_do_or_die imager__set_default_emmc_partition_layout_pscgbusyboxos
			;;
		*)
			fatalError "Unsupported distro ${config_distro}"
			;;
	esac

	info_do_or_die create_emmc_partition_config_file $outfile

	info_do_or_die add_to_emmc_partition_config_file_common $outfile
	info_do_or_die add_formatting_functions_to_config_file_common $outfile
	info_do_or_die add_sanity_checks_to_config_file_common $outfile
	info_do_or_die add_more_definitions_to_config_file_common $outfile
}


commonScriptPrologueLogRunAndEpilogue $@