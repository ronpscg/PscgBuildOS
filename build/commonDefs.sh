# commonDefs.sh - Common definitions for the build system
#
# Some useful constants are put here, so that they can be used in other scripts, as well as
# in the caller to the build system, whether it is the shell, or a wrapping helper shell script
#
export BYTES_PER_SECTOR=512
export BYTES_PER_MIB=$((1024*1024))
export BYTES_PER_GIB=$((1024*1024*1024))
export SECTORS_PER_MIB=$(($BYTES_PER_MIB/$BYTES_PER_SECTOR))
export SECTORS_PER_GIB=$(($BYTES_PER_GIB/$BYTES_PER_SECTOR))