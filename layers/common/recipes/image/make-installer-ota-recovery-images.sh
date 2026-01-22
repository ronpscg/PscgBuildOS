#!/bin/bash
#
# This script creates an installable fat media
# The fat format is selected as it is natively supported by every bootloader that respects itself, and trivial image
# manipulations also in Operating Systems that are less friendly to ext-filesystems
#

#
# This function adds "boot files" as well as boot "instruction files" to the top working directory,
# meaning that they will find themselves at the top of the extracted materials for an OTA, and
# at the top of the installation media.
# The latter (installation media) is indeed the former + digests and manifests [ + the compressed former in the form of a recoverytarball ]
#
# Some of the things you can put here are:
# - a bootable image (kernel, ramdisk, device tree blobs, etc.)
# - bootloader materials (u-boot/grub/etc. code and config)
# - Firmware
# - instrctions files for the flasher or for the system (mostly for the ramdisk)
# - More. Basically some of these files can be in some BSP's in a dedicated partition, however, this is the reference design as per now.
#
populate_working_directory_with_boot_materials() {
	info "populating working directory boot files"

	# it is very unlikely to have disk space issues here, but let's be safe. If there are disk issues here, there will definitely be issues later
	check_folder_free_space $config_imager__workdir_ext_partition_images \
		$(( $(du -sb $distro__image_materials_installables_bootfs_dir | cut -f1 ) + $(du -sb $distro__image_materials_removable_media_specifics_dir | cut -f1) )) \
		fail \
		:

	# Copy the installable bootfs materials if they exist - this goes to the top of the working directory
	if [ -d "$distro__image_materials_installables_bootfs_dir" ] && [ ! "$(ls -A $distro__image_materials_installables_bootfs_dir)" = "" ] ; then
		verbose_do_or_die mcopy -snm $distro__image_materials_installables_bootfs_dir/*  ${config_imager__workdir}/
	fi

	# Copy everything in the removable media specifics dir directly onto the workdir
	# they will find themselves in the root of the removable installer media
	if [ -d "$distro__image_materials_removable_media_specifics_dir" ] && ! [ "$(ls -A $distro__image_materials_removable_media_specifics_dir)" = "" ] ; then
        verbose_do_or_die mcopy -snm $distro__image_materials_removable_media_specifics_dir/* ${config_imager__workdir}
	fi

	if [ "$config_imager__autoflash" = "true" ] ; then
		info "Making the image autoflashable. User can choose to remove it"
		do_or_die touch ${config_imager__workdir}/autoflash
	fi

	if [ "$config_imager__dontformatemmc" = "true" ] ; then
		warn "Preventing emmc format upon installation. You really shouldn't do it unless you know what you're doing"
		do_or_die touch ${config_imager__workdir}/dontformatemmc
	fi

}

#
# Copy installables folders to installables/folders of the working directory
# Use this only for folders you do not care about permissions etc.
# Since the installer is fat, if you need permissions separately, prepare them as overlay tarballs instead
#
# The motivation behind this logic is to allow people in less friendly host operating systems to
#
# TODO: The following functions can be easily merged into a common function and called with parameters
# 		but it is clearer to have their specific names and code in front of the eyes
#		might do it after a couple of sessions
#
copy_to_fat_installable_folders() {
	local src=$distro__image_materials_installables_folders_dir
	if [ ! -d "$src" ] ; then
		verbose "Skipping $FUNCNAME (no sources)"
		return
	fi

	info "Copying installable/folders"
	do_or_die rm -rf ${config_imager__workdir}/installables/folders
	do_or_die mkdir -p ${config_imager__workdir}/installables/folders

	local src_installables_folders=${distro__image_materials_installables_folders_dir}

	for d in $(ls -A $src_installables_folders) ; do
		check_folder_free_space ${config_imager__workdir} $(( $(du -sb ${src_installables_folders}/"$d" | cut -f1) )) fail :
		verbose_do_or_die mcopy -snm $src_installables_folders/"$d" ${config_imager__workdir}/installables/folders
	done
}

#
# Copy tarballs from respective folders to respective folders. These will be overlaid (extracted) by the flasher, onto
# the exact same partitions that their containing folder matches with the labels
# (as opposed to "writableoverlays" which are meant to be used in overlayfs, and are not popolated automatically now
# (ideas: provisioned read/write data on systemrw partition, putting apt-caches there, etc)
#
copy_installables_overlays_tarballs() {
	local src=${distro__image_materials_installables_overlays_dir}
	if [ ! -d "$src" ] ; then
		verbose "Skipping $FUNCNAME (no sources)"
		return
	fi
	info "Copying installable/overlays"
	do_or_die rm -rf ${config_imager__workdir}/installables/overlays
	do_or_die mkdir -p ${config_imager__workdir}/installables/overlays

	for d in $(ls -A $src) ; do
		check_folder_free_space ${config_imager__workdir} $(( $(du -sb $src/"$d" | cut -f1) )) fail :
		verbose_do_or_die cp -a $src/"$d" ${config_imager__workdir}/installables/overlays
	done
}

#
# Copy tarballs from respective folders to respective folders. These will be overlaid using
# overlayfs on partitions with matching names.
# A more detailed explanation is in the flasher code
#
copy_installables_writableoverlays_tarballs() {
	local src=${distro__image_materials_installables_writableoverlays_dir}
	if [ ! -d "$src" ] ; then
		verbose "Skipping $FUNCNAME (no sources)"
		return
	fi
	info "Copying installable/writableoverlays"
	do_or_die rm -rf ${config_imager__workdir}/installables/writableoverlays
	do_or_die mkdir -p ${config_imager__workdir}/installables/writableoverlays

	for d in $(ls -A $src) ; do
		check_folder_free_space ${config_imager__workdir} $(( $(du -sb $src/"$d" | cut -f1) )) fail :
		verbose_do_or_die cp -a $src/"$d" ${config_imager__workdir}/installables/writableoverlays
	done
}

#
# Copy ext partition images to the respective folder.
# On the target, these will be dd-ed, tuned and resized and required by the flasher code
#
copy_ext_partition_images() {
	# staging (added 2025/05) This (hardlinking instead of copying) was never tested properly, so it is not an exported config option yet. TODO: if it catches, add it
	#					   	  it was mostly added to save space in /tmp and allow demonstrating things quickly without using non tmpfs storage
	#						  However, with large images, there is a risk of running out of space in tmpfs
	# 			              If this catches, add the logic to the prebuilts (which haven't been tested for a long long while now...)
	: ${config_imager__hardlink_ext_partition_images=false} # If true, will hardlink the images instead of copying them. This is useful for testing purposes, but not recommended for production

	if [ -d ${imager_workdir_installables_filesystem_images_path} ] ; then
                warn "Overwriting ${imager_workdir_installables_filesystem_images_path}"
	else
                do_or_die mkdir -p ${imager_workdir_installables_filesystem_images_path}
	fi

	if [ "${config_imager__installer_media_ext_partitions_from}" = "folders" ] ; then
		verbose "Copying images from ${config_imager__workdir_ext_partition_images}"
		for img in $(ls ${config_imager__workdir_ext_partition_images}/*.img 2>/dev/null) ; do
			if [ "${config_imager__hardlink_ext_partition_images}" = "true" ] ; then
				verbose "Hardlinking $img to ${imager_workdir_installables_filesystem_images_path}/"
				if ! ln $img ${imager_workdir_installables_filesystem_images_path}/ ; then
					warn "Failed to hardlink, you are probably no on the same partition. Reverting to copying"
					check_folder_free_space ${config_imager__workdir} $(( $(du -sb $img | cut -f1) )) fail :
					do_or_die cp -a $img ${imager_workdir_installables_filesystem_images_path}/
				fi
			else
				verbose "Copying $img to ${imager_workdir_installables_filesystem_images_path}/"
				check_folder_free_space ${config_imager__workdir} $(( $(du -sb $img | cut -f1) )) fail :
				do_or_die cp -a $img ${imager_workdir_installables_filesystem_images_path}/
			fi
		done
		# we could add more partitions here - put them (when creating) in a folder and then loop over all of them
	elif [ "${config_imager__installer_media_ext_partitions_from}" = "prebuilts" ] ; then
		verbose "Copying prebuilt images"
		for img in $(ls $config_imager__installer_media_ext_partitions_prebuilts_src_folder/*.img 2>/dev/null) ; do
			check_folder_free_space ${config_imager__workdir} $(( $(du -sb $img | cut -f1) )) fail :
			do_or_die cp -a $img ${imager_workdir_installables_filesystem_images_path}/
			# TODO: test code
		done
	fi
}

#
# Populates the installables/ directory. The flasher will flash materials from there
#
populate_removable_media_installables_directory() {
	info "populating the installable materials"
	if [ -d ${config_imager__workdir}/installables/bootfat ] ; then
		warn "Overwriting ${config_imager__workdir}/installables/bootfat"
	else
		mkdir -p ${config_imager__workdir}/installables/bootfat || fatalError "Failed to create the installable bootfat folder"
	fi

	# Copy the installable bootfs materials if they exist - this goes to the installables/bootfat
	info "populating the installable boot directory work files..."
	if [ -d "$distro__image_materials_installables_bootfs_dir" ] && [ ! "$(ls -A $distro__image_materials_installables_bootfs_dir)" = "" ] ; then
		check_folder_free_space ${config_imager__workdir} \
			$(( $(du -sb $distro__image_materials_installables_bootfs_dir | cut -f1) )) \
			fail \
			:
		verbose_do_or_die mcopy -snm $distro__image_materials_installables_bootfs_dir/*  ${config_imager__workdir}/installables/bootfat
	fi

	info_do_or_die copy_to_fat_installable_folders
	info_do_or_die copy_ext_partition_images
	info_do_or_die copy_installables_overlays_tarballs
	info_do_or_die copy_installables_writableoverlays_tarballs

	# May add BSP specific code here (although it is more likely that if a BSP needs something special it would override the entire mechanism)
}

#
# Populate the working directory. This will be the contents of everything that is common to
# an installer image, as well as an ota and recovery tarballs
#
populate_working_directory() {
	info "Will populate your media working directory at ${config_imager__workdir}"
	info_do_or_die populate_working_directory_with_boot_materials
	info_do_or_die populate_removable_media_installables_directory
	check_folder_free_space ${config_imager__workdir_ext_partition_images} 0 dontfail

	# May add BSP specific code here (although it is more likely that if a BSP needs something special it would override the entire mechanism)
}

#
# this could be done for additional images as well, could be hardlinked, or copied when populating the removable storage directory as well
# (it could be done in copy_ext_partition_images() for example)
# however, as this serves another purpose (of quick testing, or having a simpler live image with only system.img)
# we do it here in a one liner
#
create_livecd_image() {
	if [ -n "$config_bsp__qemu_livecd_storage_device_path" ] ; then
		verbose "Staging live image creation script - copying system image"
		if [ ! -d $(dirname "$config_bsp__qemu_livecd_storage_device_path") ] ; then
			do_or_die mkdir -p $(dirname "$config_bsp__qemu_livecd_storage_device_path")
		fi
		info_do_or_die cp $config_imager__workdir_ext_partition_images/system.img $config_bsp__qemu_livecd_storage_device_path

		if [ "$config_bsp__qemu_livecd_extract_system_overlays_into_live_image" = "true" \
		-a -d "$distro__image_materials_installables_overlays_dir/system" \
		-a ! "$(ls -A $distro__image_materials_installables_overlays_dir/system)" = ""  ] ; then
			info "Extracting overlays into the livecd image"
			local mountpoint=$(mktemp -d ${TMP_TOP}/wip-imager-livecd-XXX)
			if ! sudo mount -o loop,rw $config_bsp__qemu_livecd_storage_device_path $mountpoint ; then
				rm -rf $mountpoint
				fatalError "Failed to mount the livecd image"
			fi

			for f in $(ls -A $distro__image_materials_installables_overlays_dir/system 2>/dev/null) ; do
				warn "Extracting overlay $f into the livecd image"
				if ! sudo tar -xf $distro__image_materials_installables_overlays_dir/system/$f -C $mountpoint ; then
					sudo umount $mountpoint && rm -rf &mountpoint
					fatalError "Failed to extract overlay $f into the livecd image"
				fi
			done
			if ! sudo umount $mountpoint ; then
				rm -rf $mountpoint
				fatalError "Failed to unmount the livecd image"
			else
				rm -rf $mountpoint
			fi
			hardInfo "Livecd image is ready at $config_bsp__qemu_livecd_storage_device_path"
			hardVerbose "You may use the live image at $config_bsp__qemu_livecd_storage_device_path"
		fi
	fi
}
#
# Compresses the working directory.
# The result can be used as an OTA update tarball, or a compressed recovery image
# (we use the same design for everything except for a non A/B removable media installer)
#
# In a design of a single fat partition, one can create an installer image (without the digests/manifests), by
# simply extracting this tarball onto a fat image
#
compress_working_directory() {
	info "Compressing working directory..."
	# Compressing may take a while for large images. This is a good place to check if the user has enough disk space
	# and checking for the size of the uncompressed folder is a good way to do it
	check_folder_free_space $(dirname ${config_imager__workdir_compressed}) $(( $(du -sb ${config_imager__workdir} | cut -f1) )) fail :
	if [ "$imager_sparse_compression_workdir" = "true" ] ; then
		verbose "Creating a sparse archive"
		warn "Sparse archives are not supported by busybox!"
		verbose_do_or_die tar --sparse -I "xz -T0" -cf $config_imager__workdir_compressed -C $config_imager__workdir .
	else
		verbose "Not compressing with sparse files. This is busybox safe. Watch your disk space though."
		verbose_do_or_die tar -I "xz -T0" -cf $config_imager__workdir_compressed -C $config_imager__workdir . || fatalError "Failed to compress working directory"
	fi
}

#
# Creates the installer manifest file.
# This is used for a unified solution for A/B installer, recovery golden image and an OTA update
#
create_installer_manifest_and_digest_files() {
	digest_type=sha256
	digest_cmd=sha256sum
	digest_file=${config_imager__workdir_compressed}.digest
	manifest_file=${config_imager__workdir_compressed}.manifest
	blob=${config_imager__workdir_compressed}

	info "Updating $digest_type of compressed working directory tarball --> $digest_file"
	$digest_cmd $blob | cut -d ' ' -f 1 > $digest_file || fatalError "Failed to calculate $digest_type"

	blob_digest=$(cat $digest_file)
	blob_size=$(du -B 1 $blob | cut -f 1)
	compression_type=tar.xz

	original_blob_filename=$(basename $config_imager__workdir_compressed) || fatalError "Failed to get the basename of original_blob_filename config_imager__workdir_compressed"

	info "$digest_type is $blob_digest . You may put it in your installer.digest file if you create an installer"

	cat << EOF > $manifest_file
#
# Essential
#
blob_url=\$URL_OTA_SERVER_BASE/otafiles/full-ota-image.tar.xz
blob_size=$blob_size
compression_type=$compression_type
blob_digest=$blob_digest
digest_type=$digest_type
original_blob_filename=$original_blob_filename
blob_creation_date=$(date "+%Y-%m-%d--%H-%M-%S")

#
#
# livepatch, and non standard environment related.
# If update_type is "livepatch" then if misc_commands is not empty, they are run before (and perhaps instead of) the unpacking.
# If blob_download_path is not empty, the blob download directories/recommendations will be under this path
# if blob_extract_path is not empty, unpacking will be done to this place. This allows, for example, designing a system that does not require any information about the
# partition structure in the target, and in a way also implement clever "by hindsight" design (which is of course never recommended)
#
blob_download_path=
blob_extract_path=
update_type=fullota
#misc_commands=hardVerbose Hello from the manifest
misc=
on_done_commands=do_auto_reboot_after_flashing
#
# CIA (Confidentiality, Integrity, Authenticity)
#
blob_signature=
signature_type=
encryption_type=
signer_public_key=
EOF

	debug "There goes your manifest: \n$(cat $manifest_file)"
}

#
# Ccreate a removable media image.
# The structure will be one partition, and we will create on it one label.
# This can change depending on the hardware, livecd preparation, etc.
#
# we could calculate a more accurate image size, but this is a reasonable size to use, and if it gets too small
# the build will fail so one can know to increase it
#
# The function will assign the loopdev environment variable, which will be a loopback device
# associated with the fat partition.
#
# Error handling: since the entire build system is built in a relatively clean and robust way, that is meant
# to be easily readable, we will not change every single thing in the way things are done. This means, that
# the following variables need to be cleaned up in case of an error:
#  - loopdev
#  - config_imager__installer_image_file
#  - config_imager__installer_workdir
#
# This function handles it explicitly. For the next ones, we will not do it (we can save and restore the shell options if we want to,
# and remove set -e on other places, but it is not worth it now).
# Since we will continue having fatalError's at this point, it may be a good idea for the caller to clean them up,
# or to do explicit error handling that is a little bit less readable (e.g. call cleanup_loopback_devices_and_mounts() )
#
create_initial_installer_image_and_empty_filesystems() {
	case "$config_imager__installer_filesystem_type" in
		"fat")
			;;
		"*")
			fatalError "This packer packs a fat installer"
			;;
	esac

	local dst=$config_imager__installer_image_file
	sectors=$config_imager__installer_media_size_sectors
	startsector=$config_imager__installer_media_fat_label_start_sector
	bytespersector=512
	local bytes=$(($bytespersector*$sectors))
	local blocksize=$((1024*1024))
	local blockcount=$(($bytes/$blocksize))

	if [ ! -d $(dirname "$dst") ] ; then
		do_or_die mkdir -p $(dirname $dst)
	fi
	hardVerbose "Generating an installer image of size $(($bytes/1024/1024))MiB...\nWill be created at $dst and mounted at $config_imager__installer_workdir"

	check_folder_free_space $(dirname $dst) $(( $blocksize * $blockcount )) fail :
	verbose_do_or_die dd if=/dev/zero of=$dst bs=$blocksize count=$blockcount conv=sparse

	echo -e "n\np\n1\n${startsector}\n\n t\nc\nw\n" | fdisk $dst || fatalError "Failed to create partition table for installer"
	loopdev=$(losetup -f) || fatalError "Failed to find a loopdev"
	# You would usually use losetup -Pf on a file. We break it into two to show using losetup with offset.
	# If you are running inside docker, you may need to create loop control device nodes
	# Docker and loopback devices is a hate story, but I'm sure in time hacks will become more standardized
	do_or_die sudo losetup -o $(($startsector*$bytespersector)) $loopdev $config_imager__installer_image_file
	if ! sudo mkfs.vfat -n $config_imager__installer_media_fat_label $loopdev ; then
		sudo losetup -d $loopdev || warn "Failed to detach loop device $loopdev"
		fatalError "Failed to create a vfat filesystem on $loopdev"
	fi
	if ! sudo mount -o loop $loopdev $config_imager__installer_workdir ; then
		sudo losetup -d $loopdev || warn "Failed to detach loop device $loopdev"
		fatalError "Failed to mount the installer image at $config_imager__installer_workdir"
	fi
}

add_recovery_tarball_to_installer() {
	if [ ! "$config_imager__create_recovery_image" = "true" ] ; then
		warn "Will not create a recovery tarball"
		return
	fi

	info "Adding the OTA image as a recovery image"
	recovery_folder_on_installer_media=$config_imager__installer_workdir/installables/folders/$config_imager__recovery_partition_label
	local recovery_image_name=$(basename -s .tar.xz $(basename $config_imager__recovery_tarball)) || fatalError "Failed to get the basename of the recovery image"
	if [ -d $recovery_folder_on_installer_media ] ; then
		do_or_die sudo rm -rf $recovery_folder_on_installer_media
	fi
	do_or_die sudo mkdir -p $recovery_folder_on_installer_media
	do_or_die sudo cp $config_imager__recovery_tarball $recovery_folder_on_installer_media

	info "Adding the installer digest and manifest files to the recovery folder"
	if [ -f ${config_imager__workdir_compressed}.manifest ] ; then
		do_or_die sudo cp ${config_imager__workdir_compressed}.manifest $recovery_folder_on_installer_media/installer.manifest
	else
		# No point in making this if we really use the manifest and not just for debug
		hardWarn "Making up an installer.manifest  - this will be modified in case we do not compress (e.g.: manifest of files and digest on them)"
		echo "dummy_manifest" | sudo tee $recovery_folder_on_installer_media/installer.manifest || fatalError "Failed to populate dummy installer.manifest"
	fi

	if [ -f ${config_imager__workdir_compressed}.digest ] ; then
		do_or_die sudo cp ${config_imager__workdir_compressed}.digest $recovery_folder_on_installer_media/installer.digest
	else
		hardWarn "Making up an installer.digest file - this will be modified in case we do not compress (e.g.: manifest of files and digest on them)"
		echo "dummy_digest" | sudo tee $recovery_folder_on_installer_media/installer.digest || fatalError "Failed to populate dummy installer.digest"
	fi


	info "Done creating the recovery image for $recovery_image_name"
}


compress_installer_image() {
	if [ ! "$config_imager__compress_installer_image" = "true" ] ; then
		return
	fi
	info "Compressing installer image... "
	verbose_do_or_die tar --sparse -I "xz -T0" -cf $config_imager__installer_image_file_tarball $config_imager__installer_image_file
	info "Installer compressed sha256sum is: $(sha256sum $config_imager__installer_image_file_tarball)"
}

#
# Create the installer image. You can dd this installer into a removable media, or attach it
# to an emulator as a removable media
#
# Note that since this includes mounting a loopback device, sudo is necessary (or the relevant capability)
#
do_create_installer_image() {
	if [ ! "$config_imager__create_installer_image" = "true" ] ; then
		return
	fi

	info "Creating the installer image at $config_imager__installer_image_file"
	info "The installer workdir is $config_imager__installer_workdir"

	if mountpoint $config_imager__installer_workdir &>/dev/null ; then
		warn "$config_imager__installer_workdir was already mounted"
		do_or_die sudo umount $config_imager__installer_workdir
	fi

	do_or_die mkdir -p $config_imager__installer_workdir
	if [ ! "$(ls -A $config_imager__installer_workdir)" = "" ] ; then
		fatalError "$config_imager__installer_workdir is not empty. Will not risk creating an installer image for you"
	fi

	verbose_do_or_die create_initial_installer_image_and_empty_filesystems

	info "Copying workdir over to install dir and adding to it the digest and manifest of the compressed workdir tarball"
	# for the installer image - we usually target smaller filesystems, and use the "huge ones" directly on storage
	# however, if you find yourself preparing a huge image (e.g. with graphics), you definitely want to modify the
	# default size the installer image (in sectors) - config_imager__installer_media_size_sectors
	check_folder_free_space ${config_imager__installer_workdir} $(( $(du -sb ${config_imager__workdir} | cut -f1) )) fail cleanup_loopback_devices_and_mounts
	if ! verbose_do sudo mcopy -snm ${config_imager__workdir}/* ${config_imager__installer_workdir}/ ; then
		cleanup_loopback_devices_and_mounts
		fatalError "Failed to copy the working directory to the installer working directory"
	fi

	if [ -f ${config_imager__workdir_compressed}.manifest ] ; then
		if ! verbose_do sudo cp ${config_imager__workdir_compressed}.manifest $config_imager__installer_workdir/installer.manifest ; then
			cleanup_loopback_devices_and_mounts
			fatalError "Failed to copy the installer manifest file to the installer working directory"
		fi
	else
		# No point in making this if we really use the manifest and not just for debug
		hardWarn "Making up an installer.manifest  - this will be modified in case we do not compress (e.g.: manifest of files and digest on them)"
		echo "dummy_manifest" | sudo tee $config_imager__installer_workdir/installer.manifest || fatalError "Failed to populate dummy installer.manifest"
	fi

	if [ -f ${config_imager__workdir_compressed}.digest ] ; then
		if ! verbose_do sudo cp ${config_imager__workdir_compressed}.digest $config_imager__installer_workdir/installer.digest ; then
			cleanup_loopback_devices_and_mounts
			fatalError "Failed to copy the installer digest file to the installer working directory"
		fi
	else
		hardWarn "Making up an installer.digest file - this will be modified in case we do not compress (e.g.: manifest of files and digest on them)"
		echo "dummy_digest" | sudo tee $config_imager__installer_workdir/installer.digest || fatalError "Failed to populate dummy installer.digest"
	fi

	if ! verbose_do add_recovery_tarball_to_installer ; then
		cleanup_loopback_devices_and_mounts
		fatalError "Failed to add the recovery tarball to the installer"
	fi

	cleanup_loopback_devices_and_mounts

	info "You can use this as your installation media: $config_imager__installer_image_file"

	# This is done here, because compression takes time. In the meantime, the user can happily test the installer image
	verbose "Next steps are digest calculation on the installer and optional compression, in case you want to upload the artifacts. Otherwise you can comment out the lines"
	# We are essentially done. The installer image digest calculation and compression
	# are optional, and are useful in case you would like to send them to someone.
	# Calculating the digest can take a while, depending on the size of your image
	info "Installer sha256sum is $(sha256sum $config_imager__installer_image_file)"
	do_or_die compress_installer_image # not showing a message because it will likely not be called
}

#
# Initialize environment variables that are used but are not configuration variables
#
# Some examples and rationale:
# Working directories and images - we know we want to work in tmpfs because it's faster,
# and because we do not want to override images unless everything is OK, so we don't want to work directly
# on the final images.
#
init_env() {
	: ${workimg_installer_path=${TMP_TOP}/workimg-installer.img}
	: ${imager__delete_workimg_system=false}
	: ${imager__delete_workdir_ota=false}
	: ${imager__delete_workimg_installer=true} # it's ok to not delete it but it would be re-imaged if so
	: ${imager__delete_workdir_installer=true} # it's ok to not delete it but it would be re-imaged if so

	: ${config_imager__workdir_compressed="${TMP_TOP}/PSCGINSTALL.tar.xz"} # path of the output file of the compressed working directory
	: ${imager_sparse_compression_workdir=false}			# set to true only if you are sure you don't want to unpack with busybox, and gain better disk usage ratio of the extracted contents (assumming you compress the tarball)


	: ${config_imager__workdir_ext_partition_images=${TMP_TOP}/wip-images}			# The system partition will be packed into this ext image

	: ${imager_system_img_name=system.img}		# The name of the rootfs image (or the lower part of it in case of overlayfs)
	imager_workdir_installables_filesystem_images_path=${config_imager__workdir}/installables/ext4images

	# Check that the build materials are in tact
		### Check that source directories exist
	if [ ! -d "$distro__image_materials_installables_bootfs_dir" ] ; then
		fatalError $distro__image_materials_installables_bootfs_dir does not exist
	fi
	if [ ! -d "$distro__image_materials_installables_system_dir" ] ; then
		fatalError $distro__image_materials_installables_system_dir does not exist
	fi

	case ${config_imager__installer_media_ext_partitions_from} in
		folders)
			;;
		prebuilts)
			if [ ! -d "$config_imager__installer_media_ext_partitions_prebuilts_src_folder" ] ; then
				fatalError You must provide a source folder for the prebuilts
			fi
			fatalError "images from prebuilts is not yet supported, although it's easy to add (for now)"
			;;
		*)
			fatalError "Unsupported option"
			;;
	esac
}

init_directory_structure() {
	### Verify target directories, and remove or keep them according to configuration flags

	# Create the parent directory of the  compressed workdir artifacts (e.g. ota or recovery golden image tarball) if needs to
	if [ ! -d $(dirname $config_imager__workdir_compressed) ] ; then
		info "Directory for $config_imager__workdir_compressed did not exist. creating it for you"
		mkdir -p $(dirname $config_imager__workdir_compressed) || fatalError "Failed to create directory"
	fi

	# Create the parent directory of the installer image artifacts if needs to
	if [ ! -d $(dirname $config_imager__installer_image_file) ] ; then
		info "Directory for $config_imager__installer_image_file did not exist. creating it for you"
		mkdir -p $(dirname $config_imager__workdir_compressed) || fatalError "Failed to create directory"
	fi

	# The installer creates images out of folders (e.g. system.img). This is where they are stored. Cleanup if need be
	if [ -d "$config_imager__workdir_ext_partition_images" ] ; then
		if [ "$config_imager__installer_workdir_start_from_scratch" = "true" ] ; then
			warn "$config_imager__workdir_ext_partition_images existed. deleting previous contents and restarting from scratch"
			do_or_die sudo rm -rf $config_imager__workdir_ext_partition_images

			do_or_die sudo rm -rf $config_imager__workdir_ext_partition_images
			do_or_die mkdir $config_imager__workdir_ext_partition_images
		else
			warn "$config_imager__workdir_ext_partition_images existed. we assume that you know what you are doing!"
		fi

	else
		verbose_do_or_die mkdir -p $config_imager__workdir_ext_partition_images
	fi

	# The imager works on the workdir before compressing it. Cleanup if need be
	if [ -d "$config_imager__workdir" ] ; then
		if [ "$config_imager__installer_workdir_start_from_scratch" = "true" ] ; then
			warn "$config_imager__workdir existed. deleting previous contents and restarting from scratch"
			do_or_die sudo rm -rf $config_imager__workdir
			do_or_die mkdir $config_imager__workdir
		else
			warn "$config_imager__workdir existed. we assume that you know what you are doing!"
		fi
	else
		verbose_do_or_die mkdir -p $config_imager__workdir
	fi
}

# a trivial printing function
bytes_to_mibs() {
	echo $(($1/1024/1024))
}


#
# Does the actual creation of the partition accodring to the tunables
# $1: target image path
# $2: label to set
# $3: required size
# $4: filesystem type (e.g. ext4)
# $4-: tunables
#
#
create_empty_filesystem() {
	local bs=4096
	local image=$1
	local label=$2
	local size=$3
	local fstype=$4
	shift 4
	local tunables="$*"
	local count=$(( (4096+$size)/4096))
	printvars image label size fstype tunables count
	debug "Will create an image of size $((count * $bs)) ( $(($count*$bs - $size)) extra bytes for integral block count)"
	check_folder_free_space $(dirname $image) $((count*$bs)) fail :
	verbose_eval_or_die dd if=/dev/zero of=$image bs=$bs count=$count
	verbose_do_or_die mkfs.$fstype $tunables -L $label $image
}

#
# Creates an empty image file trying to estimate the required size for a partition automatically, unless otherwise specified by a configuration option
#
# $1 source folder to populate the ext image with its contents
# $2 target image path
# $3 label to set
#
# ext4 is an example. the tunables REALLY depends on your usage. Tuning is an art. Our main objective here is to make the system as
# tight as possible. If the target partition has more space, it will be resized. However, the inode tunables are fixed ones they are set
# There are many things that affect the tunables, and in general a 3% overhead would be considered as very good.
# Setting the reserved block to 0 saves space, but then if you have a full disk space, you are not guaranteed to be able to fsck
# On the other hand, if it is read only, you don't really need to
# And so on, and so on, and so the discussion goes...
# Bottom line: Tuning is an art, and "preoptimization is the root of all evil"
#
create_empty_ext_filesystem_for_folder() {
	local folder=$(readlink -f $1)
	local image=$2
	local label=$3
	info "Creating and formatting image file for $label: $folder --> $image"
	local size_bytes_var=$(get_compound_var config__imager__ext_partition_${label}_size_bytes)
	local tunables_options_var=$(get_compound_var imager__ext_partition_${label}_tunables_options)
	if [ -n "${size_bytes_var}" ] ; then
		# This is the less preferred option, but if you really want to set a fixed size, you can. We will ignore checking
		# the folder size, or any other calculations in this case, as it may speed up the build, and you may know better
		verbose "You have specified a fixed size for the $label partition: ${size_bytes_var} bytes, and are not willing to compromise."
		verbose_do_or_die create_empty_filesystem $image $label $size_bytes_var ext4 $tunables_options_var
		return 0
	fi
	local folder_size_bytes=$(sudo du -sb $folder | cut -f 1)
	local scale_factor_var=$(get_compound_var config_imager__ext_partition_${label}_size_scale_factor)
	local minimum_size_bytes_var=$(get_compound_var config_imager__ext_partition_${label}_minimum_size_bytes)
	local estimate=$(printf "%.f" $(echo "$folder_size_bytes * ${scale_factor_var} + 0.5" | bc ))
	local diff=$(($estimate - $folder_size_bytes))
	debug
	local debug_msg="Folder size: $(bytes_to_mibs $folder_size_bytes)MiB --> partition image estimate:  $(bytes_to_mibs $estimate)MiB, diff: $diff bytes, $(bytes_to_mibs $diff)MiB"
	debug "$debug_msg"
	# the next debugging statement will not go to the log file, but will make it clearer on the eyes for an educational session
	local printvars_msg=$(printvars folder_size_bytes estimate scale_factor_var minimum_size_bytes_var size_bytes_var tunables_options_var)

	if [ $estimate -lt "${minimum_size_bytes_var}" ] ; then
		warn "The folder size is too small for a filesystem. Using ${minimum_size_bytes_var} instead of $estimate"
		estimate=${minimum_size_bytes_var}
	fi

	verbose_do_or_die create_empty_filesystem $image $label $estimate ext4 $tunables_options_var
	# The next lines are meant to help those who do not scroll up, in case the estimation and/or the scale factor were not enough, which is very likely when trying to be too optimize agressively
	STRING_ERROR_MESSAGE_CALCULATION_HELPER="$debug_msg\n$printvars_msg"
}

# $1 source folder to populate the ext image with its contents
# $2 target image path
# $3 tmp image file indicator (doesn't really matter, but for things to look nice if you want to build several partitions in parallel)
copy_folder_to_partition_image() {
	local folder=$(readlink -f $1)
	local image=$2
	local label=$3
	local mountpoint=$(mktemp -d ${TMP_TOP}/wip-imager-$label-XXX)

	verbose_do_or_die sudo mount -o loop $image $mountpoint
	# Copy flags: flags: P - do not derefernece links,  T - copy contents, not folder name, r - recursive, a - like r but preserves all attributes (however for the example I am more specific, and omitting timestamps and context)
	if ! verbose_do sudo cp -PTr --preserve=mode,ownership,links,xattr $folder $mountpoint ; then
		hardError "Failed to populate $folder --> $image  (mountpoint: $mountpoint)"
		error "Please OBSERVE the tunables and stats below. The debugging message is for you - use it!"
		debug "It is likely because your tunable are not adequate for the folder size and filesystem metadata. There goes some info:\n$STRING_ERROR_MESSAGE_CALCULATION_HELPER"
		sudo umount $mountpoint || fatalError "Failed to unmount $mountpoint"
		rmdir $mountpoint || fatalError "Failed to remove $mountpoint"

		fatalError "Your image could work, but it would be more luck than judgement. Refusing to let you waste your best years on pointless debugging"
	fi

	# Some stats
	local size=$(df -h $mountpoint  | tail -1 | tr -s " " | cut -d' ' -f 2)
	local used=$(df -h $mountpoint  | tail -1 | tr -s " " | cut -d' ' -f 3)
	local available=$(df -h $mountpoint  | tail -1 | tr -s " " | cut -d' ' -f 4)
	local usedpercentage=$(df -h $mountpoint  | tail -1 | tr -s " " | cut -d' ' -f 5)

	do_or_die sudo umount $mountpoint
	do_or_die rmdir $mountpoint

	verbose "Your $label image file is in $image. Some stats: size=$size, used=$used, available=$available usedpercentage=$usedpercentage"
}

#
# $1 source folder to populate the ext image with its contents
# $2 target image path
# $3 label to set
create_ext_partition_image_from_folder() {

	local folder=$(readlink -f $1)
	local image=$2
	local label=$3

	if [ -z "$folder" -o -z "$image" -o -z "$label" ] ; then
		fatalError "you must provide a source folder, destination image path, and label to create the partition image"
	fi

	STRING_ERROR_MESSAGE_CALCULATION_HELPER="" # This is useful for those who don't scroll up to see why imaging activities fail (you know who you are, you are welcome...)
	create_empty_ext_filesystem_for_folder $folder $image $label
	copy_folder_to_partition_image $folder $image $label
}

#
# create ext partitions from folders.
# This wraps the logic that calculates the size to allocate to each such image. Since tunables are art,
# and per project dependent (e.g. inode size, number of inodes, journal type, reserved size, etc.), we
# separate the implementation to another file so it is easier to discuss it separately in time
#
# The important thing is, and it happens in every build system, that if the size is too small, you may
# not pack the image, and if it is too big, you may end up wasteful, especially with read only file systems
# that don't need the space.
#
do_create_ext_partition_images_from_folders() {
	if [ ! "${config_imager__installer_media_ext_partitions_from}" = "folders" ] ; then
		return
	fi

	init_env_ext_partition_tunables
	if [ "$(ls -A $distro__image_materials_installables_system_dir)" = "" ] ; then
		if  [ ! "$config_imager__allow_missing_system_installation" = "true" ] ; then
			fatalError "Refusing to allow an image without system.img"
		else
			warn "There is nothing to pack into the system image. Skipping"
			return
		fi
	fi

	do_or_die create_ext_partition_image_from_folder $distro__image_materials_installables_system_dir $config_imager__workdir_ext_partition_images/system.img system

	# could create other partitions images as well, but the are optional and per system designed
}

#
# Check the free space on the folder.
# $1 path to the folder
# $2 minimum expected free space in bytes. 0 if don't care. doesn't have to be exact, but should be an estimation of the minimum space required
# $3 if set to "fail" the script if the folder does not have enough space (estimation.). This can be useful for saving some time and failing
#    faster if the target folder (storage or tmpfs) is not big enough. You may reduce the parameter to give it a chance anyway
#    Any other string will be ignored
#
# $4 callback function to call if the check fails, $2 is not 0, and $3 is set to "fail"
check_folder_free_space() {
	local size=$(df -h $1  | tail -1 | tr -s " " | cut -d' ' -f 2)
	local used=$(df -h $1  | tail -1 | tr -s " " | cut -d' ' -f 3)
	local available=$(df -h $1  | tail -1 | tr -s " " | cut -d' ' -f 4)
	local usedpercentage=$(df -h $1  | tail -1 | tr -s " " | cut -d' ' -f 5)
	local available_bytes=$(df -B1 $1  | tail -1 | tr -s " " | cut -d' ' -f 4)

	verbose "Checking if $1 has enough space for $2 bytes (otherwise, behavior is set to $3)"
	debug "Some df stats for $1 size=$size, used=$used, available=$available usedpercentage=$usedpercentage"

	if [ "$3" = "fail" ] ; then
		if [ "$available_bytes" -lt "$2" ] ; then
			local diff_available_bytes=$(($available_bytes - $2))
			if [ -n "$4" ] ; then
				warn "Not enough space in $1. Available: $available_bytes, required: $2 [diff: $diff_available_bytes ($(( $diff_available_bytes/1024/1024 ))MiB)]"
				$4
			fi
			fatalError "Not enough space in $1. Available: $available_bytes, required: $2 [diff: $diff_available_bytes ($(( $diff_available_bytes/1024/1024 ))MiB)]"
		fi
	fi
}

display_friendly_ota_serving_instructions() {
	local ota_project_src=$config_toplevel__oot_dir/ota-update-richos
	info "You may now start serving OTA images. For your convenience, you can use something like
	( cd $ota_project_src ; workdir=/tmp/PscgBuildOS-otaserver-example/otafiles blob=$config_imager__workdir_compressed manifest=$manifest_file ./hostfiles/test/ota-server.sh  fullota )
	"
}

create_ota_recovery_and_installer_images() {
	if [ ! "$config_imager__create_ota_image" = "true" ] ; then
		warn "Will not compress working directory. Will not create OTA, recovery and installer images"
		return
	fi

	info_do_or_die compress_working_directory

	info_do_or_die create_installer_manifest_and_digest_files

	display_friendly_ota_serving_instructions # This is absolutely for the convenience of a developer

	info_do_or_die do_create_installer_image
}

do_create_partition_images_from_folders() {
	# Use ext4 partitions. You can modify it as you see fit
	do_create_ext_partition_images_from_folders
}

main() {
	init_env
	init_directory_structure

	info_do_or_die do_create_partition_images_from_folders
	info_do_or_die populate_working_directory

	info_do_or_die create_livecd_image 						# read comments inside
	info_do_or_die create_ota_recovery_and_installer_images # all have common mechanisms

	info "done."
}


#
# Cleanup mounts and loopback devices for the next time the script is run
#
cleanup_loopback_devices_and_mounts() {
	verbose "Cleaning up..."
	rc_cleanup=0
	if mountpoint "$config_imager__installer_workdir" &>/dev/null ; then
		sudo umount $config_imager__installer_workdir || rc_cleanup=1
	fi
	if [ -n "$loopdev" ] && losetup $loopdev &>/dev/null ; then
		sudo losetup -d $loopdev || rc_cleanup=1
	fi
	if [ -d "$config_imager__installer_workdir" ] ; then
		sudo rm -rf $config_imager__installer_workdir || rc_cleanup=1
	fi
	return $rc_cleanup
}

commonScriptPrologueLogRunAndEpilogue $@