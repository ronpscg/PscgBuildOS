#
# More common wrapping functions relevant for all distros. All distros can override them, and so can all recipes
# Careful about the exporting. In some cases we do reuse for brevity, but namespaces are very helpful to avoid
# mistake while modifying and adding to a code base such as this
#
do_fetch() (
	local prevLogTag=$logTag
	logTag=build-distro:${config_distro}
	base_do_fetch
	logTag=$prevLogTag
)

do_unpack() (
	local prevLogTag=$logTag
	logTag=build-distro:${config_distro}
	base_do_unpack
	logTag=$prevLogTag
)



export -f do_fetch do_unpack