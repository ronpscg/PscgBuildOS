
# Adding more hardware and firmware to Linux

This document gives you a framework of adding your own devices, by demonstrating a
popular USB WiFi/Bluetooth dongle, which has:
- A *kernel driver* and *subsystem* (in tree, but you have other examples in the projects for out-of-tree)
- The respective *firmware* that it loads

## Theory and practice of adding drivers and firmware to Linux
It is up to you, when designing something like this, to decide if you want to make it a kernel builtin or not. There are advantages and disadvantages to both, and once firmware loading is required, you need to copy the firmware files to a rootfs (or your initramfs) anyhow, so you need to know your system, your requirements and design.
On such occurences, it makes sense to use loadable kernel modules, however, since many times we demo with default configs, that have a lot of other loadable modules that are quite unnecessary, for important demonstrations, to save disk space and adjustment times (you have the minimal kernel configs and you can start from there, and then add if you want, which will also take time), we would likely use builtin modules for our demonstrations, as we don't need to worry about the "module databases"/`depmod` etc, which we prefer doing for the entire configuration. One could of course manage it themselves with `insmod`/`rmmod` rather than `modprobe`, but if I keep going the intro will be five pages already...

While a driver *can* decide to retry reloading firmware, if you really want to make it builtin, unless you put in in the initramfs like this:
```
CONFIG_EXTRA_FIRMWARE="firmware-name.bin"
CONFIG_EXTRA_FIRMWARE_DIR="/path/to/firmware"
```
You would want to do modprobe. Embedded Linux decisions...

Note: this *does not* address the Device Tree. We assume that if someone wants
to add device tree files - they either add it to the kernel, or as a prebuilt, and this version aims to deal with simpler things at the time of publishing it (there is a mechanism for doing dtb's and dtbo's but I did not port it to the open sourced project yet, and I am not sure if I will, as it is all very time consuming)

## Example videos


- What we will acheive, if we built outside of the build system, without *CONFIG_EXTRA_FIRMWARE*. These videos also show adding the required packages to alpine linux (which we will do in *PscgBuildOS* as well)
  - [https://www.youtube.com/watch?v=Y6BKlzAHRsM&list=PLBaH8x4hthVysdRTOlg2_8hL6CWCnN5l-&index=109]
  - [https://www.youtube.com/watch?v=nxNWKX9sSCA&list=PLBaH8x4hthVysdRTOlg2_8hL6CWCnN5l-&index=110]
- [A thorough explanation about building it with *CONFIG_EXTRA_FIRMWARE](https://www.youtube.com/watch?v=WJzppdaqk0Y&list=PLBaH8x4hthVysdRTOlg2_8hL6CWCnN5l-&index=111)

Using our system to achieve the same things:
- **TODO**

## Design principles
To add a driver and its firmware one needs to:
- Set the kernel configuration options
- Copy the firmware to the rootfs or initramfs (or possibly to the kernel itself)
- In case userspace executables are required to operate (e.g. `wpa_supplicant`), build them and populate the rootfs for *the respective distro*

This means that some things are absolutely distro independent, and some things are.
While this project **was not** modeled after the *Yocto Project*, the more contents I added to it, the more I found myself wanting to call variables in the same way. So distro-wise, let's say we are talking about a WiFi dongle, one would want to set the equivalent of the Yocto Project's `DISTRO_FEATURES` to specify that it has wifi, bluetooth, 3g/lte/5g, etc.
Then, each distro could look at the flags, and install the relevant configurations.

While I *could* bulid *wpa_supplicant* for the busybox ramdisk as well, this will not be done at this point. Perhaps I'll do it and add it as a prebuilt. It sometimes serves as
another exericse in the PSCG's Embedded Linux courses of working with minimal libc's, but to date, I did not require to build it statically, IIRC.


## Working with the code
