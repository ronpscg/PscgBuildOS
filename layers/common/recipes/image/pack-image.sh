#!/bin/bash
#
# This recipe packages the image
#
main() {
	. $LOCAL_DIR/imager.buildconfig

	for script in $config_imager__staging_list_of_image_creation_scripts_to_run ; do
		if [[ "$script" != /* ]]; then
			script=$LOCAL_DIR/staging/$script
		fi
		info_do_or_die $script
	done

	if [ "$config_imager__staging_do_non_staging_stuff" = "false" ] ; then
		hardWarn "User opted to create images only in the non staging part"
		return
	fi

	for script in $config_bsp__imager__pre_common_list_of_image_creation_scripts_to_run \
		$config_imager__list_of_image_creation_scripts_to_run \
		$config_bsp__imager__post_common_list_of_image_creation_scripts_to_run \
		; do
		if [[ "$script" != /* ]]; then
			script=$LOCAL_DIR/$script
		fi
		debug $script
		info_do_or_die $script
	done
}

commonScriptPrologueLogRunAndEpilogue $@
