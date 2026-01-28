#!/bin/bash
main() {
	verbose_do_or_die $LOCAL_DIR/common-busybox-sysvinit.sh
}

commonScriptPrologueLogRunAndEpilogue $@
