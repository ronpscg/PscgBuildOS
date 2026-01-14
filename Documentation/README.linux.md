# Linux distro building general concepts and design
The major idea, is that the system enables to use multiple distros that share the same architecture and the same concepts, with a minimal switching, and minimal building time, comparing to any other distro.

## Main design considerations
The build system prioritizes:
- Speed of build and clean separation of components (e.g. kernel, rootfs, bootloader, QEMU)
- Reusing of components taken from either previous builds, or from other build systems (e.g. an file system image created by the *Yocto Project* or the *Android Open Source Project (AOSP)*)
- Offline builds - and so uses caching, and "just in case" gets more pacakges (e.g. for a Debian based system) than required. This is easily customizable, and the list of packages has been selected to represents. **This means that once you built something, you can save the caches aside, and build offline forever**
  - Which is very useful for travelling - all you flying instructors you should appreciate it! It takes one to know one!
- Trivial switching from one build to another
- **Not requiring the novice to know plenty of programming languages**
  - Everything is written in *bash*
  - For the *Linux* based distros, the *initramfs* is entirely written with a shell (*ash*) language as well
  - In most of the build system, the *bash* features are portable, and simplicity was chosen over constructs. Since it is not a very tiny project, sometimes I just opted for things that are easier for me.
  - **This makes the system an excellent use case of teaching scripting** - and it is indeed what I do, including the good and bad practices in a bash scripting course, for those who need to work with Embedded Linux, or with Linux and Embedded devices, effectively
  - For what it's worth - the design of this has been influenced by explaining too many things to too many people (Engineering managers I have designed OTA systems for), by the addition of *Rust* to the *Linux kernel*, and mostly, to the changes added to the *AOSP* build system, which forced even very strong and (relatively) unique enginners that knew all the *bash*, *python*, and *GNU Make* nuances, to have to add also *Golang*, *Ninja* and a derived home grown build system - which in time made teaching AOSP building and debugging extremely impossible in a reasonable course time.

### A note about other systems
  This document only addresses the *Linux* build flow, although the system supports building other systems as well (some have been omitted from the code that you see, because they require to know several programming languages and build systems - and I wanted this public project to be "A-Z" so that when someone masters it,
and understands it, even if it were their first job, I would feel quite confident to give them real work)

## Working with the code
Below I will present some of the concepts used in the file. The code itself is **FULL** of documentation, and since it is designed as an educational (and yet fully operational and usable in production, would you believe that?) build system, the expectation is to go and read the code. The documentation in this file, and some other files, will mostly serve as
some example guide, some use cases, etc.

As the file shows design principles and examples, it may not be accurate comparing to the present time code.

**Starting point**:

*build-image.sh* is the main build script. One can use environment variables that are set prior to invoking it, to modify a handful of characteristics. The latter, and more, are
modified and processed by sourcing  *.buildconfig* files.
Unless specified otherwise, all paths are relative to *$BUILD_TOP*)

### Linux building instruction path
**Legend:**
```
--> sources
==> calls
💡 insight  [... if multiline, might be appended with 💡]
```


#### build-image.sh flow
`build-image.sh` is a very simple script. It essentially:
- initializes a build environment
- sources the right set of scripts
- builds a distro, according to environment and configuration variables

So essentially two functions are called when you run the script: `init_env()` and `build_image()`

```
build-image.sh init_env()
--> $config  (if such an environment variable exists)
--> build/commonEnv.sh
--> config/toplevel.buildconfig
-->	config/buildtasks.buildconfig
```

```
build-image.sh build_image()
--> $distro_src_dir/${config_distro}.buildconfig
--> $DISTROS_DIR/common/build-distro-common.sh
--> $DISTROS_DIR/common-linux/build-distro-common-linux.sh  (only if Linux)
--> $distro_src_dir/build-distro.sh
--> source_file_or_die $BUILD_TOP/build/base_fetch_unpack.sh
==> main_build_distro()
```

For example, *pscg_debos*:
```
build-image.sh build_image()
--> distros/pscg_debos/pscg_debos.buildconfig
  --> distros/pscg_debos/recipes/rootfs/debos-common.inc
  ==> debos_common_init_env()
  💡 distro__identifier_name is set here - which enables multiple components (such as
       the rootfs working dir before it is packaged, and the generated QEMU scripts)
       to coexist in subsequent builds (e.g build noble, then trixie, then bookworm, ...)💡
  --> $DISTROS_DIR/common-linux/pscg_linux.buildconfig
  💡 Defines some functions, e.g. for setting the package list, etc.
  ...
```


`main_build_distro()` in terms ():
```
build-distro-common-linux.sh main_build_distro()
💡 sets some more configuration options, applies some sanity checks and creates required directories:
==> build_distro__source_build_configs
==> build_distro__source_shell_scripts
==> [build_distro__source_distro_specific_configs] # sources scripts if they exist
==> build_distro__prebuild_post_sourcing_sanity_checks
==> build_distro__make_working_directories_structure

💡 sets the infrastructure to reuse whatever is possible from previous builds - if the configuration options instruct to do so
==> build_distro_reuse_materials_wrapper
==> build_distro_reuse_build_src_and_arch_wrapper

==> bsp_linux__set_console_device_by_target_architecture # Call early enough, as it is used by the configuration files of several components

# Then it pretty much attends to building and packaging:
💡 Takes care of rootfs caching if the distro supports it (e.g. pscg_debos deb packages are not redownloaded or reinstalled if unnecessary, etc.)
💡 Builds the Linux kernel
💡 Builds the initramfs (ramdisk)
💡 Builds the rootfs
💡 adds kernel modules and firmware to the rootfs if required
💡 adds kernel modules and firmware to the initramfs (ramdisk) as well as other things if required - and repackages the initramfs (ramdisk)
💡 Builds the boot loader (s) and/or updates its configuration files if required 
💡 Takes care of secure boot related things if required
💡 Packages the images and takes care of OTA and recovery images if required
💡 Build QEMU installer (removable) media, live image, and persistent storage device if required
