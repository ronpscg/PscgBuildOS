#
# Basic utils
# Compatible with ash (busybox shell). If something is Bash specific we will list it explicitly by testing $BASH
#
#

#
# Prints $1=<value of $1" assuming $1 is an environment variable
#
printvar() {
	echo $1=$(eval echo \$$1)
}

#
# Print all vars given as arguments
#
echo_vars() {
	for i in $@ ; do printvar $i ; done
}

#
# Print out the 'value' of a 'key'='value' tupple in a file. If the key does not exists, print nothing
# In bash it would be wiser, e.g., to create an array, read once the file at some points and keep it, but in ash you need to
# do other things (or use sed) so KISS
# $1 file
# $2 key to look for
#
get_value_by_key_file() {
	local file=$1
	local key=$2
	while read line ; do
		# Unless in quotes, ash will try and evaluate some of the lines. In bash there is no need for quotes
		[[ "$line" =~ "^#.*" ]] && continue
		if [ "$(echo $line | cut -d= -f1)" = "$key" ] ; then
			echo $line | cut -d= -f2
			return
		fi
	done < $file
}
