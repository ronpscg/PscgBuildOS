#!/bin/bash

# Usage:  <value>
#
# Does not verify input validity, so be careful when using it
# We could add several functions to do something like  foo a b and set a to b - but this would require too much explanation of bash stuff
# so we keep it simple - usage is by echoing te result
#
# $1: value
#
#
set_true_false_by_value() {
		case $1 in
		"") fatalError "Must provide a value" 	;;
			1|true|y|Y) echo -n "true"      	;;
			0|false|n|N) echo -n "false" 		;;
			*) fatalError "Please provide a proper value" ;;
        esac
}

init_env() {
	: ${logFile=${TMP_TOP}/$(basename $0).log} # allow running the script independently and yet allowing -u in older builds
	: ${logTag=devbuild} # allow running the script independently and yet allowing -u) in older builds
}

init_folders() {
	set -euo pipefail
	mkdir -p $RAMDISK_BUILD_WORKING_DIRECTORY
	if [ -d $RAMDISK_DIR ] ; then
		warn "Ramdisk already exists. " # TODO decide what to do with it
		if [ "$config_ramdisk_removeprev" = "true" ] ; then
			warn "removing previous ramdisk contents"
			dod rm -rf $RAMDISK_DIR
			dod rm -rf $RAMDISK_PACKED
			dod rm -rf $RAMDISK_PACKED_UBOOT # nothing will happen if it does not exist
		fi
		#you could recreate, won't do now... rm -rf $RAMDISK_DIR TODO decide / add an environment variable
	fi
	mkdir -p $RAMDISK_DIR || fatalError "Failed to create $RAMDISK_DIR"

	# TODO I don't think this is needed but let's see
	# To avoid building as super user, using fakeroot (or the likes) etc., change permissions first. This is a lazy hack for rebuilding
	if [ "$USE_SUDO_IF_NOT_CAPABLE" = "true" ] ; then
		if [ -d $RAMDISK_DIR -a ! "$(id -u)" = "0" ] ; then
			sudo chown -R $(id -un):$(id -gn) $RAMDISK_DIR || fatalError "Failed to change ownership"
		fi
	fi

	set +euo pipefail
}

copy_swissknife_to_ramdisk() {
	case $config_ramdisk__shell_swissknife in
		busybox)
			info_do_or_die cp -a $BUSYBOX_INSTALL_DIR/* $RAMDISK_DIR
			;;
		*)
			fatalError "Unsupported swissknife: $config_ramdisk__shell_swissknife"
			;;
	esac
}

verify_statically_linked_binaries() {
	case $config_ramdisk__shell_swissknife in
		busybox)
			# First, verify that busybox is not accidentally dynamically linked. Otherwise, you need to copy the desired shared folders, linker, etc.
			readelf -d $RAMDISK_DIR/bin/busybox  | grep -q "There is no dynamic section in this file" || fatalError "Your $RAMDISK_DIR/bin/busybox is dynamically linked. Were you playing with configuring it?"
			;;
		*)
			fatalError "Unsupported swissknife: $config_ramdisk__shell_swissknife"
			;;
	esac
}

copy_prebuilts_to_ramdisk() {
	$BUILD_TOP/layers/common/prebuilts/copy-prebuilts-e2fsprogs-to-ramdisk.sh $RAMDISK_DIR || fatalError "Failed to copy ramdisk prebuilts"
	$BUILD_TOP/layers/common/prebuilts/copy-prebuilts-more-tools-to-ramdisk.sh $RAMDISK_DIR|| fatalError "Failed to copy more tools from prebuilts to ramdisk"

	# simple, does not support permissions
	for d in $config_ramdisk__directories_to_create ; do
		info_do_or_die mkdir -p $RAMDISK_DIR/$d
	done

	# copy more files - deliberately all go to one directory, as the objective here was the copy kernels for kexec
	# otherwise, one could add something like a list of src0:dst0 src1:dst1 etc. parse them and copy them, it's easy,
	# but more to write in the configuration optins so I chose to not do it
	if [ -n "$config_ramdisk__more_files_to_copy_src" -a -n "$config_ramdisk__more_files_to_copy_dst" ] ; then
		# This is a place to copy a capture kernel from (e.g. for kexec)
		if [ ! -d "$RAMDISK_DIR/$config_ramdisk__more_files_to_copy_dst" ] ; then
			fatalError "Destination directory $RAMDISK_DIR/$config_ramdisk__more_files_to_copy_dst does not exist"
		fi

		# Please make sure you copy from files you have read access to (meaning: if you copy a kernel, don't copy it directly from /boot/ please)
		# the ramdisk is packed unprivileged, and we don't want to change this logic just for a kexec demonstration
		for ford in $config_ramdisk__more_files_to_copy_src ; do
			info_do_or_die cp -a $ford $RAMDISK_DIR/$config_ramdisk__more_files_to_copy_dst/
		done
	fi
}

populate_ramdisk() {
	cd $RAMDISK_DIR
	mkdir -p bin dev etc lib mnt proc sbin sys tmp var || fatalError "Failed to create the base directories in $RAMDISK_DIR"

	copy_swissknife_to_ramdisk
	copy_prebuilts_to_ramdisk
	# verify that some utils that we build are statically linked
	# we don't need to verify some of the prebuilts we already know are statically linked
	verify_statically_linked_binaries


	# Add init scripts
	cp -p $LOCAL_DIR/files/init						$RAMDISK_DIR/init || fatalError "Could not copy init"
	cp -rp $LOCAL_DIR/files/init-helpers/			$RAMDISK_DIR/ || fatalError "Could not copy init-helpers/"
	# TODO ramdisk should get its own project
	cp -p $LOCAL_DIR/files/commonEnv.sh				$RAMDISK_DIR/commonEnv.sh || fatalError "Could not copy commonEnv"
	cp -rp $LOCAL_DIR/files/flasher					$RAMDISK_DIR/ || fatalError "Could not copy flasher"

	if [ "$config_ramdisk__add_ethernet_network_hooks" = "true" ] ; then
		cp -rp $LOCAL_DIR/files/network   $RAMDISK_DIR || fatalError "Failed to copy the ramdisk network setup code"
	fi

	if [ "$USE_SUDO_IF_NOT_CAPABLE" = "true" ] ; then
		if [ ! "$(id -u)" = "0" ] ; then
				# This is not really necessary, more like nice to have.
				# the downside here is that one would have to change ownership to build user before running
				# the script, or run as superuser (not work here is qnd so there is much to change to do it cleaner"
			info "Changing ramdisk directory files permissions to be owned by the superuser"    # todo: if script is run directly info is unknown so make sure we source commonEnv everywhere
			sudo chown -R root:root $RAMDISK_DIR/* || fatalError "Failed to change ownership to superuser"
		fi

		# TODO: we don't need this if we use mdev - otherwise, you pretty much need this for console on your rootfs
		if [ ! "$config_ramdisk_create_nodes" = "true" ] ; then
			# [optional] create character devices
			# This fixes busybox's "Warning: unable to open an initial console", should you not call mdev
			#
			if [ ! -e $RAMDISK_DIR/dev/console ]; then
					sudo mknod -m 666 $RAMDISK_DIR/dev/console c 5 1
			fi
		fi
	fi

	echo -e VERSION=\"thepscg-busyboxos-$(date '+%y-%m-%d_%H-%M-%S')\" > $RAMDISK_DIR/etc/thepscgos-release

	if [ -f "$imager__target_partition_defs_generator" ] ; then
		warn "Overriding target partition definitions"
		verbose_do_or_die $imager__target_partition_defs_generator $RAMDISK_DIR/flasher/config/partitions-emmc.config
	else
		fatalError "$imager__target_partition_defs_generator does not exist"
	fi
}

#
# Wrap the filesystem in a gzipped cpio file, or cpio file. The compression method must be supported by the target kernel
#
repack_ramdisk() (
	local cpiov=""
	[ "$config_ramdisk__verbose_cpio" = "true" ] && cpiov="v"
	verbose "Repacking ramdisk: ( $RAMDISK_DIR --> $RAMDISK_PACKED )"
	cd $RAMDISK_DIR
	case $config_ramdisk__compression in
		cpio)
			find . | cpio -o$cpiov --format=newc > $RAMDISK_PACKED || fatalError "Failed to compress ramdisk"
			;;
		cpio.gz)
			find . | cpio -o$cpiov --format=newc | gzip -9 > $RAMDISK_PACKED || fatalError "Failed to compress ramdisk"
			;;
		*)
			fatalError "Illegal ramdisk compression type $config_ramdisk__compression"
			;;
	esac
	verbose "Done packing ramdisk ( $RAMDISK_DIR --> $RAMDISK_PACKED )"
)

pack_for_uboot() {
	mkimage \
		-A $ARCH \
		-O linux \
		-T ramdisk \
		-C gzip \
		-n "The PSCG Ramdisk" \
		-d $RAMDISK_PACKED \
		$RAMDISK_PACKED_UBOOT \
		|| fatalError "Failed to create ramdisk in u-boot format (64 bytes of header followed by the compressed ramdisk)"
}

install_packed_images() {
	# copy ramdisk image to the relevant boot place
		if [ "$config_bsp__bootloader" = "uboot" ] ; then
			cp $RAMDISK_PACKED_UBOOT $BOOT_DIR/ || fatalError "Failed to copy u$RAMDISK_TYPE to $BOOT_DIR"
			info "Done. your u-boot packed ramdisk is ready at $BOOT_DIR/u$RAMDISK_TYPE"
		else
			cp $RAMDISK_PACKED $BOOT_DIR/ || fatalError "Failed to copy $RAMDISK_TYPE.$config_ramdisk__compression to $BOOT_DIR"
			info "Done. your $config_ramdisk__compression packed ramdisk is ready at $BOOT_DIR/$RAMDISK_TYPE.$config_ramdisk__compression"
		fi
}

#
# Repack and install ramdisk if needed
# Allows calling it both from build-imitramfs.sh and from other places that may copy things to the ramdisk,
# such as firmware files, kernel modules, etc.
#
repack_and_install_ramdisk() {
	dod repack_ramdisk
	if [ "$config_bsp__bootloader" = "uboot" ] ; then
		dod pack_for_uboot
	fi
	install_packed_images
}

main() {
	#
	# I really wanted to keep this file self contained and usable regardless of the build system, so that
	# it would be identical to the process in PSCG-mini-linux - but given the rich feature list of PscgBuildOS,
	# it doesn't make sense to restrict it. Adding this option here is concise enough to not require
	# a change to the build system, only calling the script twice which is fine.
	#
	if [ "$1" = "repackonly" ] ; then
		info "Repacking initrafms only"
		init_env $@
		repack_and_install_ramdisk
		return
	elif [ "$1" = "buildonlydontrepack" ] ; then
		info "Building initramfs only, not repacking"
		init_env $@
		init_folders
		dod populate_ramdisk
		return
	fi

	# This has been the flow since the beginning, leaving it as is, although unless you want to repack twice,
	# it will no longer be called by build-distro-common-linux.sh
	init_env $@
	dod init_folders

	if [ "$config_ramdisk_install" = "true" ] ; then
		dod populate_ramdisk
		dod repack_ramdisk
		if [ "$config_bsp__bootloader" = "uboot" ] ; then
			dod pack_for_uboot
		fi
		install_packed_images
	fi
}

commonScriptPrologueLogRunAndEpilogue $@