#
# Mount basic kernel virtual file systems
# With the "right" kernel configuration options, you will not need a userspace helper to populate the devices under /dev once calling this function
#
mount_basic_virtual_filesystems() {
	mount -t devtmpfs  devtmpfs  /dev
	mount -t proc      proc      /proc
	mount -t sysfs     sysfs     /sys
	mount -t tmpfs     tmpfs     /tmp
	if [ ! "$docker" = "true" ] ; then
		mkdir /dev/pts
		mount -t devpts -o noexec,nosuid,gid=5,mode=0620 devpts /dev/pts || :
	else 
		mount -t devpts -o noexec,nosuid,gid=5,mode=0620 devpts /dev/pts || :
	fi
}

#
# Populate /dev nodes. 
# Note:
# 	For a basic usage there is no need to use mdev -s if CONFIG_DEVTMPFS=y  CONFIG_DEVTMPFS_MOUNT=y
# 	which are essentially the true for all defaults in recent kernels
#
enumerate_nodes_with_mdev() {	
	mdev -s
}