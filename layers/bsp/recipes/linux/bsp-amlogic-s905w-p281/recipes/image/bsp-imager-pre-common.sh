#!/bin/bash
main() {
	if [ "$config_bsp__bootloader" = "extlinux" ] ; then
		info "Adding extlinux to the removable media boot materials"
		debug $(get_layer_top ${config_bsp_layer})
		verbose_do_or_die cp -a $(get_layer_top ${config_bsp_layer})/recipes/bootloaders/extlinux-removablemedia/extlinux ${distro__image_materials_removable_media_specifics_dir}/

		info "Adding extlinux to the installables boot materials"
		debug $(get_layer_top ${config_bsp_layer})
		verbose_do_or_die cp -a $(get_layer_top ${config_bsp_layer})/recipes/bootloaders/extlinux-emmc/extlinux ${distro__image_materials_installables_bootfs_dir}/
	fi
}

commonScriptPrologueLogRunAndEpilogue $@
