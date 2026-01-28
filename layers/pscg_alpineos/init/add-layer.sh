#!/bin/bash
#
# Compatible with: the pscg_alpineos training distro 
#
# This layer is responsible for:
# - installing an init framework if the user opts to add something that is not the busybox default (for Alpine minirootfs)
# - adding minimum configuration to it (exercises: what happens when it's not added...) in terms of tty access
#
#

main() {
	# about the next 'set' line:  less typing than adding || fatalError... everywhere. That's good if you do trivial things that are very unlikely to fail, and very easy to debug in case they do. Otherwise, careful using this shell option!
	set -euo pipefail

	cd $LOCAL_DIR

	for initframework in $config_pscg_alpineos__init_frameworks ; do
		if [ ! -f $LOCAL_DIR/${initframework}.sh ] ; then
			fatalError "Failed to find $initframework installation script. Are you sure you provided a supported framework?"
		fi

		banner_and_do $LOCAL_DIR/${initframework}.sh || fatalError "Failed to run main logic"
	done
}


commonScriptPrologueLogRunAndEpilogue $@