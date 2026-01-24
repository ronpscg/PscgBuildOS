# Kernel Command-Line Parameters for Ramdisk

This document describes the kernel command-line parameters used in the ramdisk implementation. These parameters are parsed from the `cmdline_file` (typically `/proc/cmdline` or a custom path).

## Parameters

### `pscgrd.hw.bsp`
- **Description**: Specifies the BSP (Board Support Package) configuration. This in term is set in the `bsp` variable, which is used to source files that affect the behavior, under  *init-helpers/bsp/<bsp>* .
- **Affects**: Quiet a few things, init parameters, disk layout, flasher signaling (e.g. lights, terminal graphics) etc.
- **Default Behavior**: Not set unless explicitly passed.
- **Usage**:
  ```bash
  pscgrd.hw.bsp=<bsp>
  ```
- **Examples**:   `pscgrd.hw.bsp=qemu` , `pscgrd.hw.bsp=docker`. Both use common code from the *init-helpers/bsp/virtual*.\
  More examples are `pscgrd.hw.bsp=qcom`, `pscgrd.hw.bsp=bbb` , `pscgrd.hw.bsp=raspberrypi` and more, all use specific hardware knowledge.

---

### `boot`
- **Description**: Specifies the boot partition or device.
- **Affects**: Nothing, it's not used
- **Default Behavior**: Not set unless explicitly passed.
- **Usage**:
  ```bash
  boot=<unused>
  ```

---

### `root`
- **Description**: Specifies the root filesystem partition or device. It is expected to specify a *label*
- **Affects**: `ROOTFS_MOUNT_LABEL`, which is the label to which switch_root is done (either directly, or as an *overlayfs* *lowerdir*)
- **Default Behavior**: Not set unless explicitly passed.
- **Usage**:
  ```bash
  root=<label>
  ```

---

### `init`
- **Description**: Specifies the init process to use in the richos rootfs. (in the initramfs */init* is run, unless you specify `initrd=` **which you should not**)
- **Default Behavior**: Defaults to `/sbin/init` if not explicitly set.
- **Usage**:
  ```bash
  init=<executable-full-path>
  ```
- **Examples**: `init=/usr/lib/systemd/systemd` , `init=/sbin/init`

---

### `overlayfs`
- **Description**: Enables overlay filesystem and optionally specifies the partition and tmpfs size.
- **Default Behavior**: If not set, overlayfs is not used. If set without a parameter (i.e. just `overlayfs`), it will use the rootfs partition, appended with *rw*  (e.g. *systemrw* )
- **Usage**:
  ```bash
  overlayfs
  overlayfs=<partition>
  overlayfs=tmpfs,<tmpfssize>
  ```

---

### `remove_previous_overlayfs_contents`
- **Description**: Removes previous rootfs overlay filesystem contents upon an OTA update
- **Default Behavior**: Unless set to true, the overlay partition contents will remain. Otherwise, it will be formatted.
- **Usage**:
  ```bash
  remove_previous_overlayfs_contents=true
  ```

---

### `pscgrd.debug.openvts`
- **Description**: Enables openning vts (and serial consoles for your console device and hvc) early during the ramdisk.
  This is to be used as a debug only option, as it may interfere with your richos terminals (Depending on how they reinitialize them, if), and with your main console in case of a failure. It is recommended to not provide this option unless you know what you are doing.
  The current implementation of vts is to open vt #2 and #3, and this is easily changable in the code (@see `openvts()` `FIRSTVT` and `LASTVT` variables which are self explaining)
- **Affects**: `OPEN_SERIAL_VT_EARLY`
- **Default Behavior**: Not set unless explicitly passed.
- **Usage**:
  ```bash
  pscgrd.debug.openvts=<all|serial|hvc|vts>
  ```

---

### `pscgrd.net.autotelnet`
- **Description**: Enables auto telnet for debugging purposes, by getting an address over DHCP, and opening a password-less root telnet
- **Affects**: `AUTOTELNETD`
- **Default Behavior**: Not set unless explicitly passed.
- **Usage**:
  ```bash
  pscgrd.net.autotelnet=true
  ```
  
---

### `stopatramdisk`
- **Description**: Stops execution at a specific checkpoint in the ramdisk for debugging, and either *spawn*s or *exec*s a shell, according to the optional param after the optional ','
- **Affects**: `stopatramdisk` (the checkpoint), `stopatramdisk_behavior` (the behavior, *spawn* or *exec*)
- **Default Behavior**: Does nothing unless explicitly set. If set without a `=...` param, the default behavior is the same as `stopatramdisk=pre_rootfs,exec`
- **Usage**:
  ```bash
  stopatramdisk=<checkpoint>,<spawn|exec>
  ```
- **Examples**
```
stopatramdisk
stopatramdisk=successful_flashing,spawn"
stopatramdisk=pre_remove_previous_overlayfs_contents,spawn
stopatramdisk=pre_overlay_instructionsfile,spawn

```

---

### `waitforremovablemedia`
- **Description**: Waits for removable media to be inserted before proceeding. This indicates that an *installer* will run if it exists, and its filesystem has the right label, `PSCGINSTALL`
- **Affects**: `WAIT_FOR_REMOVABLE_MEDIA`
- **Default Behavior**: Assume there is no (installer) removable media, and proceed to the rootfs or other, non removable media installer logic.
- **Usage**:
  ```bash
  waitforremovablemedia
  ```

---

### `onetimeflasher`
- **Description**: Indicates that the flashing process should only run once. See 'Affects' below, and see `remove_autoflash_files_and_reboot()` for implementation details
- **Affects**: `ONE_TIME_FLASHER` . Affects the installer image (removable media) by removing from it the file `autoflash`
- **Default Behavior**: Not set unless explicitly passed.
- **Usage**:
  ```bash
  onetimeflasher
  ```

---

### `forceskipinstallermediaflashing`
- **Description**: Skips the automatic flashing sequence from the installation media. You are unlikely to use it.
- **Default Behavior**: Not set unless explicitly passed.
- **Usage**:
  ```bash
  forceskipinstallermediaflashing
  ```

---

### `mountfatrw`
- **Description**: Mounts FAT partitions as read-write. This allows to save logs on the installer media, or to backup data into it
- **Default Behavior**: FAT partitions are mounted read-only unless explicitly set.
- **Usage**:
  ```bash
  mountfatrw
  ```

---

### `recovery`
- **Description**: Specifies a recovery trigger. Used to enable the bootloader to specify that a recovery squence (e.g. return to a  "golden image" is requested)
- **Default Behavior**: Recovery mode is not enabled unless explicitly set.
- **Usage**:
  ```bash
  recovery=<trigger>
  ```
- **Examples**:
```
recovery=hardware_buttons
```

---

### `removablemedia_device`
- **Description**: Specifies the removable media device.
- **Affects**: `REMOVABLE_MEDIA_DEVICE`
- **Default Behavior**: Must be explicitly specified
- **Usage**:
  ```bash
  removablemedia_device=<device-name>
  ```
- **Examples**:
```
removablemedia_device=sdb
removablemedia_device=vdb
removablemedia_device=mmcblk1
```

---

### `emmc_device`
- **Description**: Specifies the eMMC device.
- **Affects**: `EMMC_DEVICE`
- **Default Behavior**: Must be explicitly specified
- **Usage**:
  ```bash
  emmc_device=<device-name>
  ```
- **Examples**:
```
removablemedia_device=sda
removablemedia_device=vda
removablemedia_device=mmcblk0
```

---

### `installer_boot_partition_number`
- **Description**: Specifies the boot partition number for the installer in A-only mode. You are unlikely to change that.
- **Affects**: `cmdline_installer_boot_partition_number`
- **Default Behavior**: Uses a default partition number (1) if not explicitly set. (@see `install_a_only()` )
- **Usage**:
  ```bash
  installer_boot_partition_number=<number>
  ```

---

### `installer_system_partition_number`
- **Description**: Specifies the system partition number for the installer. You are unlikely to change that.
- **Affects**: `cmdline_installer_system_partition_number`
- **Default Behavior**: Uses a default partition number (5) if not explicitly set. (@see `install_a_only()` )
- **Usage**:
  ```bash
  installer_system_partition_number=<number>
  ```

---

### `installer_a_only`
- **Description**: Forces the installer to use the "A-only" flashing scheme.
- **Affects**: `cmdline_installer_a_only` and consequently `installer_a_only`
- **Default Behavior**: Not set unless explicitly passed. This means that A/B will be the default scheme, unless it is the very first time something is installed to the storage. The partitions to which the installation will happen are affected by `installer_boot_partition_number` and `installer_system_partition_number`.
- **Usage**:
  ```bash
  installer_a_only=true
  ```

  TODO: Probably rename the redundancy (see Affects)

  ### `installer_ab_strategy`
- **Description**: Decide whether on an A only installation, the *otaextract* directory is the mounted *otaextract* partition (and then the installables are copied over it) or the copying is directly from the removable media (and then copying and thus time are saved)
- **Affects**: `INSTALLER_MEDIA_INSTALLER_AB_STRATEGY`
- **Default Behavior**: `directlyfromremovablemedia`
- **Usage**:
  ```bash
  installer_ab_strategy=<copyoverotaextract|directlyfromremovablemedia>
  ```


---

### `debug_run_commands_from_filesystem`
- **Description**: Enables running commands or executables from specific predefined paths in the filesystem. If set to `true`: if there is a file called `autorun.sh` it is *sourced*. If there is a file called `autorun` it is *exec*-ed.
- **Default Behavior**: Not set unless explicitly passed.
- **Usage**:
  ```bash
  debug_run_commands_from_filesystem=true
  ```

---

### `dontformatemmc`
- **Description**: Prevents formatting of the eMMC device. This can be used to save time if you repeatedly flash.
- **Default Behavior**: Formatting is done unless explicitly set, or unless explicitly stated in the installer media (or OTA or recovery file system - then they will be under `${SRC_INSTALL_PARTITION_MOUNT_POINT}/dontformatemmc` )
- **Usage**:
  ```bash
  dontformatemmc=true
  ```

---

### `abtestimageoverlaystrategy`
- **Description**: Specifies the strategy for testing image overlays in A/B systems, when booting to the richos after a successful flash. See the different values and explanations in `adjust_overlayfs_parameters_for_testing_flashed_image()`. Also see `init_env()` for the defaults and explanations.
- **Affects**: `AB_TEST_IMAGE_OVERLAY_STRATEGY`
- **Default Behavior**: `tmpfs,100M`
- **Usage**:
  ```bash
  abtestimageoverlaystrategy=<usesystemro|usesystemrw|usesystemoverlay|tmpfs*|>
  ```

---

### `fallbacktonooverlaystrategy`
- **Description**: Specifies the fallback strategy when no overlay is available, although the `overlayfs` cmdline param is set.
See the different values and explanations in  `mount_rootfs_with_overlayfs()`. Also see `init_env()` for the defaults and explanations.
- **Affects**: `FALLBACK_TO_NO_OVERLAY_STRATEGY`
- **Default Behavior**: `usesystemro`
- **Usage**:
  ```bash
  fallbacktonooverlaystrategy=<usesystemro|usesystemrw>
  ```

---

### Additional Parameters
Any additional parameters not explicitly handled in `parse_cmdline()` or `additional_parse_args()`, or one of the function either of them calls is ignored by the ramdisk (but may be used by the richos, or the Linux Kernel itself).


---
