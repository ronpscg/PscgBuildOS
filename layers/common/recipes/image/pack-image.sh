#!/bin/bash
#
# This recipe packages the image
#
main() {
	. $LOCAL_DIR/imager.buildconfig

	for script in $config_imager__staging_list_of_image_creation_scripts_to_run ; do
		info_do_or_die $LOCAL_DIR/staging/$script
	done

	if [ "$config_imager__staging_do_non_staging_stuff" = "false" ] ; then
		hardWarn "User opted to create images only in the non staging part"
		return
	fi

	for script in $config_imager__list_of_image_creation_scripts_to_run ; do
			info_do_or_die $LOCAL_DIR/$script
	done
}

commonScriptPrologueLogRunAndEpilogue $@