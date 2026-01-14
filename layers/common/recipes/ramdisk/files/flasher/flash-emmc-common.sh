#!/bin/sh
source /commonEnv.sh
source /flasher/fsutils.sh
source /flasher/ota/otaCommon.sh

#
# Copy the contents of the "so called not hidden" files and folders in $1/$2 to the partition labeled as $2
# we map folder names to partitions here.
# $1: containing source dir. Expected to be something like <install-source-folder>/installables/folders/...
#	  but can take other forms, in case specific folders are needed to be explicitly copied (i.e.. copy boot after everything)
# $2: label of the partition to copy the contents to
#
# Use this only if you don't care about file permissions, if your target partition is a fat partition,
# or if if the source directory of the copying is on a non-fat filesystem.
# We do assume the default is a fat source fileystem, as this is how the simple installer was planned
#
# Otherwise, you may want to use an overlay tarball, or dd-able image file
#
install_installables_folder_contents_to_partition() {
	dod_shell [ -d "$1" ]
	dod_shell [ -n "$2" ]
	local srcdir=$1
	local dstdir=/mnt/$2
	if [ ! -d "$srcdir" ] ; then
		verbose "$srcdir is not a directory. no need to copy it"
		return
	fi

	dod_shell mkdir -p $dstdir
	dod_shell mount LABEL=$2 -o rw /mnt/$2

	local cpflags=-av
	if mount| grep $dstdir | grep -q vfat ; then
		cpflags=-rv
	fi

	cd $srcdir
	local filestocopy="*"
	for f in $filestocopy ; do
	if [ "$f" = "*" ] ; then
		warn "skipping copying of an empty $srcdir"
		continue
	fi
	dod_shell cp $cpflags $f $dstdir
	done
	sync
	cd -

	dod_shell umount /mnt/$2
	info "Done copying $2"
}


#
# Flash a parition image file into a partition
#	$1 - image file (or block device) to flash
#	$2 - path target partition to flash
#
# Note: This can be used with reverse directions for backing up partitions to images, if you wish to do so
#
install_ext_partition_from_image() {
	prevLogTag=$logTag
	logTag=$FUNCNAME

	local src=$1
	local blockdev=${EMMC_DEVICE}${PARTITION_MARK}$(eval echo \$$(eval echo partition_number_$2))
	local dst=$blockdev
	local bs=4M

	dod_shell [ -e "$src" ]
	dod_shell [ -b "$dst" ]

	info "dd-ing image $src --> $dst"
	verbose_do_or_die dd if=$src of=$dst bs=$bs

	dod_shell tune_and_resize_partition_ext4 $dst $label

	logTag=$prevLogTag
}

#
# Install a system partition taking into consideration A/B labeling
# $1 file to install to the next partition $target_system_partition, which will be relabled to $target_system_label
# 	 The reason for relabling is to allow an interim name, before declaring the new image is the new stable image
#
install_system_partition_from_image() {
	prevLogTag=$logTag
	logTag=$FUNCNAME
	local src=$1
	local dst=$target_system_partition
	local bs=4M

	if [ ! -e "$src" ] ; then
		if [ "$config_imager__allow_missing_system_installation" = "true" ] ; then
			warn "$src does not exist. the image was configured to support missing system.img although it is not a recommended configuration"
			if should_format_emmc ; then
				hardWarn "Your emmc will be formatted, so you're about to make a huge mistake, unless you really planned to do that..."
				# You can un/comment out the next line if you want to
				#fatalError "Not letting you do a huge mistake. Sorry"
			fi
			return
		else
			dod_shell [ -e "$src" ]
		fi
	fi
	dod_shell [ -b "$dst" ]

	info "dd-ing image $src --> $dst"
	verbose_do_or_die dd if=$src of=$dst bs=$bs

	dod_shell tune_and_resize_partition_ext4 $dst $label

	# If we do A/B updates, we want to flash with a DIFFERENT label as long as it is a candidate
	# if we flash an A-only sequence, the caller to this function would provide the right (final) target_system_label
	info "Relabeling $target_system_partition to $target_system_label to support A/B flashing. Will be relabeled again once image is announced stable."
   	if ! tune2fs -L $target_system_label $target_system_partition ; then
		error "Failed to set $target_system_partition label to $target_system_label"
		# you can decide that this requires falling back to recovery, or decide to live with that
		spawn_shell
	fi

	logTag=$prevLogTag
}

#
# This function encapsulates the main business logic of installing from installables/ to the formatted partitions.
#
# The logic loops over the relevant folders (folders, ext4images).
# ext4images is a hint, but in fact you can flash anything from there.
#
# The following environment variables are expected to be set prior to calling this function:
#	SRC_INSTALL_PARTITION_MOUNT_POINT	- mountpoint where the installables/ folder resides (i.e. either removable media, or an extracted folder)
#	target_boot_partition 			- block device where the bootloader will be flashed
#	target_system_partition			- block device where the system partition will be flashed
#   target_system_label				- system expected partition label. This enables labeling the partition during A/B phases
#
#	Unused (but can be used theoretically if we do A/B from this code (not recommended, and not discussed outside of the scope of kexec))
#   target_boot_label			- will not be used at this point anyway
#
# Boot A/B note [kexec note - for most - we discuss boot A/B in the context of bootloaders]
# We install the boot materials last, if it exists, to avoid hazards, that are dealt with with A/B for the boot images
# (which is better implemented in the bootloader level, and perhaps we will show a reference design here
# as well, using kexec. The mechanism is simple, but as kexec is not a busybox native citizen, it will take
# focus from the important tasks we want to demonstrate here. So if I don't mention it, don't ask about it.
# Note that kexec is not implemented by busybox (but using the system call is relatively easy. If your memory layouts are properly organized etc...)
#
#
install_to_parititions_core_materials() {
	for f in $(ls -A ${SRC_INSTALL_PARTITION_MOUNT_POINT}/installables/ext4images/*.img 2> /dev/null) ; do
		local label=$(basename -s .img $f)
		if [ "$label" = "$SYSTEM_DEFAULT_LABEL" ] ; then
			break	# system gets a special treatment, as it is an A/B partition
		fi
		info_do_or_die install_ext_partition_from_image $f $label
	done

	for d in $(ls -A ${SRC_INSTALL_PARTITION_MOUNT_POINT}/installables/folders) ; do
		local path=${SRC_INSTALL_PARTITION_MOUNT_POINT}/installables/folders/$d
		info_do_or_die install_installables_folder_contents_to_partition $path $d
	done

	# Install the system partition
	# This is done separately to empahsize the A/B logic in it
	info_do_or_die install_system_partition_from_image ${SRC_INSTALL_PARTITION_MOUNT_POINT}/installables/ext4images/system.img

	# Install the main boot partition
	# This is done separately for a good reason as explained in the comments of the calling functions and in the error message
	info_do_or_die install_installables_folder_contents_to_partition ${SRC_INSTALL_PARTITION_MOUNT_POINT}/installables/bootfat $partition_label_boot || fatalError
}

#
# Extract all the tarballs under the $1 directory onto the $2 folder
# This will preserve permissions, so it is safe to use this for overlaying the tarball contents on top of Linux file systems
# The 'overlays' name is not ideal and may change in the future
#
# Upon extraction, a predefined file will be searched for, and if exists, will be executed. Therefore,
# before extracting every tarball, we remove a possible remainder of this file.
#
# $1: containing source dir. Expected to be something like <install-source-folder>/installables/overlays/...
#	  but can take other forms, in case specific folders are needed to be explicitly copied (i.e.. copy boot after everything)
# $2: label of the partition to copy the contents to
# $3: optional directory for populating logfiles of extra activities (e.g. if the tarball contains an "overlay-install-instructions.sh" file)
#
# Permissions will be preserved if the filesystem supports it (e.g. if it's not fat)
#
extract_tarballs_in_folder_to_folder() (
	dod_shell [ -d "$1" ]
	dod_shell [ -d "$2" ]
	local srcdir=$1
	local dstdir=$2
	local logdir=$3

	if [ ! -d "$srcdir" ] ; then
		verbose "$srcdir is not a directory. no need to look for tarballs in it"
		return
	fi

	# Allow to execute a shell script put in the tarball file
	# Delete a previous file if it exists (not supposed to happen unless you debug or had an error and did not format the partition after it)
	local instructionsfile=$dstdir/overlay-install-instructions.sh
	if [ -f $instructionsfile ] ; then
		warn "$instructionsfile existed before extracting tarballs from $1. removing it."
		dod_shell rm /$instructionsfile
	fi

	cd $srcdir
	filestoextract="*"
	for f in $filestoextract ; do
		if [ "$f" = "*" ] ; then
			warn "It is likely that someone presented you with an empty folder. please check $PWD. It's not a big deal and we got over it"
			continue
		fi
		verbose "Applying tarball overlay $f..."
		if ! tar -C $dstdir -xf $f ; then
			error "Failed to extract tarball $f to $dstdir. Giving a chance to the hacker who might have put some files in the wrong place..."
			if tar -tf $f ; then
				fatalError "Failed to extract tarball $f to $dstdir. The tarball seems to be broken"
			else
				warn "Seems like $f is not a valid taball. Ignoring it and continuing"
				continue
			fi
		fi

		# The following export is only for the instruction file to use. It allows the callee to know if it is
		# extracted in an overlay or not, and do things in chroot if it wants to, or directly on it otherwise
		# the debug checkpoint is nice to have - but do noe that it will be called for every tarball
		# if you want to further debug, you may want to tee the output instead of just redirecting it with &>
		# (as done below)
		export instruction_file_folder_location=$dstdir
		debug_stopatramdisk_checkpoint pre_tarball_instructionsfile

		if [ -x $instructionsfile ] ; then
			verbose "$instructionsfile found. executing commands in it"
			if [ -d "$logdir" ] ; then
				# Enable a developer to debug their instructions file
				instructionfileoutputlog=$logdir/overlay-$(basename $srcdir)-$f.log
				debug "$instructionsfile output log: $instructionfileoutputlog"
				$instructionsfile &> $instructionfileoutputlog || fatalError "$instructionsfile failed"
			else
				$instructionsfile || fatalError "$instructionsfile failed"
			fi
			dod_shell rm $instructionsfile
		else
			verbose "$instructionsfile does not exist. Will not execute extra commands"
		fi
	done
	sync
	cd -
	info "Done extracting tarballs from $1 --> $2"
)

#
# Mount partition by label onto /mnt/$2 and then extract all tarballs under $1  onto /mnt/$2
#
# Extract all the tarballs under the $1 directory onto the respective $2 partition
# This will preserve permissions, so it is safe to use this for overlaying the tarball contents on top of Linux file systems
# The 'overlays' name is not ideal and may change in the future
#
# $1: containing source dir. Expected to be something like <install-source-folder>/installables/overlays/...
#	  but can take other forms, in case specific folders are needed to be explicitly copied (i.e.. copy boot after everything)
# $2: label of the partition to copy the contents to
#
# Permissions will be preserved if the filesystem supports it (e.g. if it's not fat)
#
#
extract_tarballs_in_folder_to_partition() {
	dod_shell [ -d "$1" ]
	local srcdir=$1
	local dstdir=/mnt/$2
	dod_shell mkdir -p $dstdir
	dod_shell mount LABEL=$2 -o rw $dstdir
	dod_shell extract_tarballs_in_folder_to_folder $srcdir $dstdir $logdir_tarball_overlays
	dod_shell umount $dstdir
}

#
# $1: containing source dir. Expected to be something like <install-source-folder>/installables/writableoverlays/...
#	  but can take other forms, in case specific folders are needed to be explicitly copied (i.e.. copy boot after everything)
# $2: label of the partition to copy the contents to. We assume that this is used to overlay on top of a read-only system, and so we assume that
#	  the contents of partition label $2 will be overlayed with the contents of partition label ${2}rw - unless there is an explicit third argument.
# [$3]: If it exists, it means the user wants to be explicit the labels of the lower and upper partitions. In that case:
#		  $1: stays as it is
#		  $2: is the lower partition label ($3 will be overlaid on top of it)
#		  $3: is the upper partition label (will be overlaid on top of $2)
#
# A typical usecase for 2 paramaeters:  using  $2=system
# A typical usecase for 3 parameters: using $2=system-pscg-can $3=systemrw , during an A/B update that did not run to completion, e.g. during recovery
#
extract_tarballs_in_folder_to_prospective_overlayfs_upper() {
	local srcdir=$1
	local lower_label=$2
	local upper_label=${2}rw
	dod_shell [ -d "$srcdir" ]

	 if [ $# -eq 3 ] ; then
		upper_label=$3
	 fi

	hardWarn "remove_previous_overlayfs_contents=$remove_previous_overlayfs_contents"
	if [ "$remove_previous_overlayfs_contents" = "true" ] ; then
		# Formatting the overlayfs upper partition if it exists. We assume ext4 as everything else assumes so to, otherwise, we
		# may rewrite this, it's simple. We can also mount and delete the contents, but this is more efficient
		# This would happen mostly during a software update, but could also be controlled from cmdline
		#
		# Note that this is systemrw specific - and it is easily changable (just inside the if) but it is unlikely anyone will need another label other than the systemrw,
		# so we leave it as is, and add a fatalError in case it is needed, so that it is easily observable.
		warn "Removing previous overlayfs contents if they existed"
		if [ ! "$upper_label" = "$partition_label_system_overlay" ] ; then
			fatalError "You are trying to overlay $upper_label on top of $lower_label and the former is not the system overlay partition. This has not been tested yet. If you have a good reason to do that, please modify this comment and remove the error line"
		fi
		debug_stopatramdisk_checkpoint pre_remove_previous_overlayfs_contents
		format_partition_ext4 ${EMMC_DEVICE}${PARTITION_MARK}${partition_number_system_overlay} ${partition_label_system_overlay}
	fi

	# Could do switch case to see different error values instead of being so drastic
	# but by design there should not be an error at all in the mounting
	debug_mount_overlay_reason=installation
	info_do_or_die mount_overlayed_filesystem_by_labels $lower_label $upper_label
	local dstdir=$OVERLAYFS_MOUNT_POINT_BASE_DIR/$upper_label/fsmaterials/upper
	dod_shell [ -d "$dstdir" ]

	dod_shell extract_tarballs_in_folder_to_folder $srcdir $dstdir $logdir_tarball_overlays

	local unmountdirs="$OVERLAYFS_MOUNT_POINT_BASE_DIR/$upper_label/fsmaterials/merged $OVERLAYFS_MOUNT_POINT_BASE_DIR/$upper_label $OVERLAYFS_MOUNT_POINT_BASE_DIR/$lower_label"
	do_or_die umount $unmountdirs
}

#
# This function applies the tarballs from the overlays/ and writableoverlays/ folders onto the respective partitions.
#
install_to_partitions_tarballs_and_overlayfs_materials() {
	logdir_tarball_overlays=/tmp/logs # used in subsequent functions
	dod_shell mkdir -p $logdir_tarball_overlays

	local searchdir=${SRC_INSTALL_PARTITION_MOUNT_POINT}/installables/overlays
	for d in $(ls -A $searchdir) ; do
		if [ "$d" = "$SYSTEM_DEFAULT_LABEL" ] ; then
			break	# system gets a special treatment, as it is an A/B partition
		fi
		local path=$searchdir/$d
		info_do_or_die extract_tarballs_in_folder_to_partition $path $d
	done

	# system gets a special treatment, in terms that in an A/B update, we want to update to the candidate
	# in a non A/B the target_system_label will be identical to $SYSTEM_DEFAULT_LABEL anyway so this logic is correct
	if [ -d "$searchdir/$SYSTEM_DEFAULT_LABEL" ] ; then
		info_do_or_die extract_tarballs_in_folder_to_partition $searchdir/$SYSTEM_DEFAULT_LABEL  $target_system_label
	fi


	# Since overlays are mostly meant for one partition, it is likely that the next loop will never run. However, for the sake of flexibility, we leave it.
	# Flexibility, meaning, if someone decides to overlay things on top of other partitions, and of course changes the disk layout and labels accordingly.
	# While *very* unlikely, an exmample could be that someone wants to overlay datarwrw on top of datarw, or something like that.
	local searchdir=${SRC_INSTALL_PARTITION_MOUNT_POINT}/installables/writableoverlays
	for d in $(ls -A $searchdir) ; do
		local path=$searchdir/$d
		if [ "$d" = "$SYSTEM_DEFAULT_LABEL" ] ; then
			break	# system gets a special treatment, as it is an A/B partition
		fi
		# Such a loop assumes a mountable overlayfs dir etc...
		info_do_or_die extract_tarballs_in_folder_to_prospective_overlayfs_upper $path $d
	done

	if [ -d "$searchdir/$SYSTEM_DEFAULT_LABEL" ] ; then
		info_do_or_die extract_tarballs_in_folder_to_prospective_overlayfs_upper $searchdir/${SYSTEM_DEFAULT_LABEL} $target_system_label ${SYSTEM_DEFAULT_LABEL}rw
	fi
}

#
# Install from the installation media or folders.
# This encapsulates the logic of all flashing including:
# - BSP specific copying/backup/restore etc.
# - Installation to partitions of either specified folders or image files
# - Applying overlay tarballs to partitions (by labels)
#
do_install_to_partitions() {
	info "Installing to partitions: src=${SRC_INSTALL_PARTITION_MOUNT_POINT}  boot=$target_boot_partition root=$target_system_partition"

	call_if_exists bsp_post_partition_format_pre_install_to_partitions	# e.g. backup/restore from "non visible" paritions (Some examples can be U-Boot binaries, logos, environments, etc.)

	install_to_parititions_core_materials

	install_to_partitions_tarballs_and_overlayfs_materials

}