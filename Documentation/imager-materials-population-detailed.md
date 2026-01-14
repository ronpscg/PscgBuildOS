# Images materials population - how the materials that go into the images are gathered and packed
While each of the components (*kernel*, *initramfs*, *rootfs*, etc.) is created separately on the hosts file system, the imager's responsibility is to pack them onto flashable and/or bootable and/or runnable images on the respective targets.
This has been done using a unified design, for which the flasher code (in the ramdisk/initramfs, unless you port it to another component of your choice), knows how to handle multiple flashing/reflashing scenarios.

The image materials themselves are divided into several groups:
- Materials that should only find themselves on an installation media (e.g. if you want to have different U-Boot environment for a removable media, than the one you would have on your persistent storage). They are mostly denoted as **removable_media**.
- Materials that are **installables** - meaning they will be directly flashed onto the persistent storage and are roughly divided between what is part of your *richos* (e.g. partition scheme for everything related to your *rootfs* operation), and those that have to do with the boot (e.g. U-Boot, maybe UEFI, maybe early firmware, probably the kernel image and the ramdisk image themselves, unless you opt to put them in an ext4 partition or the like, etc.)

This document elaborates things that are well documented in the code. Yet, it can help you to navigate in them more quickly.
The format here will be a bit different than in the other documents, mostly to save the writer time.

We will be discussing the first two functions of the following code excerpts:

make-installer-ota-recovery-images.sh main():
```
  ...
  ==> do_create_partition_images_from_folders()
  ==> populate_working_directory()
  ==> create_livecd_image()
  ==> create_ota_recovery_and_installer_images()
```


While the following examples are all ext4, simple adjustments throughout the build system as well as the flasher (in ramdisk code) can make you use any partition format and any file system of your choice. Also, mostly the *system* partition is addressed. With minor changes, you can prepopluate any other partition/image as you wish (there is an "easier" mechanism for that though, using the `folders` construct on the flasher, that just copies a folder contents to its respective partition label.

## Some variables used
Prior to that, you are welcome to see *pscg_linux.buildconfig* for some important variable definitions. Some excerpts:
```bash
export distro__image_materials_workdir=$BUILD_DIR/image_materials_workdir

export distro__image_materials_installables_workdir=$distro__image_materials_workdir/installables
export distro__image_materials_removable_media_specifics_dir=$distro__image_materials_workdir/removablemedia_specifics

export distro__image_materials_installables_folders_dir=$distro__image_materials_workdir/installables/folders
export distro__image_materials_installables_overlays_dir=$distro__image_materials_workdir/installables/overlays
export distro__image_materials_installables_writableoverlays_dir=$distro__image_materials_workdir/installables/writableoverlays

export distro__image_materials_installables_bootfs_dir=$distro__image_materials_installables_workdir/bootfat

export distro__image_materials_installables_system_dir=$distro__image_materials_installables_workdir/ext4images/${distro__identifier_name}/system

: ${config_distro__prebuilt_image_materials_workdir=""}
export config_distro__prebuilt_image_materials_workdir

# The following variables are used within the builder code, in several places, and so are assigned more "standard" names
# (so it is easy to look at and discuss)"
BOOT_DIR=$distro__image_materials_installables_bootfs_dir
ROOTFS_DIR=$distro__image_materials_installables_system_dir
REMOVABLE_MEDIA_SPECIFICS_DIR=$distro__image_materials_removable_media_specifics_dir
```

## More about beavior changing variables
You will see other important variables in other *.buildconfig* files, such as `RAMDISK_DIR` in *ramdisk.buildconfig* and more.
**Note: I do want to refactor a lot of the variable locations, and maybe conventions, so this might become obsolete. In general, my intention was that things that are strictly related to the component building, will get names that could make them easily separable from the build system itself, and would be more easily observable (capital cases) and readable (concise names)**

These excerpts tell a lot. When the different components are built, they will likely populate each of its own.
Let's look deeper into some of the functions that use these variables and more, when populating the image materials on `${config_imager__workdir}`(which will be packed into the *OTA tarball*):

An interesting exception is `${config_distro__prebuilt_image_materials_workdir}`, which if set, enables to reuse materials from another build, and possibly operating system build. So it practice, it can allow you to incorporate AOSP materials, Yocto Project materials, and so, into the build system. You can see the usage of it in the places that consider `${config_imager__installer_media_ext_partitions_from}`:
- If it's set to *folders* - the images are copied (or hardlinked, depending on `${config_imager__hardlink_ext_partition_images}`)  from `${config_imager__workdir_ext_partition_images}/*.img` to `${config_imager__workdir}/installables/ext4images/`
- Otherwise, they are copied from `${config_imager__installer_media_ext_partitions_prebuilts_src_folder}/*.img` to the same folder, `${config_imager__workdir}/installables/ext4images/`

You can see this logic in `copy_ext_partition_images()`

## About the file system tunables
Tuning file system sizes and features is a mastery. You can look at some of the variables as they are (currently) described in `init_env_ext_partition_tunables()`. While The tunables are for *ext4* and you can devise the logic for other file system types from there, and your knowledge of the respective file system.

Some values you may want to set in your enviroment variables prior to building an image:
- `config_imager__ext_partition_system_size_scale_factor` - by how much to multiply the size of the `${distro__image_materials_installables_system_dir}`. This is important if you don't provide the size of it yourself
- `config__imager__ext_partition_system_size_bytes`  - if set - this will be the partition size, to be exactly it. If it is too small - it is up to you to fix it - which is why it is not recommended
- `config_imager__ext_partition_system_minimum_size_bytes` - this will be the minimum recommeded size to use, regardless of the size calculation (including the *scale factor*) of the folder that is packed. Specifying it can be useful if you know how big you want the filesystem to be, e.g. if you want to have some free space in it too (which is hardly ever not a good idea)

### Code examples


#### Creating the file system images and materials - some examples


##### do_create_ext_partition_images_from_folders()

```
  ==> do_create_partition_images_from_folders()
    ==> do_create_ext_partition_images_from_folders()
```


We will briefly go through the *system.img* journey:
- In `create_ext_partition_image_from_folder()`, the *system.img* is packed from the folder `${distro__image_materials_installables_system_dir}` into `${config_imager__workdir_ext_partition_images}/system.img`, with filesystem tunables affected by the configuration variables listed in `init_env_ext_partition_tunables()`.\
  An example of such paths, can be:
  `.../build/target/product/pscg_busyboxos/build-loongarch/image_materials_workdir/installables/ext4images/pscg_busyboxos-loongarch/system` that would be packed into  `.../tmp/PscgBuildOS/staging-loongarch/wip-images/system.img`
  - This will happen unless someone opted to not create the rootfs (e.g. skipped the respective buildtask), and set `${config_imager__allow_missing_system_installation}` to true.
  - The tunables are for *ext4* and you can devise the logic for other file system types from there, and your knowledge of the respective file system.


```
  ==> do_create_ext_partition_images_from_folders()
    ==> create_ext_partition_image_from_folder()
      ==> create_empty_ext_filesystem_for_folder()
        ==> create_empty_filesystem()
          ==> dd ...
          ==> mkfs ...
      ==> copy_folder_to_partition_image()
```

At the end of this process, unless `${config_imager__installer_media_ext_partitions_from}" = "folders"`, you the contents will be created
into  `${config_imager__workdir_ext_partition_images}`, for example `.../tmp/PscgBuildOS/staging-riscv/wip-images`.

Since these are temporary, it is fine to not use a per architecture `config_imager__workdir_ext_partition_images` variable, and it can save space.
There are all kinds of optimizations that at this point I will try to not detail, because writing the documentation is taking a considerable time, and if it is too long, it will get more challenging to read (and: everything is very well explained and documented in the code!).



##### populate_working_directory()
The `populate_working_directory()` function refers to populating the directory that will be packed into the `OTA image` (which in turn is used by default as the compressed recovery image).

The chain of functions called starting with this function, in essence take materials that have already been prepared (like the *system.img* described earlier, configuration files, a *ramdisk* image, a *kernel* image, *U-boot* materials, etc.) and puts them all in the directory that will ultimately be compressed (if `${config_imager__workdir_compressed}` is not empty - which is unlikely unless you are debugging all kind of things and want to save time, as compressing can take time with large images).
While we compress the image with a *.tar.xz* by default, this can be easily changed. However, be careful to not use compression algorithms that *busybox* does not support - as the flasher uses it.



```bash
  populate_working_directory()
  ==> populate_working_directory_with_boot_materials
    ==> # copies ${distro__image_materials_installables_bootfs_dir}
    ==> # copies ${distro__image_materials_removable_media_specifics_dir}
    ==> # populates autoflash and dontformatemmc if the values for the resepective $config_imager__autoflash and $config_imager__dontformatemmc
  ==> populate_removable_media_installables_directory
    ==> # copies ${distro__image_materials_installables_bootfs_dir}/* to ${config_imager__workdir}/installables/bootfat
    ==> copy_to_fat_installable_folders()
	  ==> # copies the subfolders of ${distro__image_materials_installables_folders_dir} to ${config_imager__workdir}/installables/folders/
    ==> copy_ext_partition_images()
	  ==> # copies ${config_imager__workdir_ext_partition_images}/*.img to ${config_imager__workdir}/installables/ext4images/
    ==> copy_installables_overlays_tarballs() # these ones will be untarred directly onto the respective partitions during installation
	  ==> # copies the subfolders of ${distro__image_materials_installables_overlays_dir}/ into ${config_imager__workdir}/installables/overlays
    ==> copy_installables_writableoverlays_tarballs() # these ones will untarred onto respective writable overlay partitions during installation
	  ==> # copies the subfolders of ${distro__image_materials_installables_writableoverlays_dir} into ${config_imager__workdir}/installables/writableoverlays}
```

Some more notes about the flows just depicted and explained:

- `populate_removable_media_installables_directory()` populates everything that needs to be under the *installables* directory, which as it names hints, is used by the flasher to install the materials in it to the respective partitions (indicated by some of the subfolder names)

- Note about `populate_working_directory_with_boot_materials()`:
  - One of the things to note is that both `${distro__image_materials_installables_bootfs_dir}` and `${distro__image_materials_removable_media_specifics_dir}` are considered and copied, and that can be useful in the case, one wants to have the same
  code (e.g. kernel, ramdisk, U-Boot, etc.) running on both their installer (removable) media, and flashed.
  - Depending on the use case, the selection of what to copy where is made, and this is likely to be changed in specific BSPs. The latter is considered mostly for having the kernel and ramdisk exist directly on the removable media itself.
  - It is a redundant design that can be better optimized, but it was simple enough to prepare, and has its advantages on some of the BSPs that have been used (but may not have been published just yet). The reason to "optimize it" is that they will find themselves on the top of the OTA tarball, which may not need it at all (but rather only need the installables, digests, and instruction files).

- In some places "copies" can be replaced with "hard-links", e.g. depending on the value of `${config_imager__hardlink_ext_partition_images}`. This is done as an optimization, and is not recommended to the generic user.

- In the `copy_installables_overlays_tarballs()` and `copy_installables_writableoverlays_tarballs()` functions, each subfolder corresponsds to a partition, and all of the tarballs will be untarred onto the root of the respective partition during installation.