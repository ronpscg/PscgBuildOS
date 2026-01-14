# Creating images (Removable media installer, OTA-able images, recovery images)
This document contains the design principles and examples, for how the different *images* are created.
The same concepts apply to all of the architectures/products/etc., assuming of course, the configuration values for creating and packing the images are set.

This document was first been beautifully created with vim, unsaved, uncomitted, and had a computer malfunction destroy hours of careful writing :-(
Not sure how nice the writeup will be this time, I want to just publish it and that's it.

## Notes about feature availblity in what you currently see
As explained in multiple places, it is very possible that you are not exposed to all of the implemented features, because they have other been used at real customers' and require their
permission to port (even though I wrote them...), or are used as exercise in the PSCG Embedded Linux courses which I (still) don't want to spoil.
Some of these (teaser) are Android boot images (abootimg), U-Boot, EFI, non ext4 filesystems, GPT partitions, secure boot for several platforms, additional cryptographic mechanisms, and more. Yes, even some DFU like implementations, and NCM/RNDIS for flashing over a USB cable).
You might see some of those, and if people want to participate, implement, test and contribute back, they are welcome to do so.

## Design, theory and practice (i.e. examples)
The preparation of these images is listed below, so that you can follow more easily in the code, which is very heavily documented.

An excerpt of the flow is below:
```
make-installer-ota-recovery-images.sh main()
  ...
  ==> do_create_partition_images_from_folders()
  ==> populate_working_directory()
  ==> create_livecd_image()
  ==> create_ota_recovery_and_installer_images()
```

While this section will focus on the different types of images (i.e. the 2 last functions described in the last exceprts), a separate [dedicated document](imager-materials-population-detailed.md) will describe the first two functions, which essentially take as input all of the steps in the build systems, and niceley prepare `${config_imager__workdir}` which is the input for the `create_livecd_image()` and `create_ota_recovery_and_installer_images()` functions.

### Some terminology:
- **Installer image** - the removable media contents. Usually packed as fat partition on a disk, labeled PSCGINSTALL. It has folders and images to flash to the persistent storage, as well as instructions for the installation processes, given in the *installer.manifest* file. The installer image is created as a dd-able image file at `${config_imager__installer_image_file}`.
- **OTA tarball** or **OTA image** - a tarball containing everything needed to update an image partitions. While it *could* also contain a recovery tarball, the assumption is that it does not.
  - The latter requires explanation - the recovery tarball is itself an OTA tarball. If the OTA tarball contains a recovery tarball, it will also contain its *manifest*. It is eventually ultimately at `${config_imager__workdir_compressed}`.
- **Recovery tarball** - it is an *OTA tarball* that is put on the *installables/folders/recoverytarball/* folder on the *installer* image, provided with a manifest file. For now, the manifest file is also called *installer.manifest* because it represents that the *recovery* is doing exactly the same things the installer does. If you change it, also change in the *ramdisk* code: `local recovery_manifest=$RECOVERY_GOLDEN_IMAGE_MOUNT_POINT/installer.manifest` to whatever you change it to.
The tarball itself is created at `${config_imager__recovery_tarba
- **LiveCD image** - It is likely a representation of a workable *rootfs* partition, likely the `system` partition. By creating it, you can significantly speedup the test cycles of your root filesystem, and save build time by not having to prepare and compress the images for the installer/flasher code.
  - At the time of writing, a *livecd* has only been tested as a single *system.img*, but one can immitate the flasher code, to create a multipartition livecd, if it is really needed.

The *installer.digest* is not really needed,  it is left because it was used by some userspace tools, and if I have time I will likely update all, and remove them. It is not hurting anyone though, and just contains the digest that is in the respective manifest.

#### Notes about overlays and writable overlays (by example):
- **Overlays** and **Writeable overlays** mean partition labels which are populated by the flasher
- For example, a `system` overlay - will be directly untarred onto the system paritition. That will be as it were a part of the folder that the image was created from in the first place, only that the *flasher* code will do it
  - Unless of course, you decide to copy the mechanism to a phase right before packing the images, for your own purposes
- For example, a `system` writable overlay, will be untarred onto a well known directory tree under the `systemrw` labled partition  to be used as the *upper* level of an **overlayfs** mount. This will mean that  `system` will be *lower* and `systemrw` will be `upper`, and as the overlayfs rules dictate, *work* and *merged* will also be on the same partition of *upper*, so they will also reside on the `systemrw` labeled partition.

### Some examples
The examples represent the vidoes posted on August 20th and August 19th 2025, which explain about storage tradeoffs:
- https://www.youtube.com/watch?v=rR366koiXDc&list=PLBaH8x4hthVysdRTOlg2_8hL6CWCnN5l-&index=102
- https://www.youtube.com/watch?v=K5lwgZVs500&list=PLBaH8x4hthVysdRTOlg2_8hL6CWCnN5l-&index=104
- https://www.youtube.com/watch?v=9rqbTzOgONk&list=PLBaH8x4hthVysdRTOlg2_8hL6CWCnN5l-&index=105
- https://www.youtube.com/watch?v=YJJyjAe74Rk&list=PLBaH8x4hthVysdRTOlg2_8hL6CWCnN5l-&index=106

The first two videos are not entirely related, but the installation procedure and some important things are noted also there.
The last two videos, talk more about the sizes, and explain more about the configuration, so they are more relevant.
More videos may be added, but I don't feel it is needed at this point.

Example contents of the **non removable media installer materials - this becomes the OTA tarball**:
It turns `${config_imager__workdir}` into  `${config_imager__workdir_compressed}`:
```
$ tree /home/ron/aug19-pscgbuildos/tmp-but-persistent/PscgBuildOS/staging-i386/installer_fs_workdir/
/home/ron/aug19-pscgbuildos/tmp-but-persistent/PscgBuildOS/staging-i386/installer_fs_workdir/
├── autoflash
├── bzImage
├── initramfs.cpio
├── installables
│   ├── bootfat
│   │   ├── bzImage
│   │   ├── initramfs.cpio
│   │   └── kernel.config
│   ├── ext4images
│   │   └── system.img
│   ├── overlays
│   │   └── system
│   │       └── linux-modules.tar.gz
│   └── writableoverlays
│       └── system
│           └── ota-targetfiles-tarball.tar.xz
└── kernel.config
```


Example contents of the **removable media installer materials - this becomes the flasher image, holds the previously mentioned OTA tarball**.
It turns `${config_imager__installer_workdir}` into  `${config_imager__installer_image_file}`:
```
$ tree /home/ron/aug19-pscgbuildos/tmp-but-persistent/PscgBuildOS/staging-i386/installer-workdir
/home/ron/aug19-pscgbuildos/tmp-but-persistent/PscgBuildOS/staging-i386/installer-workdir
├── autoflash
├── bzImage
├── initramfs.cpio
├── installables
│   ├── bootfat
│   │   ├── bzImage
│   │   ├── initramfs.cpio
│   │   └── kernel.config
│   ├── ext4images
│   │   └── system.img
│   ├── folders
│   │   └── recoverytarball
│   │       ├── aug19_busyboxos_image_2308-i386.tar.xz
│   │       ├── installer.digest
│   │       └── installer.manifest
│   ├── overlays
│   │   └── system
│   │       └── linux-modules.tar.gz
│   └── writableoverlays
│       └── system
│           └── ota-targetfiles-tarball.tar.xz
├── installer.digest
├── installer.manifest
└── kernel.config
```


The recovery tarball in the second example contents, contains when untarred, exactly the first example contents by default. You could customize the code to provide something else, like a recovery image from another build (which could be useful if you want a very small image at the recovery, for example, that could perhaps do an OTA to a bigger one).

#### Recovery design example with a dedicated (and separate) recovery image
You can follow the following cookbook:
- Build PscgBuildOS with e.g. `distro=pscg_busyboxos` and keep the OTA tarball aside
- Build your intended image (e.g. `distro=pscg_debos`) and set the TODO_CUSTOM_RECOVERY_TARBALL  TODO_CUSTOM_RECOVERY_MANIFEST    TODO_CUSTOM_RECOVERY_DIGEST) variables to point
to your respective recovery image

You could alternatively just modify an existing installer image (by either mounting a real removable media, or loopback mounting an image), and just replace the contents of the *installables/folders/recoverytarbal*. It's really up to you. The imporant thing is that you craft your recovery tarball, and its manifest in a way that works (if you want to put Android recovery there, you are welcome to do so as well), and that is completely up to you.)


### More notes about QEMU and images
The basic idea is that there are two storage devices by default, configurable from the *qemu.env* file and environment variables when calling `run-qemu.sh` in the resulting bsp artifact folder.
The default values are populated during build times, as follows:
```
	: ${EMMC_IMAGE_FILE=$config_bsp__qemu_storage_device_path}
	: ${INSTALLER_IMAGE=$config_bsp__qemu_removable_media_path}
```

So if you want to modify the images you are currently working on, but don't want to modify the images you built (installer, and potentially livecd as the storage), your way to go
would be copying them over several places. It is wasteful, but the tradeoffs are up to you.

#### Controlling the removable media creation

To control the installer image size, set `config_imager__installer_media_size_sectors` . You can leave it unset if you are sure you don't want to add more things to the media after the build.

These are the configuration variables you would want to change if you want or don't want copies:
- `config_bsp__qemu_copy_installer_image_to_removable_media` - set to true to copy `${config_imager__installer_image_file}` to `${config_bsp__qemu_removable_media_path}`. This is implemented in `copy_removable_device_if_needed()`

#### Controlling the persistent storage creation
- If you set `config_bsp__qemu_recreate_storage_device` to true, whatever was the previous storage device at `${config_bsp__qemu_storage_device_path}` will be overridden with an empty file (dd-ed from */dev/zero*). Otherwise, you can reuse the previous storage device, and save some time, especially on large images. This is done in `create_storage_device()`, and the size is affected by: `${config_bsp__qemu_storage_device_size_mib}` and `$RAMDISK_DIR/flasher/config/partitions-emmc.config`. The size will be adjusted to an auto calculation (by the auto created *partition-emmc.config* - which itself has some configurable partition sizes that can be modified), if `config_bsp__qemu_storage_device_size_autoadjust` is set to true.
TODO: note - I think I did not check what happens if `config_bsp__qemu_storage_device_size_mib` is not set. I did sort of force it to be set.
-

You can also see in the videos (and maybe in some example code if it is uploaded - I just have too many of those and they may be confusing, as well as discourage learning to use the system configuration parameters)


#### Controlling the livecd creation
The livecd will be created only if `${config_bsp__qemu_livecd_storage_device_path}` is set to a value.
The livecd is currently made by copying `${config_imager__workdir_ext_partition_images/system.img}` to `${config_bsp__qemu_livecd_storage_device_path}`.
Since there are both *overlays* and *wrtiableoverlays* that the flasher (i.e. ramdisk code) takes into consideration, one could try and mimic these activities during the image build time.
This is implemented now only for the *overlays* of the *system* partition, to avoid abusing the mechanism and copying potentially huge images.
You can allow it (e.g. for copying the OTA richos files which have been traditionally made a *system* *overlay* ) by setting `config_bsp__qemu_livecd_extract_system_overlays_into_live_image=true`.
To implement it in general you need to:
- decide the size of the image
- decide if you extract overlays into one partition - or use the same partition tricks and then you also need to partition the image - which would be a preferred option, other than being wasteful in space or in space reservation calculation.

It's easy to implement, as all the functionalities have been implemented in other places (the flasher) - but again, everything with size considerations complicates things, and so I prefer to focus the explanation on the training on the real installer image and storage. At least at the time of writing this.
