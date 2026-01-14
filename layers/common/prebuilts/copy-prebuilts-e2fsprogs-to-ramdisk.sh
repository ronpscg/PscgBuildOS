#!/bin/bash
#
# This script handles copying of some static prebuilts from well known places to the ramdisk.
# The motivation is a quick and dirty fixup of fsck.ext4, fsck.fat and some other tools due to busybox's incompetence
# First version: some binaries cloned from https://github.com/ronpscg/e2fsprogs-static-builds.git
#

: ${PREBUILT_DIR_E2FSPROGS_BASE=$HOME/dev/pscgdebos-external-projects-build/e2fsprogs-static-builds}
: ${PREBUILT_DIR_DOSFSTOOLS_BASE=$HOME/dev/pscgdebos-external-projects-build/dosfstools-static-builds}



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
copy_selected_e2fsprogs() {
	local resolved_path=$(readlink -f $PREBUILT_DIR_E2FSPROGS_BASE)
	if [ -z "$resolved_path" -o ! -d "$resolved_path" ] ; then
		fatalError "No source folder in $PREBUILT_DIR_E2FSPROGS_BASE. You may want to get the source code from somewhere e.g.  git clone  https://github.com/ronpscg/e2fsprogs-static-builds.git $PREBUILT_DIR_E2FSPROGS_BASE"
	fi
	set_tools_src_dir # properly sets srcdir
	dod cp -a $PREBUILT_DIR_E2FSPROGS_BASE/$srcdir/sbin/{e2fsck,tune2fs,resize2fs} $2/sbin
}

#
# $1: source directory of installation (does not have to be full). likely to be expecting some files from /sbin
# $2: target, likely on a prepared ramdisk
#
copy_selected_dosfstools() {
	local resolved_path=$(readlink -f $PREBUILT_DIR_DOSFSTOOLS_BASE)
	if [ -z "$resolved_path" -o ! -d "$resolved_path" ] ; then
		fatalError "No source folder in $PREBUILT_DIR_DOSFSTOOLS_BASE. You may want to get the source code from somewhere e.g.  git clone  https://github.com/ronpscg/dosfstools-static-builds.git $PREBUILT_DIR_DOSFSTOOLS_BASE"
	fi
	set_tools_src_dir # properly sets srcdir
	dod cp -a $PREBUILT_DIR_DOSFSTOOLS_BASE/$srcdir/usr/local/sbin/{fsck.fat,fatlabel} $2/sbin
}

main() {
	local dst=$1
	if [ ! -d "$dst" ] ;then
		fatalError "$dst does not exist"
	fi

	copy_selected_e2fsprogs $PREBUILT_DIR_E2FSPROGS_BASE $dst
	# The next is less likely to be needed, will probably wrap it in some config option...
	copy_selected_dosfstools $PREBUILT_DIR_DOSFSTOOLS_BASE $dst
}

commonScriptPrologueLogRunAndEpilogue $@
