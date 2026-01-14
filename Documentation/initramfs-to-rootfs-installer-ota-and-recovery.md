# Installer, OTA and Recovery - a system designed from scratch with busybox, bash and ash (and some filesystem utils)

This document describes the mechanism implemented for the successful execution of:
- First image flashing from an installer media (aka. **installer_a_only**)
- Subsequent image flashing from an installer media
- Golden image recovery
- OTA update

All of the above, except for the *installer_a_only* support A/B updates.

Do note that the code is extremely documented, so most of the considerations, and usage patterns are listed there fully.
In addition, the [cmdline-ramdisk.md](cmdline-ramdisk.md) explains the different controlling command line parameters

## Design principles
While the *bootloader* and *Trusted Execution Environment* are crucial components in the design of a secure boot system, everything here
is implemented as part of an *initramfs*. The reasons are:
* Educational - the main goal of the entire project is to teach *Embedded Linux*, and to demonstrate concepts on the PSCG Embedded Linux courses and in Ron Munitz's talks.
* Simplicity - does not require you to learn a lot of tools or programming languages
* Hardware independance - one can port the same code to different hardware, and if they need "lower level" stuff - just translate it into the respective components
* One root filesystem to rule them all - in an initramfs
* Be very lightweight and super simple to build
  * Making it lighter weight by reducing static binaries is an important exercise in root file system minimization and troubleshooting, and so
    it is as minimal as it can get - except for using static binaries linked with glibc (as per the time of writing this document)
  * glibc was selected only out of simplicity - there are available cross toolchains in every modern distro for every modern architecture
  * In the PSCG Embedded Linux course we build toolchains from scratch, and in the Yocto Project and Buildroot courses, we build them with the respective tools
* Give enough security tools to teach proper design - and yet, give enough things to fix during courses

There are of course reasons for the entire distro, but people don't read long documentations (and sadly don't watch long videos. Too bad, I have a lot to say, and some of it is very useful)

### Security Notes
For the reasons listed above, the system deliberately ommits Public Key Cryptography (it exists in the exercises, and in the Linux kernel security courses), and only uses busybox to implement things.
This means that what we have is:
- Digest verification (so if the source is trusted and has not been compromised is fine)
And what we don't have is:
- Authenticity (signatures) or confidentiality (encryption), with the exception of OTA image obtained with https:// and avoiding Time-Of-Check-Time-Of-Use attacks (Which is of course unreasonable, but it makes an excellent security discussion)
  - We could provide the latter with dropbear and minimal cryptography libraries or building openssl
  - We could provide the latter with kernel API usage and a userspace "user" - but this is only for the Linux kernel related courses that
  - actively address cryptography


## Boot flow summary
While there are quite a lot of implemented features, and support for multiple *BSP*, the boot flow and software update flow has quite a lot of
commonalities. The "boot order" or "what to do with respect to software update" order is listed in this section.
### Working with the code
**Legend:**
```
--> sources
==> calls
💡 insight  [... if multiline, might be appended with 💡]
```

#### /init
/init main()
```
...
==> mount_basic_virtual_filesystems()
==> parse_cmdline()
    also sets the bsp variable according to pscgrd.hw.bsp -
==> init_hardware_dependent_code()
   --> /init-helpers/bsp/$bsp/init.sh
   ==> bsp_init_blockdev_variables() if this function exists, sets the block devices associated with the storage of this hardware
==> do_recovery_golden_image_logic()
==> do_removable_media_logic()
==> do_ota_update_logic()
==> do_rootfs_logic()

If the system cannot boot to the rootfs and no other step happens then:
==> do_fallback_to_shell
```

This allows you the flexibility of making decisions. e.g., you are in a software update. You fail to flash. Do you want to debug? Revert? etc.


So the flow is:
- If a recovery parameter has been provided to the kernel - do recovery preparations
- If there is a removable media and it has the `autoflash` file - install from removable media
- If there is a flagging by any of the subsystem to flash an image - follow the states as per the `do_ota_update_logic()`
- Continue to rootfs with a `switch_root` . This can also be done during an OTA.

The code, and the associated lecture will tell you the entire story.

#### rootfs software update activities
The rootfs relies on the *ota* service, or executable, which runs a state machine that can
* download a manifest from a server and do things according to the manifest
  * such as verify its digest, unpack it, do additional commands, etc.
  * Can work either on an entire image (*fullota*) or a livepatch (*livepatch*). The latter may not even involve the ramdisk, depending on the instructions provided by the manifest and the update file
* reboot to the initramfs after unpacking - and then a state machine is run there, to do the installation itself (and possibly backups, but that is very architecture specific)
* After initramfs thinks it successfully flashed the image, do some verifications and reboot, to see if to qualify the new image as the new image or not. That is where the A/B partitions are swapped - by setting a label to them


## More
There is a lot of information in the code itself, in the git commit logs (although it is likely you will not see all of them), and in the respective [youtube playlist](https://www.youtube.com/watch?v=kmaPtoCOKwM&list=PLBaH8x4hthVysdRTOlg2_8hL6CWCnN5l-) videos on the respective [youtube channel](https://www.youtube.com/@ronmunitz)