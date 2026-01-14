# Explanation about the different ARCH / arch environment variables

TLDR Important changes in the changelog (will be removed to another section when done - keeping it here helps me to keep track of what I'm doing as I'm doing it)
- `ARCH` will be adjusted only in the top level and **only** to the names supported by the Linux kernel (E.g. arch/ subdirectories, with the exception of `x86_64` which is listed explicitly, as setting `ARCH=x86` would result in building for `x86_64` by default.

## The Problem - each distro - projects has its own naming conventions
Several problems to begin with:
- Debian/Ubuntu/Docker calls *x86_64*  *amd64* , whereas the toolchains are x86_64-linux-gnu-...
- The Linux kernel calls armv8 (and later) *arm64*. So does MacOS. In a way so does docker (also calls it armv8). However, both `arch`/`uname -m` and all the toolchains call it `aarch64`
- Building with or without *armhf* can literally break distros completely, and even a trivial busybox init if an *arm* kernel is not compiled with `CONFIG_VFP` or `CONFIG_NEON`
- The Linux kernel calls the *riscv64* architecture *riscv* whereas all of the toolchains call it *riscv64*
- Older distros have i386-... or i585-... toolchains. Newer ones have i686. Buliding on x86_64 hosts with `-m32` requires multilib which conflicts with all other distro cross toolchains

In order to avoid too many adjustments in scripts, some conventions must be made. However, I already wrote all of this before actually agreeing on one, starting with the debian conventions,
and then figuring out that most people don't care about the intristics, and would just (maybe...) use ARCH= and CROSS_COMPILE=  .

So (and believe me there were hundreds of commits before the commit you see it, which was likely rebased it into one commit when I published it) some environment variables were added
in two ways:
- Global ones which are defined here. They include a common adjustment and terminology as well.
- Per distro/per project ones - have each buildsystem (kernel, busybox, different distros rootfs etc.) take care of their own adjustments.
  - If you know this project from the past - this is a significant change (TODO)

These lines were added after *Ubuntu 25.04* was released, and we decided to just keep things closer to distros, to help people start using this project without worrying about
custom toolchains (don't worry, if you see this as part of The PSCG's course, you will deal with your own built toolchains, a lot.)
The first versions of this project strongly supported building 32 bit x86 systems on x86_64 hosts with *multilib*, but as it is not worth the effort it is likely
to be left out or remain less tested (advised to use `CROSS_COMPILE=i686-linux-gnu-` with `ARCH=i386`) instead.

## Another problem - same architecture, different ABIs
As you can see below, some distros only provide *armhf* built rootfs. The Linux kernel knows how to emulate it and so you can build a kernel to handle it (see `CONFIG_VPF` et. al`).

This could be nice if one could specify `ARCH=armhf CROSS_COMPILE=...`, but it is not the case.

## Our solution for the global ones:
- `config_toplevel__arch` - will revert to the ARCH part of the Linux Kernel. If only $ARCH is provided, will be automatically adjusted
- `config_toplevel__arch_subarch` - subarch is not an accurate term, but we will use it, mostly for rootfs and some other tools
  - There is a room for improvement here, but there is also a room for more flags per compiler etc. We will not add them for now.
-  `toplevel__arch_crosscompile` - (TODO - this is a preparation for automatically setting `CROSS_COMPILE` - given a subarch. I think I will remove it as `CROSS_COMPILE` is already set for the most parts, and it is an important variable for the differet build projects)

## Supported toolchains - gcc only for now
**A note about Clang (LLVM):**
I just don't have time to support it, but it should work relatively well with kernels recent enough (make LLVM=1)
For userspace projects, the build should change to something like this:
clang --target=aarch64-linux-gnu --sysroot=/usr/aarch64-linux-gnu/libc --gcc-toolchain=/usr hello.c -o hello-arm64

If I happen to add support, all references to gcc will need to be replaced with some variables etc.
for now, all gcc references are explicit, and that is intentional.

## Porting Guide: Adding a new arch to the build (excerpts - Example - loongarch64)
1. Add treatment for `ARCH=<yourarch>`
```
toplevel__set_crosscompile_variables_if_needed() {
In config/toplevel.arch.buildconfig, add the following changes:
...
  loongarch)
			CROSS_COMPILE=loongarch64-linux-gnu-
			${CROSS_COMPILE}gcc -v >& /dev/null || fatalError "Cannot use cross compiler $CROSS_COMPILE. Please verify it is installed and in your path"
			;;
...
}
```

This is enough if you just want to build with ARCH=<yourarch>. There are more nuances with respect to subarchitectures, or if you would like to build natively. For this, you would want to read the file thoroughly. This applies, in general to the other steps here as well, as all instructions here were added to test `distro=pscg_busyboxos`, as it is the first recommended porting platform, and `distro=pscg_debos`.

You should look at the other functions in this file, and use your judgement to add additional considerations (especially if you want to use )

2. Create the kernel.buildconfig if need be and other things for the qemu bsp recipe:
In this case, we will reuse the RISCV config:
```
cd ~/dev/otaworkshop/PscgDebOS/layers/bsp/recipes/linux
cp -a  bsp-pscg_debos-qemu-riscv64/ bsp-pscg_debos-qemu-loongarch64/
```

You then need to modify parameters, according to your needs. For example,
```
: ${config_kernel__kernel_image_type=vmlinuz}
```
** HOWEVER, in this particular case, you cannot boot it directly with QEMU as its bios does not support non ELF targets. So another step of booting with EFI is required, or alternatively use *vmlinux*

3. If you want to use the installer functionality (which for now is a must), you must
Copy ramdisk prebuilts, otherwise you will have this error and more, per each prebuilt:
```
[copy-prebuilts-e2fsprogs-to-ramdisk.sh:] Unsupported ARCH loongarch /home/ron/dev/otaworkshop/PscgDebOS/layers/common/recipes/ramdisk/copy-prebuilts-e2fsprogs-to-ramdisk.sh
```

To do so, you need to add, e.g. to `layers/common/recipes/ramdisk/copy-prebuilts-e2fsprogs-to-ramdisk.sh` and `copy-prebuilts-more-tools-to-ramdisk.sh`
```
set_tools_src_dir()
...
loongarch64|loongarch)
                        srcdir=loongarch64-linux-gnu-install
                        ;;
...
```

If the architecture is not supported by the pscgdebos-external-projects-build tools - it is trivial to add it there. Add it, and feel free to send over a patch or a pull request.
You can see exactly the changes in the dedicated commits done in each of these projects (see the repos in ronpscg's public Github), it's made for you to add new architectures **very** easily.

4. Edit your qemu run script and add your architecture there (assuming you want to support it in qemu).
To do so, edit `layers/bsp/recipes/linux/common-qemu/run-scripts/run-qemu.sh` and there:
```
init_env() {
...
loongarch|loongarch64|loong64)
# will not specify too much, just look at the code itself for the example
...
qemu=qemu-system-loongarch64
...
...
```

5. To add Debian/Ubuntu support, if the respective distros support it, edit `distros/pscg_debos/pscg_debos.buildconfig` and adjust to something like this following excerpt:
```
pscg_debos__set_arch_specific_variables_if_needed() {
  ...
  : ${config_pscgdebos__debian_arch=loong64}
  bspname_archnamefixup=loongarch64 # deliberatley - different name from Debian as I want to break it from the other conventions
  config_pscgdebos__debian_base_url="http://ftp.ports.debian.org/debian-ports "
  config_pscgdebos__ubuntu_base_url="whatever-it-is-not-supported " # replace when Ubuntu is supported
  ...
}
```
You can see working examples, specifically for this process, in the code. The *archloong64* has been prepared specifically to create this example and documentation.

This should get you started, and once you do, you need to customize according to your needs, and according to what works or does not work (mostly depending on the Linux kernel configuration and QEMU support).
It is always best to start testing with busyboxos , as it is not guaranteed that the rootfs of other distros support the new architecture.

## Some conventions

The section below shows different conventions used by different projects. We can add more architectures, we did not add MIPS, some of the power (PowerPC) architectures et. al just for brevity and
not needing them when I started the project.

### Linux kernel
- `ARCH=arm64`
- `ARCH=x86_64`
- `ARCH=arm`
- `ARCH=riscv`
- `ARCH=i386`
- `ARCH=loongarch`
- `ARCH=powerpc`
- `ARCH=s390`

| ARCH= | CROSS_COMPILE= (empty if default) | status |
|-------|-|---------|
| x86_64 | | ✅ |
| i386 | i686-linux-gnu | ✅ |
| arm | | ✅ |
| riscv | | ✅ |
| arm64 | | ✅ |
| loongarch | | ✅ |
| powerpc | powerpc64le-linux-gnu | ✅ |
| s390 | | ✅ |


### QEMU
- qemu-system-aarch64 (qemu-system-arm64 is a symlink to it)
- qemu-system-x86_64
- qemu-system-arm (qemu-system-armhf and qemu-system-armel are symlinks to it)
- qemu-system-riscv64
- qemu-system-i386 (qemu-system-x86_64 can also run it)
- qemu-system-ppc64le
- qemu-system-s390x
- qemu-system-loongarch64 (qemu-system-loong64 is a symlink to it)

### Busybox
Doesn't care at all about `ARCH=`. You can lie to it brutally (as per the time of writing), set `CROSS_COMPILE=` and you'll be fine

### Cross toolchains in Ubuntu 25.04/25.10
Obviously you can build your own cross toolchains. Using the distro toolchain is easier of course, and these are the relevant ones that are here:
- aarch64-linux-gnu-
- x86_64-linux-gnu-
- arm-linux-gnueabi-
- arm-linux-gnueabihf-
- riscv64-linux-gnu-
- i686-linux-gnu-
- powerpc64le-linux-gnu-
- s390x-linux-gnu
- loongarch64-linux-gnu-

### Prebuilts (e.g. kexec-tools, e2fsprogs, etc.)
Same convention as the cross toolchains above

### Debian/Ubuntu
This is mostly relevant to the apt sources. Names that are common to Ubuntu and Debian (as per the time of writing) are:
- arm64
- amd64
- armhf
- riscv64
- i386

More things are explained in the relevant Debian and Ubuntu builders, as there are different URLs sometimes for different platforms, and it is
not interesting enough to support everything.

Do note that not all architectures are supported in all versions, and there are more details about it in the sections below. Some architectures are sometimes added, some architectures are sometimes (sort-of) phased out, until they are removed at some phase. If something is important to you, and is broken upstream (i.e. at Debian's or Ubuntu's repos) you can build your own Debian/Ubuntu repos.

#### Debian
An example of available Debian repos from *bookworm*:
- amd64
- arm64
- armel
- armhf
- i386
- mips64el
- mipsel
- ppc64el
- s390x


##### Notes about Debian ports (staging)
The following are examples for getting more Debian architectures. One would likely want to get the gpg key for the
Debian keyring usually, but in these cases, it's just quicker to not check gpg, for those obvious development and
training purposes.
The following serve as some examples for debootstrapping

Staging: debian ports from *unstable* (*sid*)
- loong64
  Debootstrapping example:
   ```
   sudo debootstrap --arch=loong64 --foreign   --no-check-gpg   sid ./debian-loong64-rootfs   http://ftp.ports.debian.org/debian-ports
   ```
- riscv64 (while it is in Ubuntu ports, it is not yet in Debian stable, as per the time of writing)
Supported on the main Debian archives only beginning trixie (Debian 13)
```
sudo debootstrap --arch=riscv64 --foreign   --no-check-gpg trixie ./debian-riscv64-rootfs   http://deb.debian.org/debian/
```

#### Ubuntu
A list of available Ubuntu architectures (ubunu-ports repos) from *noble*
- arm64
- armhf
- ppc64el
- s390x

An example of available Ubuntu architectures (x86/x86_64 repos) from *noble*
- amd64
- i386

#### Notes about signatures and verification during debootstrap
In essence, the keys for both Debian and Ubuntu will likely be known by your distro for all of the stable (or formerly stable) releases. For unstable releases, and in Ubuntu for non-LTS releases, it is likely that you will have to *import* the gpg keys yourself.

You can generally override that, by specifying `debianDebootstrapExtraArgs=" --no-check-gpg "`

You can recognize this type of error, if during debootstrap you have an error like:
```
E: Release signed by unknown key (key id 3AF65F93D6FBC5B9)
...
The specified keyring /usr/share/keyrings/debian-archive-keyring.gpg may be incorrect or out of date.
You can find the latest Debian release key at https://ftp-master.debian.org/keys.html
...
```

##### Particular notes about Ubuntu

While the above error excerpts was taken from a Debian build, the same type of error is applicable for both Debian an Ubuntu. In Ubuntu, as per the time of writing, you can see some examples that work or won't work.
- `distro=pscg_debos config_pscgdebos__debian_or_ubuntu=ubuntu config_pscgdebos__debian_codename=noble  ARCH=arm` - works
- `distro=pscg_debos config_pscgdebos__debian_or_ubuntu=ubuntu config_pscgdebos__debian_codename=oracular  ARCH=arm` - doesn't work
- `distro=pscg_debos config_pscgdebos__debian_or_ubuntu=ubuntu config_pscgdebos__debian_codename=oracular  ARCH=arm debianDebootstrapExtraArgs=" --no-check-gpg "` - works (as it skips the verification)

On the other hand, some versions may not work even if you skip the check, so you need to import the key or find another way to bring them up, e.g.:
- `distro=pscg_debos config_pscgdebos__debian_or_ubuntu=ubuntu config_pscgdebos__debian_codename=plucky  ARCH=arm debianDebootstrapExtraArgs=" --no-check-gpg "` - wouldn't work.

Note: At the time of writing, *plucky (25.04)* was the latest release, and *oracular (24.10)* was the one prior to it. Versions, what works, and what not, of course change.

In addition, if you want to use versions that are too old, you need to familiarize yourself with the URLs, as they change with time (in both Debian and Ubuntu)

**Important Note:** Sometimes, upstream support is just not working. You can see this with the missing packages of i386 in plucky, where even packages like `kbd` and `iputils-ping` are not present. This has been the case for *noble*, *plucky* and *oracular* and more on *i386*, as Canonical largely decided that *i386* is not a main supported architecture anymore. You may find it during the `debootstrap` process itself, because there is a release and there are packages. It is up to you, if you insist on a particular version, to resolve that.
For instance, you can add packages from another repo and solve the problems (and it is a nice exercise too, although quite sysadmin-ish), but we will obviously not take care of that for you.

Needless to say, if you use any of this for long lasting production, you are encourage to used LTS releases, or otherwise know what you are doing.


### Other distros
#### Alpine (not a focus, but I have demonstrated it in videos so I might update it)
The following "Mini Root Filesystem"s are available as per 2025:
- aarch64
- armhf
- armv7
- loongarch64
- ppc64le
- riscv64
- s390x
- x86
- x86_64


### Docker platforms
This is extra, I use it but I don't think it is relevant (yet) for the wider public.
- amd64
- arm64 (which is generally arm64/v8)
- arm  (which is generally arm/v7)
- riscv64 (not sure didn't check)
- 386

## Building for 32bit x86 targets on 64bit x86_64 hosts
As stated before, `ARCH` will be adjusted only in the top level and **only** to the names supported by the Linux kernel (E.g. arch/ subdirectories, with the exception of `x86_64` which is listed explicitly, as setting `ARCH=x86` would result in building for `x86_64` by default.
Therefore, we will fail `ARCH=x86` as a protective manner, and instruct the user to use either `ARCH=x86_64` or `ARCH=i386` respectively, and if no cross-compiler is selected, we will opt for selecting a cross toolchain that is widely available in modern distros, and also represents the spirit of the Linux kernel, opting in for removing the i386 architecture (but not the i686, don't mistake it for a complete removal!).
i.e., this will be build step, if only `ARCH=i386` is provided: `CROSS_COMPILE=i686-linux-gnu- ARCH=i386`