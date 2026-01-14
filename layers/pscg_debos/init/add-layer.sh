#!/bin/bash
#
# Compatible with: the debos training distro (do not confuse with the debos package, we became aware of years after this template O_o)
#
# This layer is responsible for:
# - installing a lightweight init framework (i.e. not systemd)
# - adding minimum configuration to it (exercises: what happens when it's not added...) in terms of tty access
#
# To make things easier, more readable, and to allow the builder to either install several init frameworks (including systemd, but it did get another layer),
# or select one of their choice*
#
# *We do assume that the apt repositories are populated. e.g. that in Ubuntu universe had been added (or perhaps multiverse)
#

main() {
	# about the next 'set' line:  less typing than adding || fatalError... everywhere. That's good if you do trivial things that are very unlikely to fail, and very easy to debug in case they do. Otherwise, careful using this shell option!
	set -euo pipefail

	cd $LOCAL_DIR

	for initframework in $config_pscgdebos__init_frameworks ; do
		if [ ! -f $LOCAL_DIR/${initframework}.sh ] ; then
			fatalError "Failed to find $initframework installation script. Are you sure you provided a supported framework?"
		fi

		banner_and_do $LOCAL_DIR/${initframework}.sh || fatalError "Failed to run main logic"
	done
}


commonScriptPrologueLogRunAndEpilogue $@