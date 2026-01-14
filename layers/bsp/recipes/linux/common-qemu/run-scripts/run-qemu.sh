#!/bin/bash
#
# This scripts runs a QEMU instance of our pscg*os images with user mode QEMU (see notes below)
# It emulates as closely as possible a real device and storage format where:
# - the "bootloader workload"/first ramdisk are booted directly via QEMU parameters
# - The first block device represents an emmc
# - The second block device represents a removable media
#
# We are aiming for simplicity, and not for QEMU efficiency. In the PSCG courses we build QEMU, set networking devices, set accelerators
# and dive much deeper into QEMU. Here the objective is for you to know nothing about QEMU.
#
# This particular script is meant to be run in Linux with the respective qemu-system-* in the path.
# I will show how easy the adjusments are in class (e.g. no -enable-kvm but rather -accel=..., different paths for QEMU etc.), depending
# on the host operating systems and hardware of the attendees
#


usage() {
	echo "ARCH=<arm|arm64|riscv|x86_64|loongarch> $0"
}

# While I don't want it to be like the rest of the scripts and/or redefine functions, I did want to only warn of particularlly unsupported/untested platforms
# I will not change the rest of the echos until further notice (I just don't have time to refactor the ramdisk code and builder code macros to the same ones, if I do I'll do it here too)
error() { echo -e "\x1b[31m$@\x1b[0m" ; }
fatalError() { echo -e "\x1b[41m$@\x1b[0m" ; }
info() { echo -e "\x1b[32m$@\x1b[0m" ; }
hardInfo() { echo -e "\x1b[42m$@\x1b[0m" ; }
warn() { echo -e "\x1b[33m$@\x1b[0m" ; }
hardWarn() { echo -e "\x1b[43m$@\x1b[0m" ; }
debug() { echo -e "\x1b[34m$@\x1b[0m" ; }
hardDebug() { echo -e "\x1b[44m$@\x1b[0m" ; }
verbose() { echo -e "\x1b[34m$@\x1b[0m" ; }
hardVerbose() { echo -e "\x1b[44m$@\x1b[0m" ; }

init_env() {
	# In this basic setup you do not need to run as super user, but this script is augmented with more scripts in the courses
	# that may require sudo for additional setup on the first run, so this clause is left here
	if [ -n "$SUDO_USER" ] ; then
		: ${homedir=/home/$SUDO_USER}
	else
		: ${homedir=$HOME}
	fi

	LOCAL_DIR=$(readlink -f $(dirname ${BASH_SOURCE[0]}))
	cd $LOCAL_DIR
	if [ -f qemu.env ] ; then
		source qemu.env
	else
		echo "You did not provide a qemu.env file. We expect you to set some enviroment variables yourself"
	fi

	set -euo pipefail # perhaps this should be turned off by default.

	: ${ARCH=""}
	: ${QEMUOPTIONS=""}

	case $ARCH in
		arm)
			: ${imagetype=zImage}
			: ${console=ttyAMA0}
			: ${MACHINE:="-M virt,highmem=off"} # disable highmem for virtio hardware to work well with PCI. Requires -m less than 4GB!
			: ${qemu="qemu-system-arm"}
			# We will assume no hardware accelearation on 32 bit arm products
			: ${VIRT_ACCEL_OPTIONS_0=""}
			: ${NETWORKPARAMS_0=""}	# for now disable networking, to save some typing when running
			: ${QEMUOPTIONS_VIRTIO_NETWORK_DEVICE_TYPE=virtio-net-device}
			: ${QEMUOPTIONS_VIRTIO_SERIAL_DEVICE_TYPE=virtio-serial-device}
			: ${QEMUOPTIONS_VIRTIO_BLOCK_DEVICE_TYPE=virtio-blk-device}
			;;
		riscv|riscv64)
			: ${imagetype=Image}
			: ${console=ttyS0}
			: ${MACHINE:="-M virt"}
			: ${qemu=qemu-system-riscv64}
			: ${VIRT_ACCEL_OPTIONS_0=""}
			: ${NETWORKPARAMS_0=""}	# for now disable networking, to save some typing when running
			: ${QEMUOPTIONS_VIRTIO_NETWORK_DEVICE_TYPE=virtio-net-device}
			: ${QEMUOPTIONS_VIRTIO_SERIAL_DEVICE_TYPE=virtio-serial-device}
			: ${QEMUOPTIONS_VIRTIO_BLOCK_DEVICE_TYPE=virtio-blk-device}
			;;
		aarch64|arm64)
			ARCH=aarch64
			: ${imagetype=Image}
			: ${console=ttyAMA0}
			: ${MACHINE:="-M virt"}
			: ${CPU:="-cpu cortex-a72"}
			: ${qemu="qemu-system-aarch64"}
			# Could add checks depending on Apple Silicon, or native Linux. Will leave unaccelerated for now by default
			: ${VIRT_ACCEL_OPTIONS_0=""}
			: ${QEMUOPTIONS_VIRTIO_NETWORK_DEVICE_TYPE=virtio-net-device}
			: ${QEMUOPTIONS_VIRTIO_SERIAL_DEVICE_TYPE=virtio-serial-device}
			: ${QEMUOPTIONS_VIRTIO_BLOCK_DEVICE_TYPE=virtio-blk-device}
			;;
		x86_64)
			: ${imagetype=bzImage}
			: ${console=ttyS0}
			: ${qemu=qemu-system-x86_64}
			: ${VIRT_ACCEL_OPTIONS_0="-enable-kvm"} # This assumes you are using an x86_64 host. Trivial to change
			: ${QEMUOPTIONS_VIRTIO_NETWORK_DEVICE_TYPE=virtio-net-pci}
			: ${QEMUOPTIONS_VIRTIO_SERIAL_DEVICE_TYPE=virtio-serial-pci}
			: ${QEMUOPTIONS_VIRTIO_BLOCK_DEVICE_TYPE=virtio-blk-pci}
			;;
		i386|i686)
			: ${imagetype=bzImage}
			: ${console=ttyS0}
			: ${qemu=qemu-system-i386}
			: ${VIRT_ACCEL_OPTIONS_0="-enable-kvm"} # This assumes you are using an x86_64 host. Trivial to change
			: ${QEMUOPTIONS_VIRTIO_NETWORK_DEVICE_TYPE=virtio-net-pci}
			: ${QEMUOPTIONS_VIRTIO_SERIAL_DEVICE_TYPE=virtio-serial-pci}
			: ${QEMUOPTIONS_VIRTIO_BLOCK_DEVICE_TYPE=virtio-blk-pci}
			echo "As per this time, i386 is not recommended, because we did not build some of the tools for it, but for very simple busybox distros (without robust flashers) it will work"
			;;
		loongarch|loongarch64|loong64)
			warn "This is work in progress, as QEMU does not support booting loongarch64 kernels without UEFI yet"
			warn "If you built it yourself, and you can't boot - you can try to build with config_bsp_qemu_kernel_image_use_vmlinux=true"
			hardWarn "You can override KERNEL_IMAGE to point to the vmlinux image and then you can boot it to experiment with loongarch64 QEMU"
			debug "e.g. something like KERNEL_IMAGE=/home/ron/pscgbuildos-builds/target/shared/arch/loongarch/linux-kernel-build/vmlinux"
			warn "You can also use UEFI, by buildind QEMU yourself or installing the specific bios (e.g. sudo apt-get install qemu-efi-loongarch64):
			KERNEL_IMAGE=/home/ron/pscgbuildos-builds/target/shared/arch/loongarch/linux-kernel-build/arch/loongarch/boot/vmlinux.efi QEMUOPTIONS=\"-bios /usr/share/qemu-efi-loongarch64/QEMU_EFI.fd\" /home/ron/shared_artifacts-jul/runqemus/pscg_debos-debian-sid-minbase-loong64/run-qemu.sh"

			: ${MACHINE="-M virt"}
			: ${CPU="-cpu la464"}
			: ${imagetype=vmlinuz.efi}
			: ${console=ttyS0}

			: ${qemu=qemu-system-loongarch64}
			: ${VIRT_ACCEL_OPTIONS_0=""} # This assumes you are using an x86_64 host. Trivial to change
			: ${QEMUOPTIONS_VIRTIO_NETWORK_DEVICE_TYPE=virtio-net-pci}
			: ${QEMUOPTIONS_VIRTIO_SERIAL_DEVICE_TYPE=virtio-serial-pci}
			: ${QEMUOPTIONS_VIRTIO_BLOCK_DEVICE_TYPE=virtio-blk-pci}
			;;
		powerpc)
			: ${imagetype=zImage.pseries}
			: ${console=ttyS0}

			: ${qemu=qemu-system-ppc64le}
			: ${VIRT_ACCEL_OPTIONS_0=""} # This assumes you are using an x86_64 host. Trivial to change
			: ${QEMUOPTIONS_VIRTIO_NETWORK_DEVICE_TYPE=virtio-net-pci}
			: ${QEMUOPTIONS_VIRTIO_SERIAL_DEVICE_TYPE=virtio-serial-pci}
			: ${QEMUOPTIONS_VIRTIO_BLOCK_DEVICE_TYPE=virtio-blk-pci}
			;;
		s390)
			: ${imagetype=bzImage}
			: ${console=ttyS0}

			: ${qemu=qemu-system-s390x}
			: ${VIRT_ACCEL_OPTIONS_0=""} # This assumes you are using an x86_64 host. Trivial to change
			: ${QEMUOPTIONS_VIRTIO_NETWORK_DEVICE_TYPE=virtio-net-pci}
			: ${QEMUOPTIONS_VIRTIO_SERIAL_DEVICE_TYPE=virtio-serial-pci}
			: ${QEMUOPTIONS_VIRTIO_BLOCK_DEVICE_TYPE=virtio-blk-pci}
			;;
		sparc64)
			: ${imagetype=image}
			: ${console=ttyS0}

			: ${qemu=qemu-system-sparc64} # requires sparc64 openbios
			: ${VIRT_ACCEL_OPTIONS_0=""} # This assumes you are using an x86_64 host. Trivial to change
			: ${QEMUOPTIONS_VIRTIO_NETWORK_DEVICE_TYPE=virtio-net-pci}
			: ${QEMUOPTIONS_VIRTIO_SERIAL_DEVICE_TYPE=virtio-serial-pci}
			: ${QEMUOPTIONS_VIRTIO_BLOCK_DEVICE_TYPE=virtio-blk-pci}

			warn "sparc64 has been added as another example, and is not expected to be used by anyone, other than training purposes"
			warn "sparc64 has very limited PCI slots"
			warn "qemu-system-sparc64: -device virtio-blk-pci,drive=emmcdisk: PCI: no slot/function available for virtio-blk-pci, all in use or reserved"
			error "It is provided as an example".
			warn 'You may want to run something like: USE_VIRTIO_FOR_CONSOLE_DEVICES=false NETWORKPARAMS_0=" "  GRAPHICSPARAMS_0="" AUDIOPARAMS_0=""  INPUTPARAMS_0="" STORAGEPARAMS_REMOVABLE_0="" STORAGEPARAMS_EMMC_0=""  CONSOLEPARAMS_0="-serial mon:stdio" /home/ron/aug19-pscgbuildos/artifacts/runqemus/pscg_busyboxos-sparc64/run-qemu.sh'
			;;
		*)
			echo "unsupported arch $ARCH"
			usage
			exit 1
			;;
	esac

	# The following are command line parameters e.g -smp -cpu -m  -M etc
	: ${MACHINE=""}
	: ${CPU=""}
	: ${SMP="-smp 4"}
	: ${MEMORY="-m 2G"}

	# QEMU will boot the materials there. Our ramdisk and flasher will be there along with the kernel and what makes it work
	: ${bootdir=$homedir/dev/dev-boot/$ARCH}
	: ${KERNEL_IMAGE=$bootdir/$imagetype}
	: ${RAMDISK_IMAGE=$bootdir/initramfs.${config_ramdisk__compression}}

	: ${EMMC_IMAGE_FILE=new-fake}
	: ${config_distro="pscg_quickhack_linuxos-or-whatever-it-should-be-overridden-anyway"}
	: ${INSTALLER_IMAGE=$config_toplevel__shared_artifacts/${config_distro}-$ARCH-installer.img}

	echo Installer image is $INSTALLER_IMAGE
	echo Emmc/hd image is $EMMC_IMAGE_FILE

	# These are handled in other scripts, and left here to discuss some things that are not the common installer flow
	: ${ROOTFS_IMAGE=xy}
	: ${ROOTFS_9P=xyz}
	: ${RAMDISK_9P=vwt}

	set_storage_params
	set_network_params
	set_serial_console_and_graphics_params
}

#
# This function is used to check the storage parameters and warn the user if they are not set correctly. Simple, short, not extensive
#
storage_sanity_checks_and_user_warning() {
	local error=false
	if [ ! -f "$INSTALLER_IMAGE" -a -n "$STORAGEPARAMS_REMOVABLE_0" ] ; then
		echo -e "\x1b[31mERROR: The installer image $INSTALLER_IMAGE does not exist. Please check your configuration.\x1b[0m"
		echo "You can use the 'generate-qemu-scripts.sh' script to generate the installer image."
		echo "If you are using a different image, please update the INSTALLER_IMAGE variable in the script."
		echo "If you only want to check the harddrive image - e.g. to quickly test a system.img without the installer, you should do one of the following:"
		echo " 1. set STORAGEPARAMS_REMOVABLE_0=\"\" *prior* to running this script."
		echo " 2. touch $INSTALLER_IMAGE  to create a dummy file"
		error=true
	fi

	if [ ! -f "$EMMC_IMAGE_FILE" -a -n "$STORAGEPARAMS_EMMC_0" ] ; then
		echo -e "\x1b[31mERROR: The EMMC image file $EMMC_IMAGE_FILE does not exist. Please check your configuration.\x1b[0m"
		echo "If you only want to check the harddrive image - e.g. to quickly test an installer image, you should do one of the following:"
		echo " 1. set STORAGEPARAMS_EMMC_0=\"\" *prior* to running this script."
		error=true
	fi

	if [ -n "$MORE_USAGE_RECOMMENDATIONS_IN_RUNQEMU" ] ; then
		echo "The following warnings came from your build system. If you already overcame them yourself, or know what you are doing, you can ignore them, and you can also reset MORE_USAGE_RECOMMENDATIONS_IN_RUNQEMU in the respective qemu.env file"
		echo -e "$MORE_USAGE_RECOMMENDATIONS_IN_RUNQEMU"
	fi
	[ "$error" = "true" ] && exit 1 || true # qemu will fail on it later anyway, so avoid the extra prints
}
#
# By default we want to be very easy and do minimum configurations. Sometimes we want to illustrate the importance and performance gains, (and security...) of different drivers and image formats
#
set_storage_params() {
	if [ ! "$USE_VIRTIO_FOR_STORAGE_DEVICES" = "true" ] ; then
		: ${STORAGEPARAMS_EMMC_0="\
			-drive id=emmcdisk,file=$EMMC_IMAGE_FILE,format=raw,if=none \
			-device ahci,id=ahci0 \
			-device ide-hd,drive=emmcdisk,bus=ahci0.0 \
			"\
		}
		: ${STORAGEPARAMS_REMOVABLE_0="\
			-drive id=removabledrive,file=$INSTALLER_IMAGE,format=raw,if=none \
			-device ahci,id=ahci \
			-device ide-hd,drive=removabledrive,bus=ahci.0 \
			"\
		}

		target_emmc_device=sda
		target_removablemedia_device=sdb

	else
		# Just keep the default configs and your host distro qemu happy and use virtio
		# NOTE the reverse order - for whatever reason, in some architectures and some QEMU/kernel versions, virtio defaults are in the reverse order of definitions, and we want the harddrive to be the first device.
		# You will easily see it in runtime. One solution for that can be to only work with labels/uuid/etc. Another one, which we use here,
		# is to understand if it got it right very early at runtime.
		# This only affects the installer/storage workflow. If there is no removable media, or there is only a livecd, then it does not matter.
		: ${STORAGEPARAMS_EMMC_0="\
			-drive id=emmcdisk,file=$EMMC_IMAGE_FILE,format=raw,if=none -device $QEMUOPTIONS_VIRTIO_BLOCK_DEVICE_TYPE,drive=emmcdisk \
			"\
		}
		: ${STORAGEPARAMS_REMOVABLE_0="\
			-drive id=removabledrive,file=$INSTALLER_IMAGE,format=raw,if=none -device $QEMUOPTIONS_VIRTIO_BLOCK_DEVICE_TYPE,drive=removabledrive \
			"\
		}

		warn "Using virtio for storage devices. The order is not guaranteed, so if you rely on the device name (e.g. /dev/vda), and things don't go as you might expect, you may want to revise that."

		target_emmc_device=vda
		target_removablemedia_device=vdb

		if [[ "$ARCH" =~ "arm" ]] ; then
			warn "Reversing vda/vdb order for $ARCH as they seem to be reversed compared to other architectures"
			target_emmc_device=vdb
			target_removablemedia_device=vda
		fi
	fi

	: ${CMDLINE_STORAGE:=""}
	if [ -n "$STORAGEPARAMS_EMMC_0" ] ; then
		CMDLINE_STORAGE+=" emmc_device=$target_emmc_device"
	fi
	if [ -n "$STORAGEPARAMS_REMOVABLE_0" ] ; then
		CMDLINE_STORAGE+=" removablemedia_device=$target_removablemedia_device"
	fi

	storage_sanity_checks_and_user_warning
}

set_network_params() {
	if [ ! "$USE_VIRTIO_FOR_NETWORK_DEVICES" = "true" ] ; then
		if [ "$ARCH" = "arm" ] ; then
			warn "The arm default configuration does not have network support, so it is likely you will not have it for arm - you can fix it"
		fi

		if [[ "$ARCH" =~ riscv ]] ; then
			# I think I opted for the quickest build for the default config of riscv64. If this changes, we can add that.
			warn "The riscv default configuration does not have network support, so it is likely you will not have it for arm - you can fix it"
		fi
	else
		if [[ "$ARCH" =~ "loongarch" ]] ; then
			warn "$ARCH does not support virtio networking at the moment. Perhaps you can fix it, or use another -netdev"
		fi

		: ${NETWORKPARAMS_0:="-netdev user,id=unet -device $QEMUOPTIONS_VIRTIO_NETWORK_DEVICE_TYPE,netdev=unet"}
	fi

	# no need to set any more CMDLINE_NETWORK parameters for now, but you may add some if you wish to
}

#
# This is an example as the possibilities are infinite...
# Note that the *last* console=... parameter in the chain is the actual /dev/console . It is set by default if nothing else is set, but here, in particular
# one could override config_kernel__kernel_config_src_path and then set some of these.
#
# I simply don't have time to work on this now, so I am leaving it as a place to look at things. There are several other one/two files projects I added (or the helpers) that
# can demonstrate, quite a few configuration options for multiple platforms
#
set_console_params() {
	if [ "$USE_VIRTIO_FOR_CONSOLE_DEVICES" = "true" ] ; then
		# TODO today - I think this is ARM only
		# This is an example you can use if you want to. Note that it will not show the boot from the very beginning
		CONSOLEPARAMS_EXAMPLE_VIRTIO_STDIO_ONLY="-chardev stdio,id=virtiocon0,mux=on,signal=off \
			-device $QEMUOPTIONS_VIRTIO_SERIAL_DEVICE_TYPE,id=virtioserialbus0 \
			-device virtconsole,chardev=virtiocon0,bus=virtioserialbus0.0 \
			-mon chardev=virtiocon0,mode=readline \
		"
		# TODO today - I think this is x86 only
		CONSOLEPARAMS_SERIAL_TO_STDIO_VIRTIO_TO_UDS="-chardev socket,id=hvc0_socket,path=/tmp/qemu_hvc0.sock,server=on,wait=off \
			-device $QEMUOPTIONS_VIRTIO_SERIAL_DEVICE_TYPE -device virtconsole,chardev=hvc0_socket \
			-serial mon:stdio \
		"

		echo -e "\x1b[35mVIRTIO_CONSOLE: Assuming you want to connect to it with a Unix Domain Socket using:\nsocat STDIO,raw,echo=0 UNIX-CONNECT:/tmp/qemu_hvc0.sock\x1b[0m"
		echo -e "\x1b[35mYou may want to run it with a wait=on parameter, use it as stdio, and more\x1b[0m"
		echo -e "\x1b[35mPlease edit directly $0 if you wish to change the behavior, this is just an example\x1b[0m"

		CMDLINE_CONSOLE="console=hvc0 $CMDLINE_CONSOLE"

		CONSOLEPARAMS_0+=" $CONSOLEPARAMS_SERIAL_TO_STDIO_VIRTIO_TO_UDS"
	fi

}

set_graphics_params() {
	# The defaults are excellent for console only.
	#
	# A recommendation for graphics could be something like:
	# CMDLINE="vga=0x312 console=ttyS0"
	# GRAPHICSPARAMS_0="-vga std" # leaving it empty would be fine
	# CONSOLEPARAMS_0="-serial mon:stdio"
	# -append "nosplash fbcon=nodefer vga=0x312  nokaslr rdinit=/init console=ttyS0"  -serial mon:stdio

	:
}

#
# These are mostly left for the user to specify parameters, either before building the respective distro, or before running run-qemu.sh
# added additional devices here as well (audio, and misc, a.k.a "more devices")
#
set_serial_console_and_graphics_params() {
	set_console_params
	set_graphics_params

	: ${CONSOLEPARAMS_0="-nographic"}
	: ${GRAPHICSPARAMS_0=""}
	: ${AUDIOPARAMS_0=""} # no audio by default, but you can set it to -device AC97, or -device hda, or -device es1370, etc.
	: ${INPUTPARAMS_0=""}
	: ${MOREDEVICESPARAMS_0=""}
	: ${MOREDEVICESPARAMS_1=""}
}

#
# Print the qemu command line and run it
#
print_and_run_qemu_command() {
	       qemu_cmd="$qemu $SMP $MEMORY $CPU $MACHINE \
		   		$BIOSPARAMS                                                                     \
                -kernel $KERNEL_IMAGE                                                           \
                -initrd $RAMDISK_IMAGE                                                          \
                -append \"$CMDLINE\"                                                            \
                $STORAGEPARAMS_EMMC_0                                                           \
                $STORAGEPARAMS_REMOVABLE_0                                                      \
                $NETWORKPARAMS_0                                                                \
                $CONSOLEPARAMS_0                                                                \
                $GRAPHICSPARAMS_0                                                               \
                $AUDIOPARAMS_0                                                                  \
                $INPUTPARAMS_0                                                                  \
                $MOREDEVICESPARAMS_0                                                            \
                $MOREDEVICESPARAMS_1                                                            \
                $VIRT_ACCEL_OPTIONS_0                                                           \
                $QEMUOPTIONS"

	# The command line is printed for debugging purposes. You can remove it if you want
	echo -e "\x1b[34mRunning QEMU with the following command line:\x1b[0m"
	echo -e "\x1b[34m$qemu_cmd\x1b[0m" | tr -s "[:blank:]" " " # remove extra spaces

	if [ "$DEBUG_PRINT_MODE" = "true" ] ; then
		info "Debug mode enabled - not running QEMU"
		return
	fi
	eval $qemu_cmd
}

#
# Run qemu - using the user backend - this is *intentional* - however, not all QEMU's have SLIRP compiled into them
# 	     Why intentional? No need to setup network interfaces.
#	     Note the cmdline. This is an easy recommendation. If you know what you are doing, you may set --complete-command-line-override
#
run_qemu() {
	: ${CMDLINE=""}
	if [ "$COMPLETE_COMMAND_LINE_OVERRIDE" = "true" ] ; then
		echo -e "Using complete command line override: \x1b[34m$CMDLINE\x1b[0m]"
		if [ -z "$CMDLINE" ] ; then
			echo -e "\x1[31mYou must set the CMDLINE variable\x1b[0m"
			exit 1
		fi
	else
		: ${CMDLINE_DEFAULT_SETTINGS="$CMDLINE $CMDLINE_CONSOLE $CMDLINE_GRAPHICS $CMDLINE_STORAGE $CMDLINE_NETWORK $CMDLINE_RAMDISK_DEFAULT_SETTINGS"}
		CMDLINE=$CMDLINE_DEFAULT_SETTINGS
		#CMDLINE="$CMDLINE pscgrd.hw.bsp=qemu console=$console net.ifnames=0 $CMDLINE_STORAGE pscgrd.net.autotelnet=0 " # give up the overlayfs so that the main filesystem will not be ro
		#CMDLINE="$CMDLINE waitforremovablemedia installer_a_only=true stopatramdisk=successful_flashing,spawn"
		#CMDLINE="$CMDLINE  " #  overlayfs=tmpfs,200M dontformatemmc"
		#CMDLINE="$CMDLINE abtestimageoverlaystrategy=nothing"

	fi

	print_and_run_qemu_command
}

#
# While most of the arguments are expected to be set in the qemu.env file or via an enviroment variable, this function takes care
# of setting some special params such as:
# --complete-command-line-override - use the cmdline exacly as per CMDLINE, or as per the value after '='. Otherwise CMDLINE is appended to some defaults.
#
parse_args() {
	COMPLETE_COMMAND_LINE_OVERRIDE=false
	DEBUG_PRINT_MODE=false
	while [ $# -gt 0 ]; do
		case "$1" in
			--complete-command-line-override)
				COMPLETE_COMMAND_LINE_OVERRIDE=true
				shift
				;;
			--complete-command-line-override=*)
				COMPLETE_COMMAND_LINE_OVERRIDE=true
				CMDLINE="${1#*=}"
				shift
				;;
			-h|--help)
				echo "Kindly check the scripts and environment variables. The only argument supported is --complete-command-line-override[=*]"
				exit 0
				;;
			-d|--debug)
				DEBUG_PRINT_MODE=true
				hardDebug "Debug mode enabled - will print information and not run qemu"
				shift
				;;
			*)
				echo "Unknown option: $1"
				exit 1
				;;
		esac
	done
}

main() {
	parse_args "$@"
	init_env
	run_qemu
}

main "$@"
exit 0
