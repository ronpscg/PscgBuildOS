#!/bin/bash
#
# This script sets up the first dependencies.
# It assumes that you have setup the secboot related packages, and the apt-get... here are in addition to those (this is arbitrary - as the U-Boot stuff are not in this project, and
# I don't know when or if I will get them in (My appologies, there are some things that are harder to separate from projects)

: ${BASE_DIR=$HOME/dev}
: ${BASE_EXTERNAL_PROJECTS_BUILD_DIR=${BASE_DIR}/pscgdebos-external-projects-build}
: ${BUILD_SYSTEM_DIR=${BASE_DIR}/otaworkshop/PscgBuildOS}
: ${BUILD_SYSTEM_HELPER_SCRIPTS_DIR=${BASE_DIR}/otaworkshop/PscgBuildOS-helpers}
: ${BUILD_SYSTEM_EXTRA_LAYERS_DIR=${BASE_DIR}/otaworkshop/PscgBuildOS-extra-layers}
: ${BUILD_SYSTEM_OOT_DIR=${BASE_DIR}/otaworkshop/oot}
: ${BUILD_SYSTEM_OTA_DIR=${BUILD_SYSTEM_OOT_DIR}/ota-update-richos}

install_packages() {
	# Additional tools
	sudo apt-get install -y mtools
	# Note: more toolchains are available for most of the components directly from your distro. However, neither Debian, Alpine, or other systems support all architectures, all ABI's etc.
	#       we therefore recommend here a subset. For research purposes that require, e.g. a rootfilesystem reuse, you may use the respective projects (likely not open-sourced), or tailor them yourself.
	sudo apt-get install -y gcc-aarch64-linux-gnu  gcc-arm-linux-gnueabihf gcc-x86-64-linux-gnu gcc-i686-linux-gnu gcc-riscv64-linux-gnu gcc-powerpc64le-linux-gnu gcc-sparc64-linux-gnu gcc-s390x-linux-gnu 
	sudo apt-get install -y qemu-system qemu-user-static

	if [ "$(lsb_release -r | cut -f 2)" = "24.04" ] ; then
		echo "gcc-loongarch is not a meta package in Ubuntu 24.04. Installing a specific version instead. If you choose to build on this distro, you may want to keep track of the installed toolchain paths"
		echo "Also take into consideration that you may need to install qemu-efi-loongarch64"
		sudo apt-get install -y gcc-14-loongarch64-linux-gnu
	else
		sudo apt-get install -y gcc-loongarch64-linux-gnu qemu-efi-loongarch64
	fi
}

# Builds of other projects (usually by myself) and firmware
clone_external_projects() {
	# Getting the repos we already have
	# Both should really have gotten there through the downloads mechanism
	mkdir -p ${BASE_EXTERNAL_PROJECTS_BUILD_DIR}
	git clone  https://github.com/ronpscg/e2fsprogs-static-builds.git ${BASE_EXTERNAL_PROJECTS_BUILD_DIR}/e2fsprogs-static-builds
	git clone  https://github.com/ronpscg/dosfstools-static-builds.git ${BASE_EXTERNAL_PROJECTS_BUILD_DIR}/dosfstools-static-builds
	git clone  https://github.com/ronpscg/kexec-tools-static-builds.git ${BASE_EXTERNAL_PROJECTS_BUILD_DIR}/kexec-tools-static-builds
	git clone  https://github.com/ronpscg/tinyalsa-static-builds.git ${BASE_EXTERNAL_PROJECTS_BUILD_DIR}/tinyalsa-static-builds
	git clone  https://github.com/ronpscg/smallos-assets.git ${BASE_EXTERNAL_PROJECTS_BUILD_DIR}/smallos-assets

	git clone git://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git ${BUILD_SYSTEM_OOT_DIR}/linux-firmware --depth=1
}

# projects that are external to the main build like the build helper scripts, and the OTA project (that might go into the build itself, or the external layers
# since they are in a private repository, I am having some haks here
clone_more_oot_projects() {
	git clone https://github.com/ronpscg/PscgBuildOS-extra-layers.git $BUILD_SYSTEM_EXTRA_LAYERS_DIR
	# ota is currently requested by: distros/common-linux/build-distro-common-linux.sh       (will likely move to common layers)
	git clone  https://github.com/ronpscg/PscgBuildOS-ota-update-richos.git $BUILD_SYSTEM_OTA_DIR
	git clone https://github.com/ronpscg/PscgBuildOS-helpers.git $BUILD_SYSTEM_HELPER_SCRIPTS_DIR

	if [ "$(hostname)" = "ronmsi" ] ; then
		:
	else
		:
	fi
}

main() {
	set -euo pipefail
	install_packages
	clone_external_projects
	clone_more_oot_projects
}

main $@
