#
# fsck wrapper that returns 0 if there were no errors or the errors were fixed, and 2 otherwise
#
fsck_wrapper_check_by_partition_path() {
	local blockdev=$1
	verbose_do e2fsck -p $blockdev
	case $? in
		0)
			return 0
			;;
		1|2)
			warn "fsck corrected errors and returned with $?"
			return 0
			;;
		*)
			error "fsck returned with $?. you have serious errors that could not be automagically corrected"
			return 2
			;;
	esac
}

#
# Utility function to restructure existing partitions as ext4, as busybox tools are not that awesome by default and this task is done in a rush
# $1 partition
# $2 label
#
tune_and_resize_partition_ext4() (
        partition=$1
        label=$2
        if [ -z "$partition" -o -z "$label" ] ; then
                errorExitScope "Wrong usage: partition=$partition label=$label"
        fi
	# Journaling is critical
	MORE_OPTIONS=""
	# Note the -q must be provided only on the last pipe if we pipe multiple greps
	# Note: we have some tiny file systems (for the first try...) so journaling is not supported on them (will adjust on the new product)
	if tune2fs -l $partition | grep -q has_journal ; then
		# We add some of the ext4 features here. we could chose others. important thing is that -O maybe specificied only once, so beware if you change this logic
		MORE_OPTIONS="$MORE_OPTIONS -O extents,uninit_bg,dir_index"
	else
		# add journal too
		MORE_OPTIONS="$MORE_OPTIONS -O has_journal,uninit_bg,dir_index"
	fi

	# Shrinking inode size is not supported so commenting that out
	# tune2fs -l $partition | grep "Inode size" | grep -q 128 || MORE_OPTIONS="$MORE_OPTIONS -I 128"  # This inode size changing is not necessary. we may actually want the bigger one as it is more efficient in performance (and trade it off for disk space
	MORE_OPTIONS="$MORE_OPTIONS -m 0"

	# The following are meant to control fsck.
	# -i 0 is required since there is no hardware clock
	# -c can be set to any value. we will opt to do our own maintenance, so we also set it to 0
	MORE_OPTIONS="$MORE_OPTIONS -i 0 -c 0"

	verbose "Tuning and resizing ext4 partition $partition to label $label . Other options: $MORE_OPTIONS"
	verbose "Force resizing first. if fs is damaged this is not good. On the other hand, we can and should resolve all tradeoffs prior to providing the image file for flashing in the first place"
	resize2fs -f $partition || errorExitScope "Can't apply the first resize"

	if ! tune2fs $MORE_OPTIONS -L $label $partition ; then
		error "Failed to tune file system parameters. This could be due to a source file system that was deliberately smaller and not containing journal, so we will now try to fix it if this is the case. If not, we shall accept the failure"
		resize2fs -f $partition || errorExitScope "Can't apply the (almost) first resize. We should not resize twice anyway, so for now it is mostly an integrity indication. To be changed"
		tune2fs $MORE_OPTIONS -L $label $partition || errorExitScope "Failed to label the system partition or apply other tunable options"
	fi
	# Notes about fsck -
	#	As the busybox implementation of tune2fs seems to mess up the filesystem. Busybox does not have fsck for ext2/ext4 (makes no sense, but it is the way it is).
	#	e2fsprogs and the relavant dosfsutils have been added to the initramfs.
	#	- You could significantly decrease the size of the initramfs by avoiding these tools, but then you would not be able to format the partitions properly at runtime.
	#	- Another alternative is to do it offline before flashing -i.e. have the right label name - however for dual bank update we would have to
	#	  either change the method of booting, or modify the label upon updates, on the fly.
	#	Note that we do not have secure/trusted boot, so this kind of solution is pretty good.
	#
	# 	The way we use fsck before and after resize2fs does the best to ensure that the file system is in a good state:
	# 	- fsck -p fixes automatically, and fsck -f forces checks.
	#	- however they don't work together, and for now we prefer to fail rather than get stuck on user interaction
	fsck_wrapper_check_by_partition_path $partition || errorExitScope "Failed to fsck $partition before resize2fs - it is very likely you will not be able to boot"
	resize2fs -f $partition || errorExitScope "Failed to resize $partition - actually we should do it as part of the tune2fs code, and it will be left for future optimization phases"
	fsck_wrapper_check_by_partition_path $partition || errorExitScope "Failed to fsck $partition after resize2fs - it is very likely you will not be able to boot"
)

#
# Utility function to format partitions as ext4, as busybox tools are not that awesome by default and this task is done in a rush
# We need to include e2fsprogs in the ramdisk and do it properly
# $1 partition
# $2 label
#
format_partition_ext4() (
        partition=$1
        label=$2
        if [ -z "$partition" -o -z "$label" ] ; then
                errorExitScope "Wrong usage: partition=$partition label=$label" 1
        fi

	verbose "Formatting $partition / $label "
        USE_BUSYBOX_MKE2FS=true # this saves 1M in the initrd. but requires tuning the file systems
        if [ "$USE_BUSYBOX_MKE2FS" = "true" ] ; then
                # -T ext4 is misleading and in facts makes an ext3 in busybox. so we do not use this.
		mke2fs -F -m 0 -L $label $partition || errorExitScope "Failed to format partition $partition to with label $label (with busybox tools)"
        else
                mke2fs -F -t ext4 -m 0 -L $label $partition | errorExitScope "Failed to format partition $partition to with label $label"
                # Then, if we do not dd and modify the partition and filesystem characteristics, we do not need to overwrite this
        fi

	tune_and_resize_partition_ext4 $partition $label || errorExitScope "Tuning to ext4 and resizing $partition with label $label failed."
)



#
# Utility function to format partitions as vfat
# $1 partition
# $2 label
#
format_partition_vfat() (
	partition=$1
	label=$2
	if [ -z "$partition" -o -z "$label" ] ; then
		errorExitScope "Wrong usage: partition=$partition label=$label" 1
	fi

	USE_BUSYBOX_MKFS_VFAT=true # this saves 1M in the initrd. but requires tuning the file systems
	if [ "$USE_BUSYBOX_MKFS_VFAT" = "true" ] ; then
		verbose "Formatting $partition / $label "
		mkfs.vfat -n $label $partition || fatalError "Failed to format the fat partition $partition and set label to $label"
	else
		fatalError "Non busybox format is not supported"
	fi
	# Here we do not do any tunables, although we may want to remove the dirty bit
)
