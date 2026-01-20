# Reusing build materials
The objectives of this document, and mechanisms are:
- Integrating things that have already been built by our bulid system to speed up subsequent builds, built on them, and not having to redo activities (e.g. rootfs, kernel, etc.). This allows for reusing artifacts, modifying some files and just repacking them (but keeping them in a different place of the build), etc.
- Getting components from other builds (e.g. a rootfs image, an abootimg, etc.) and reusing them in the system as a some sort of prebuilts

This is not being done for every component, but it is relatively easy to extend.

Unfortunately, at the time of writing, not every existing implementation is published (most notably: specific boards U-Boot builds, and abootimg). This comment serves as a hint of what this mechanism can be really useful for.

## Code

```
main_build_distro()
  ==> build_distro_reuse_materials_wrapper
    ==> init_env_reuse_materials()
    ==> reuse_build_materials()
	  ==> # depedning on config_buildtasks... values
	      # multiple calls to remove_target_and_link_if_src_exists()
  ==> build_distro_reuse_build_src_and_arch_wrapper()
```

The important differences are:
- `build_distro_reuse_materials_wrapper` - reuses materials from other directories, all must be under `${config_distro__prebuilt_image_materials_workdir}`. If it is unset, then the mechanism returns, and nothing is reused.
  - This means that you would want to set your prebuilts up, by either copying them there, or linking.
  - There is a thought about changing this out of convenience, and allow arbitrary component inclusion
    - This thought is mostly for resuing image files (E.g. ext4, btrfs etc. images) without unpacking them first
- `build_distro_reuse_build_src_and_arch_wrapper` is responsible for having the *shared sources* (e.g. downloaded and checked out commit of a Linux kernel, or the untarred contents of it etc.) and the *shared arch* (e.g. a Linux kernel build for the same architecture, with the same cross compiler, or the same for busybox, etc.) taken care of, to allow reusing them in different builds (e.g. use the same kernel/busybox for *PscgDebOS*, *PscgBusyboxOS*, etc.).

In the nominal case you are not supposed to touch or care about any of these.
The next section, will cover some of the use cases and environment variables for you to configure to reuse images.


Do note that if you extend or add things, you want to make sure that the respective `config_buildtasks...` are unset - as they will take precedence over reusing materials. You can see this clearly in `reuse_build_materials()`.

Another useful variable is `config_imager__allow_missing_system_installation` - in case you want to reuse some things, without a system.img (e.g. to quickly test a ramdisk, and another partition of your own perhaps, or 9p/nfs mount it, or any other idea you may have). This can save a lot of time in packing and installing an image you may not even need

## Reusing materials - distro_reuse_materials.buildconfig
The idea is simple. Instead of using `distro__image_materials_installables_...`, use `distro__prebuilt_image_materials_installables_...` and use the `${config_distro__prebuilt_image_materials_reusing_method}` strategy for copying or linking.

Then, the respective materials are packed during the *imager* tasks.
An important addition, is that if you use qemu (or otherwise prepare an image file on build time, with the emmc partitions):
- You want to make sure that `config_bsp__qemu_storage_device_size_mib` is at least as big as whatever is expected to be installed.
- You can (but don't have to) provide `distro__prebuilt_partitions_emmc_config_file_for_imager_estimation` to provide a partition definition files, for tests (@see *generate-qemu-scripts.sh*'s `decide_storage_device_size_by_image_materials_or_partition_sizes()`).
- If you provide such a file, you can copy it from the ramdisk, or if you previously built the ramdisk yourself (but don't pack it now, otherwise you can ignore these comments altogether), you can take the file from `$RAMDISK_DIR/flasher/config/partitions-emmc.config`.

Since the logic is quite simple and self contained, the code is presented to you as part of the documentation. It will likely not be updated in the documentation, and may be removed:
```bash
init_env_reuse_materials() {
	if [ ! -d "$config_distro__prebuilt_image_materials_workdir" ] ; then
		return # Nothing to do
	fi

	if [ -z "$config_distro__prebuilt_image_materials_reusing_method" ] ; then
		fatalError "If you wish to reuse, you must provide config_distro__prebuilt_image_materials_reusing_method=<copy|symlink|hardlink>"
	fi


	export distro__prebuilt_image_materials_installables_workdir=$config_distro__prebuilt_image_materials_workdir/installables
	export distro__prebuilt_image_materials_removable_media_specifics_dir=$config_distro__prebuilt_image_materials_workdir/removablemedia_specifics

	export distro__prebuilt_image_materials_installables_folders_dir=$distro__prebuilt_image_materials_installables_workdir/installables/folders
	export distro__prebuilt_image_materials_installables_overlays_dir=$distro__prebuilt_image_materials_installables_workdir/installables/overlays
	export distro__prebuilt_image_materials_installables_writableoverlays_dir=$distro__prebuilt_image_materials_installables_workdir/installables/writableoverlays

	export distro__prebuilt_image_materials_installables_bootfs_dir=$distro__prebuilt_image_materials_installables_workdir/bootfat
	export distro__prebuilt_image_materials_installables_system_dir=$distro__prebuilt_image_materials_installables_workdir/ext4images/${distro__identifier_name}/system

	export config_distro__prebuilt_image_materials_reusing_method # don't set a default value for it

	# This is used only for the imager, to allow for calculateing the required storage size
	# You do not have to provide it, as there are other mechanisms to calculate the required size
	# Do note that whatever you provide in this file, is not consulted at runtime, as there is the respective definition in the ramdisk (or wherever the flasher is implemented)
	: ${distro__prebuilt_partitions_emmc_config_file_for_imager_estimation=$config_distro__prebuilt_image_materials_workdir/partitions-emmc.config}
	export distro__prebuilt_partitions_emmc_config_file_for_imager_estimation
}

reuse_build_materials() {
	if [ ! -d "$config_distro__prebuilt_image_materials_workdir" ] ; then
		return # Nothing to do
	fi

	if [ ! "$config_buildtasks__do_build_rootfs" = "true" ] ; then
		debug_do_or_die remove_target_and_link_if_src_exists $distro__prebuilt_image_materials_installables_system_dir $distro__image_materials_installables_system_dir $config_distro__prebuilt_image_materials_reusing_method sudo
	fi

	# For the boot materials, we will require an "all or nothing". Currently only for ramdisk, kernel and bootloader(s),
	# but one could test for the rest as well
	if [ ! "$config_buildtasks__do_build_ramdisk" = "true" -a ! "$config_buildtasks__do_build_kernel" = "true" -a ! "$config_buildtasks__do_build_bootloaders" = "true" ] ; then
		# The installable bootfs dir
		debug_do_or_die remove_target_and_link_if_src_exists $distro__prebuilt_image_materials_installables_bootfs_dir $distro__image_materials_installables_bootfs_dir $config_distro__prebuilt_image_materials_reusing_method
		# The removable media specifics - this is an optional folder, which may be empty, so don't force it
		debug_do_or_die remove_target_and_link_if_src_exists $distro__prebuilt_image_materials_removable_media_specifics_dir $distro__image_materials_removable_media_specifics_dir $config_distro__prebuilt_image_materials_reusing_method $config_distro__prebuilt_image_materials_reusing_method dontforce
	fi

	debug_do_or_die remove_target_and_link_if_src_exists $distro__prebuilt_image_materials_installables_folders_dir $distro__image_materials_installables_folders_dir $config_distro__prebuilt_image_materials_reusing_method dontforce

	debug_do_or_die remove_target_and_link_if_src_exists $distro__prebuilt_image_materials_installables_overlays_dir $distro__image_materials_installables_overlays_dir $config_distro__prebuilt_image_materials_reusing_method dontforce

	debug_do_or_die remove_target_and_link_if_src_exists $distro__prebuilt_image_materials_installables_writableoverlays_dir $distro__image_materials_installables_writableoverlays_dir $config_distro__prebuilt_image_materials_reusing_method dontforce
}
```
## Reusing an existing or a packed image from another distro
Since our system takes care of preparing the images and partitioning, and is heavily used in *modifying* images from other build systems, to make it easier, we always repack.

An exception to that is something that is not yet published, and good chances it will not be published (if there is a lot of interest, it will just be rewritten).


