additional_parse_args() {
	arg=$1
	case $arg in
		debug_run_commands_from_filesystem)
			export debug_run_commands_from_filesystem=true
			;;
		dontformatemmc)
			export dontformatemmc=true
			;;
		abtestimageoverlaystrategy=*)
			export AB_TEST_IMAGE_OVERLAY_STRATEGY="${arg#*=}"
			;;
		fallbacktonooverlaystrategy=*)
			export FALLBACK_TO_NO_OVERLAY_STRATEGY="${arg#*=}"
			;;
		*)
			;;
	esac
}

#
# Spawn a shell in a new process. Allows one to exit the shell and continues execution
#
spawn_shell() {
	echo "Spawning shell $TTY_SHELL_JOB_CONTROL_PREFIX"
	$TTY_SHELL_JOB_CONTROL_PREFIX sh || fatalError "Cannot open debug shell"
}

#
# Execs shell. There is no going back to the logic after this
#
exec_shell() {
	echo "Execing shell $TTY_SHELL_JOB_CONTROL_PREFIX"
	exec $TTY_SHELL_JOB_CONTROL_PREFIX sh
}

#
# The idea here, in case of a system with multiple serial consoles or virtual terminals is to ensure a process is
# not receiving key strokes if, e.g. systemd, is opening another getty on top of it
#
# This may fit better next to the files handling tty, but it is a good practice to be aware of it so I am keeping it
# in good neighborship with spawn_shell and exec_shell
#
kill_currently_opened_shell_on_ttys() {
	warn "Undoing previous terminal work if terminals were opened on vts"
	warn "Killing all sh instances. This is *safe* as long as /init itself is busybox and not sh"
	pkill -9 sh
}

#
# This method runs commands and executables on specific predefined paths. It assumes everything is mounted.
# The objective is to be able to update the ramdisk behavior while running the ramdisk
# $1: folder to look for files at
#
# Use cases: source a script and/or run a binary from emmc boot folder, installer media, or ota extract directory
#
# We assume that if an "autorun.sh" file exists, it will be sourced
# We assume that if an autorun file exists, it will be exec-ed (for example: a self extracting script that may want to switch_root, etc...)
#
# This is absolutely not necessary, so you can remove all calls to it if you want.
#
#
debug_run_commands_from_filesystem() {
	[ "$debug_run_commands_from_filesystem" = "true" ] || return 0
	if [ ! -d "$1" ] ; then
		debug "Nothing to execute on $1"
		return 0
	fi

	if [ -f $1/autorun.sh ] ; then
		info "$FUNCNAME sourcing autorun.sh"
		source $1/autorun.sh $1
		return $?
	fi

	if [ -x $1/autorun ] ; then
		info "$FUNCNAME exec-ing autorun"
		exec $1/autorun $1

		return 1
	fi
}