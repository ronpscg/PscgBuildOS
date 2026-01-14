#
# A place for some common utlis added relatively late in the project
#

#
# Copies $1 into $3 from $2, creating the parent directories at $3 as needed
#
# $1 src file subdir within the directory provided at $2
# $2 src file directory (e.g. $PREBUILT_DIR_LINUX_FIRMWARE_BASE)
# $3 dst directory
# [$4] if sudo - use sudo to copy. otherwise, don't.
#
# Can make an util function as it should be quite common here
#
copy_one_file_from_src_to_dst_creating_directories() {
	local srcfile=$1
	local srcdir=$2
	local dstdir=$3
	local parentreldir=$(dirname $srcfile)
	local SUDO=${4-""}

	[ -f "$srcdir/$srcfile" ] || fatalError "$srcdir/$srcfile does not exist (dir=$srcdir ; file=$srcfile)"
	[ -d "$dstdir" ] || fatalError "$dstdir does not exist"

	mkdir -p $dstdir/$parentreldir || fatalError "Failed to create $parentreldir"
	verbose_do_or_die cp -a $srcdir/$srcfile $dstdir/$srcfile || fatalError "Failed to copy $srcdir/$srcfile to $dstdir"
}
export -f copy_one_file_from_src_to_dst_creating_directories
