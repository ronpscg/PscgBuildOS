# common file for some function definitions
#
# an obvious helper function
#
is_target_dir_empty() {
	if [ "$(ls -A $1)" = "" ] ; then
		return 0
	else
		return 1
	fi
}

#
# This is a wrapper function that deletes the $2 directory, and then links or copies $2 to $1 if it exists
#
# $1 source
# $2 target
# $3 reusal method (copy, symlink, hardlink)
# $4 if sudo - use sudo for linking. otherwise don't.
# $5 if allowlinktononexistent - will allow symlinking to a non existing path. if dontforce - will return without doing anything.
#	 Otherwise, if the source directory does not exist, will exit with a fatal error

# link strategy is a soft link, to allow using materials from other partitions.
#
# TODO check imager doesn't break due to it
#
remove_target_and_link_if_src_exists() {
	local src=$1
	local dst=$2
	local method=$3
	local SUDO=""
	local dontforce=false
	local allowlinktononexistent=false
	shift 3
	if [ "$1" = "sudo" ] ; then
		SUDO=sudo
		shift
	fi
	if [ "$1" = "dontforce" ] ; then
		dontforce=true
	elif [ "$1" = "allowlinktononexistent" ] ; then
		allowlinktononexistent=true
	fi

	if [ ! -d "$src" ] ; then
		if [ "$dontforce" = "true" ] ; then
			error "Your prebuilt materials dir at $src and it is allowed, but you may want to check you really meant this"
			return
		fi

		if [ "$method" = "symlink" -a "$allowlinktononexistent" = "true" ] ; then
			verbose "Will symlink $dst to a not yet existing path $src. We assume it was intentional"
		else
			fatalError "Your prebuilt materials dir at $src does not exist. If you hack, at least bother to configure properly!"
		fi
	fi

	if ! is_target_dir_empty "$dst" ; then
		warn "$dst exists and is not empty. Removing it and linking to another prebuilt instead"
	fi

	debug_do_or_die sudo rm -rf $dst

	case "$method" in
		symlink)
			verbose_do_or_die $SUDO ln -s $src $dst
			;;
		hardlink)
			# could also copy -al
			verbose_do_or_die $SUDO ln $src $dst
			;;
		copy)
			verbose_do_or_die $SUDO cp -a $src $dst
			;;
	esac
}
