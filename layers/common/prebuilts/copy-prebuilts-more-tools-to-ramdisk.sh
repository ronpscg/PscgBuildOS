#!/bin/bash
#
# This script handles copying of some static prebuilts from well known places to the ramdisk.
#
# This is separated from the e2fsprogs and dosfstools scripts because they are (more) essential, whereas this is more of a convenience.
#
: ${PREBUILT_DIR_KEXECTOOLS_BASE=$HOME/dev/pscgdebos-external-projects-build/kexec-tools-static-builds}
: ${PREBUILT_DIR_TINYALSA_BASE=$HOME/dev/pscgdebos-external-projects-build/tinyalsa-static-builds}
: ${PREBUILT_DIR_SMALLOS_ASSETS=$HOME/dev/pscgdebos-external-projects-build/smallos-assets}

#
# side-effect: sets srcdir according to the target architecture. This assumes that all of tools prebuilts that have been built by Ron in some of his demonstrations
# 	       are under the same <tuple>-install convention
#
set_tools_src_dir() {
	case $ARCH in
		arm64|aarch64)
			srcdir=aarch64-linux-gnu-install
			;;
		arm)
			warn "You want to make sure that your target architecture indeed suits the prebuilt"
			srcdir=arm-linux-gnueabi-install
			;;
		armhf)
			warn "You want to make sure that your target architecture indeed suits the prebuilt"
			srcdir=arm-linux-gnueabihf-install
			;;
		riscv|riscv64)
			srcdir=riscv64-linux-gnu-install
			;;
		x86_64)
			srcdir=x86_64-linux-gnu-install
			;;
		x86|i386)
			srcdir=i686-linux-gnu-install
			;;
		loongarch64|loongarch)
            srcdir=loongarch64-linux-gnu-install
            ;;
		powerpc)
			srcdir=powerpc64le-linux-gnu-install
			;;
		s390x|s390)
			srcdir=s390x-linux-gnu-install
			;;
		sparc64)
			srcdir=sparc64-linux-gnu-install
			;;
		*)
			fatalError "Unsupported ARCH $ARCH"
			;;
	esac
}

#
# $1: source directory of installation (does not have to be full). likely to be expecting some files from /sbin
# $2: target, likely on a prepared ramdisk
#
copy_selected_kexectools () {
	[ "$config_ramdisk__kexectools_include" = "true" ] || return
	if [ ! -d $(readlink -f $PREBUILT_DIR_KEXECTOOLS_BASE ) ] ; then
		fatalError "No source folder in $PREBUILT_DIR_KEXECTOOLS_BASE. You may want to get the source code from somewhere e.g.  git clone  https://github.com/ronpscg/kexec-tools-static-builds.git $PREBUILT_DIR_KEXECTOOLS_BASE"
	fi
	set_tools_src_dir # properly sets srcdir
	dod cp -a $PREBUILT_DIR_KEXECTOOLS_BASE/$srcdir/usr/local/sbin/kexec $2/sbin
	# The next line should likely be commented out to save space, unless you leave in a world without networking, storage, or other
	# means to retrieve the core dump.
	dod cp -a $PREBUILT_DIR_KEXECTOOLS_BASE/$srcdir/usr/local/sbin/vmcore-dmesg $2/sbin
}

#
# $1: source directory of installation (does not have to be full). likely to be expecting some files from /sbin
# $2: target, likely on a prepared ramdisk
#
copy_selected_tinyalsatools () {
	[ "$config_ramdisk__tinyalsatools_include" = "true" ] || return
	local tinyalsa_tools_all="tinymix tinypcminfo"
	local tinyalsa_tools_in="tinycap"
	local tinyalsa_tools_out="tinyplay"
	local tools=""

	if [ ! -d $(readlink -f $PREBUILT_DIR_TINYALSA_BASE ) ] ; then
		fatalError "No source folder in $PREBUILT_DIR_TINYALSA_BASE. You may want to get the source code from somewhere e.g.  git clone  https://github.com/ronpscg/tinyalsa-static-builds.git $PREBUILT_DIR_TINYALSA_BASE"
	fi
	set_tools_src_dir # properly sets srcdir


	# TODO: integrate volume control etc. at BSP.

	# Basically for sound playback, if the device and its parameters are  well known
	#       and there is no need for debugging, one can just set tools="tinymix tinyplay" and it wil be enough

	# decide later which tools to include - as this is disk space wasteful. however, it shows a wonderful demonstration of
	# a minimal system that can do all kind of stuff. Imagine that your ramdisk would use a TTS accelerator and do microphone commands
	# rather than

	tools="$tinyalsa_tools_all"
	if true ; then
		tools="$tools $tinyalsa_tools_in"
	fi
	if true ; then
		tools="$tools $tinyalsa_tools_out"
	fi

	for tool in $tools ; do
		if [ ! -f $PREBUILT_DIR_TINYALSA_BASE/$srcdir/usr/local/bin/$tool ] ; then
			fatalError "No such tool $tool in $PREBUILT_DIR_TINYALSA_BASE/$srcdir/usr/local/bin/"
		fi
		dod cp -a $PREBUILT_DIR_TINYALSA_BASE/$srcdir/usr/local/bin/$tool $2/bin
	done
}

#
# $1: source directory of installation (does not have to be full)
# $2: target, likely on a prepared ramdisk
#
# Note: was written to demonstrate audio. while doing it, I was thinking about demonstrating a splashscreen, but I have done
#       that quite a lot ever since I put the youtube channel on, so from an educational (And practical!) point of view, I don't
#		see it as a priority now
# TODO: add a configuration for that (But it does require design, because bloating the ramdisk is a very bad idea, and the entire
#		original purpose was to show how busyboxos can be super slim and work as a powerful initramfs, as well as an operational filesystem)
#
copy_selected_assets () {
	[ "$config_ramdisk__assets_include" = "true" ] || return
	# At the time of writing, the only objective was to copy some audio files to show off tinyalsa and "BSP error sounds"
	# (e.g. in QEMU. Docker must use other mechanisms and not direct hardware access)

	local assets"" # unused now, just copy whatever is in the asset dirs - I did not put there much
	local assetdirs="audio video images fonts textures"

	if [ ! -d $(readlink -f $PREBUILT_DIR_SMALLOS_ASSETS ) ] ; then
		fatalError "No source folder in $PREBUILT_DIR_SMALLOS_ASSETS. You may want to get the source code from somewhere e.g.  git clone  https://github.com/ronpscg/smallos-assets.git $PREBUILT_DIR_SMALLOS_ASSETS"
	fi
	set_tools_src_dir # properly sets srcdir . has no effect now. preparation for if we want to "say something" or "display something" per arch.

	mkdir -p $2/assets || fatalError "Failed to create $2/assets"

	for dir in $assetdirs ; do
		if [ ! -d $PREBUILT_DIR_SMALLOS_ASSETS/$dir ] ; then
			if [ "$dir" = "audio" ] ; then
				fatalError "No such dir $dir in $PREBUILT_DIR_SMALLOS_ASSETS"
			fi
			# This is fine, as most of the assets dirs don't exist. At the time of writing, the objective was demonstrating Audio
			warn "No such dir $dir in $PREBUILT_DIR_SMALLOS_ASSETS"
			continue
		fi
		dod cp -a $PREBUILT_DIR_SMALLOS_ASSETS/$dir $2/assets
	done
}

main() {
	local dst=$1
	if [ ! -d "$dst" ] ;then
		fatalError "$dst does not exist"
	fi

	copy_selected_kexectools $PREBUILT_DIR_KEXECTOOLS_BASE $dst
	copy_selected_tinyalsatools $PREBUILT_DIR_TINYALSA_BASE $dst

	copy_selected_assets $PREBUILT_DIR_SMALLOS_ASSETS $dst
}

commonScriptPrologueLogRunAndEpilogue $@
