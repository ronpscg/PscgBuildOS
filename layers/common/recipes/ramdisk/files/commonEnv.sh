#
# Source this file. Do not execute it.
#
# This is a partial migration of some of The PSCG base, written by Ron Munitz.
# Permission is happily and freely granted to use and redistribute, while keeping the above line and credits in tact.
# Developing/Testing Notes: To set default values for your local environment, please create a localEnv.sh file and do not add it to source control
# if you do so, please make sure that your configuration values match the config file!
#
# We added logging functions with a very obvious format. You can modify the format (e.g., remove the SECONDS clause to ignore execution time statistics etc).
#
# The recommended shells are either bash or busybox. If you run under dash, change "source" to "." and expect coloring issues.
#

# Set any of these to an empty string to avoid e.g. logging with timestamps or profiling
: ${logSink1=/dev/null} # no need to print to /dev/console . Avoid double prints, it prints to the console anyway (when you are, e.g. in serial)
: ${logSink2=/dev/null}
: ${logFile1=/dev/null}
: ${logFile2=/dev/null}
: ${logTag=/init}

DATECMD='date "+%y-%m-%d %H:%M:%S"'
TEECMD=" tee $logSink1  | tee $logSink2 | tee -a $logFile1 | tee -a $logFile2 || :"

# Utility functions

error() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[31m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
	bsp_hmi_failure
}
info() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[32m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}
warn() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[33m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}
debug() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[34m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}

debug2() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}DEBUG2:\x1b[0m \x1b[34m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}

verbose() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[35m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}
fatalError() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[41m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
	bsp_hmi_fatal_failure
	exit 1
}
hardError() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[41m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
	bsp_hmi_failure
}
hardInfo() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[42m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}
hardWarn() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[43m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}
hardDebug() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[44m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}
hardVerbose() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[45m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | eval $TEECMD
}

info_do() { info $@ ; $@ ; }
verbose_do() { verbose $@ ; $@ ; }
hard_info_do() { hardInfo $@ ; $@ ; }
hard_verbose_do() { hardVerbose $@ ; $@ ; }

# Note the syntax. In busybox sh, source <file> || <cmd> does not work, so we need to check the return value in another statement
info_do_or_die() { info $@ ;  $@ ; [ $? = 0 ] || fatalError $@ ; }
debug_do_or_die() { debug $@ ; $@ ; [ $? = 0 ] || fatalError $@ ; }
verbose_do_or_die() { verbose $@ ; $@ ; [ $? = 0 ] || fatalError $@ ; }
do_or_die() { $@ ; [ $? = 0 ] || fatalError $@ ; }
dod() { do_or_die $@ ; }
debug_do() { debug $@ ; $@  ; }

# verbose print, upon failure open a shell [ either as a subprocess or... ]
# after the shell, quit, meaning that if done in init - the kernel will panic, which is intentional
dod_shell() {
	 $@
	 if ! [ $? = 0 ] ; then
		hardError "FAILED: $@ . Opening recovery shell"
		call_if_exists bsp_stop_current_audio_activities
		if [ ! "$docker" = "true" ] ; then
			setsid cttyhack sh
		else
			sh
		fi
		exit 1
	fi
}

#
# This is an helper function for logging and then invoking a shell, with different log levels
# $1: the function to call for logging
# $2-$#: the code to log and execute
#
loglevel_dod_shell() {
	local level=$1
	shift
	$level "$@"
	dod_shell "$@"
}

call_if_exists() {
	type $1 &>/dev/null
	if [ $? = 0 ] ; then
		$@
	fi
	# return non zero if the command does not exist
}

#
#
# The error return functions are very tricky, as there are no nested returns (as opposed to e.g. break <n>, which does not go out of the function scope)
# So two versions are presented: one that returns the error (and the error needs to be checked) and another that exits, meaning that the caller
# must be in subshell
#

#
# Important: put message in quotes, and either call with one parameter, or ensure the second parameter is an integer - we will not error check this for now!
#
errorReturn() {
	error $1
	if [ -n "$2" ] ; then
		return $2
	else
		return 1
	fi
}

#
# Important: put message in quotes, and either call with one parameter, or ensure the second parameter is an integer - we will not error check this for now!
#
warnReturn() {
	warn $1
	if [ -n "$2" ] ; then
		return $2
	else
		return 1
	fi
}

#
# Important: put message in quotes, and either call with one parameter, or ensure the second parameter is an integer - we will not error check this for now!
#
hardErrorReturn() {
	hardError $1
	if [ -n "$2" ] ; then
		return $2
	else
		return 1
	fi
}
#
# These should be started from a subshell. If called from within a function, make sure you define the function body within (...) and not with {...}
#
errorExitScope() {
	error $1
	if [ -n "$2" ] ; then
		exit $2
	else
		exit 1
	fi
}
warnExitScope() {
	warn $1
	if [ -n "$2" ] ; then
		exit $2
	else
		exit 1
	fi
}
hardErrorExitScope() {
	hardError $1
	if [ -n "$2" ] ; then
		exit $2
	else
		exit 1
	fi
}

#
# This gets another function since it would be easier to identify the logging elsewhere, for when we want to remove it (which we would for several reasons explained in the code)
# TODO: refactor it. I just wanted to have the option to call it from several places, and avoid the annoying
#	"file not found" etc. after unmounting
#
reInitLogsAndStopPersistentLogging() {
	reinit=false
	if [[ "$logFile2" =~ "$INSTALLER_MEDIA_MOUNT_POINT" ]] ; then
		reinit=true
	elif [[ "$logFile2" =~ "/mnt/ota/" ]] ; then
		reinit=true
	fi

	if [ "$reinit" = "true" ] ; then
		set -a
		logFile2=/dev/null
		. /commonEnv.sh
		set +a
	fi
}

#
# This is added because chroot persists over docker TODO this is probably because there is some line doing somethign somewhere...
# $1 mount point (or folder) to stop logging to. will stop logging to all log files if they exist
stop_logging() {
	if [ -n "$1" ] ; then
		if [[ "$logFile1" =~ "$1" ]] ; then
			verbose "Stop logging to $logFile1 (rd)"
			logFile1=/dev/null
			. /commonEnv.sh
		fi
		if [[ "$logFile2" =~ "$1" ]] ; then
			verbose "Stop logging to $logFile2 (rd)"
			logFile2=/dev/null
			. /commonEnv.sh
		fi
		return
	fi

	verbose "Stop logging to all files (rd)" # initramfs, rd just as a hint, maybe it's used as inird, or as a rootfs
	logFile1="/dev/null"
	logFile2="/dev/null"
	unset TEECMD
}

#
# This is made to have a common place for scripts which are not sourced to easily get the required hardware API usage
# functions (e.g. show leds, play sound etc.), that does not require any initialization
# (mostly since we do not want errors in them killing init, when developing the code in case we miss some error cases)
#
source_hardware_dependent_functions() {
	if [ -z $bsp ] ; then
		error "No bsp is specified. Hardware specific function support is disabled"
		return
	fi

	# sourcing to avoid exporting.  This means extra care needs to be taken with errors
	local filelist="bsp-functions.sh"
	local prefix="/init-helpers/bsp/$bsp/"
	local bsp_files_to_source=""
	
	for f in $filelist; do
		bsp_files_to_source="$bsp_files_to_source /init-helpers/bsp/common/$f"
  		bsp_files_to_source="$bsp_files_to_source $prefix$f"
	done

	for f in $bsp_files_to_source ; do
		if [ ! -f $f  ] ; then
			warn "$f does not exist"
			# TODO: dod_shell doesn't work for source, I don't know why. Perhaps in ash it quits after failing to source dod_shell "source $f"
			bsp_hmi_fatal_failure
		else
			dod_shell source $f
		fi
	done
}

# The following exports are set so that children scripts benefit from the facilities in this file as well
# Exporting functions is (probably) bash only. Do it for the sake of child shell processes
export fatalError error warn info debug verbose
export DATECMD


export COMMON_ENV_HAS_ALREADY_BEEN_SOURCED=y
