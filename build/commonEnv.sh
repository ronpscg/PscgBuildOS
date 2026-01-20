#
# Source this file. Do not execute it.
#
# This is a partial migration of some of The PSCG base stuff. Permission is happily and freely granted to use and redistribute this excerpts by Ron.
# Developing/Testing Notes: To set default values for your local environment, please create a localEnv.sh file and do not add it to source control
# if you do so, please make sure that your configuration values match the config file(!!!)
#
# We added logging functions with a very obvious format. You can modify the format (e.g., remove the SECONDS clause to ignore execution time statistics etc).
#
# The colored logic and echo -e seem to require bash so watch out for other shells
#
# Set any of these to an empty string to avoid e.g. logging with timestamps or profiling
#
# the "info" stuff is super unnecessary and is left in a quick hack mode in case someone else wants to modify it / is puzzled as per what is going on etc...
#
#
[ "$COMMON_ENV_HAS_ALREADY_BEEN_SOURCED" = "y" ] && type error >& /dev/null && return 0
export BUILD_TOP=$(readlink -f $(dirname $(readlink -f $BASH_SOURCE))/..)
export BUILD_TOP_COMMON=$(dirname $(readlink -f $BASH_SOURCE)) # TODO - not necessary AFAIK
source $BUILD_TOP_COMMON/commonFolders.sh
source $BUILD_TOP_COMMON/commonDefs.sh
source $BUILD_TOP_COMMON/common-utils/common-utils.sh

# It doesn't actually matter if we set them here or not, as long as the calling process sets them. This is left in case we want defaults in source control
: ${logFile=}
: ${logTag=}
: ${SPAWN_SHELL_ON_FATAL_ERROR="false"} # if true, a shell will be spawned on fatal error, so you can debug the problem. If false, the script will exit with an error code

# bash check, which would be very verbose, and is basically eliminated if we only check for "error". thing is that
# maybe there will bem more complicated environment that we would want to modify.
if [ "$SHELL" = "bash" ] ; then
	# I Am deliberately not grepping with -q. I want the colored feedback when I source this script from another build system, to easier avoid surprises when debugging
	checkFunctionName() {
		type $1 |& grep "type: $1: not found"
		if [ ! $? = 0 ] ; then
			echo $1 is already defined
			return 1
		fi
		return 0
	}


	checkFunctionNameInfo() {
		type $1 |& grep "type: $1: not found"
		if [ ! $? = 0 ] ; then
			echo $1 is already defined. let's see if it's $(which info)
			type $1 |& grep "$1 is $(which info)"
			if [ $? = 0 ] ; then
				echo will replace $1 with our own function rather than $(which info)
				return 0
			fi
			return 1
		fi
		return 0
	}

	checkFunctionName fatalError || exit 1
	checkFunctionName error || exit 1
	checkFunctionName warn || exit 1
	checkFunctionName debug || exit 1
	checkFunctionName debug_notsecure || exit 1
	checkFunctionName debug2 || exit 1
	checkFunctionName verbose || exit 1

	checkFunctionNameInfo info || exit 1
fi

DATECMD='date "+%y-%m-%d %H:%M:%S"'
touch $logFile 2>/dev/null || { echo "Failed to create log file $logFile. Please set it to a valid file path." ; exit 1; }
# Utility functions
fatalError() {
	# NOTE: BACKTRACE DOESN'T WORK WELL. Perhaps a trap would be better to make it more reliable(?)
	backtrace=""
	local deptn=${#FUNCNAME[@]}
    for ((i=1; i<$deptn; i++)); do
        local func="${FUNCNAME[$i]}"
        local line="${BASH_LINENO[$((i-1))]}"
        local src="${BASH_SOURCE[$((i-1))]}"
        backtrace="$backtrace $(printf '%*s' $i '')" # indent
        backtrace="$backtrace at: $func(), $src, line $line\n"
    done
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[41m[$(basename $0):] $@\x1b[0m $CURRENT_SCRIPT FAILED ( ${SECONDS}s)\n\x1b[33mBacktrace:\n$backtrace\x1b[0m]" | tee -a $logFile
	case "$SPAWN_SHELL_ON_FATAL_ERROR" in
		true|fork|spawn)
			warn "Spawning a shell for debugging purposes [rc: $?]. Please exit it to exit the build process"
			debug_shell
			;;
		exec)
			warn "Execing a shell for debugging purposes [rc: $?]. Please exit it to exit the build process"
			debug_shell_exec
		;;
	esac
	exit 1
}

error() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[31m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | tee -a $logFile
}

info() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[32m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | tee -a $logFile
}
warn() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[33m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | tee -a $logFile
}
debug() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[34m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | tee -a $logFile
}

# Used to output information that might be sensitive and needs refactoring at production (e.g. ssid, password, usernames maybe, etc.)
debug_notsecure() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[34m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | tee -a $logFile
}

debug2() {
	# don't log debug2 to file
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[34m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )"
}

verbose() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[35m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | tee -a $logFile
}

hardError() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[41m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | tee -a $logFile
}

hardInfo() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[42m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | tee -a $logFile
}

hardWarn() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[43m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | tee -a $logFile
}

hardDebug() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[44m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | tee -a $logFile
}

hardVerbose() {
	echo -e "$(eval $DATECMD) \x1b[21m${logTag}:\x1b[0m \x1b[45m[$(basename $0):] $@\x1b[0m ( ${SECONDS}s )" | tee -a $logFile
}

info_do() { info $@ ; $@ ; }
debug_do() { debug $@ ; $@  ; }
verbose_do() { verbose $@ ; $@ ; }
hard_info_do() { hardInfo $@ ; $@ ; }
hard_verbose_do() { hardVerbose $@ ; $@ ; }

# Yes style is different here, may change at some point or may not. was local for the kernel recipes...
info_do_or_die() {
        info $@
        "$@" || fatalError "Failed to $@"
}

verbose_do_or_die() {
        verbose $@
        "$@" || fatalError "Failed to $@"
}

debug_do_or_die() {
        debug $@
        eval "$@" || fatalError "Failed to $@"
}

info_eval_or_die() {
        info $@
        eval "$@" || fatalError "Failed to $@"
}

verbose_eval_or_die() {
        verbose $@
        eval "$@" || fatalError "Failed to $@"
}

debug_eval_or_die() {
        verbose $@
        eval "$@" || fatalError "Failed to $@"
}


source_file_or_die() {
	debug "sourcing $@"
	eval . $@ || fatalError "Failed to source $@"
}

source_if_exists() {
	if [ -f "$1" ] ; then
		debug "sourcing $@"
		eval . $@ || fatalError "Failed to source $@"
	else
		debug "$1 does not exist. skip sourcing"
	fi
}

# do or die without printing a banner
do_or_die() {
	$@ || fatalError "Failed to $@";
}

eval_or_die() {
	eval $@ || fatalError "Failed to $@";
}

dod() {
	do_or_die $@
}

call_if_exists() {
	type $1 &>/dev/null
	if [ $? = 0 ] ; then
		$@
	fi
	# return non zero if the command does not exist
}

printvar() { echo $1: $(eval echo \$$1) ; }
printvars() { for i in $@ ; do printvar $i ; done ;}
printvars_sorted() {
	# trivial implementation, don't use it for huge sets!
	printvars $@ | LC_COLLATE=C sort
}
export -f printvar printvars printvars_sorted
export -f call_if_exists

SCRIPTSHOME=$PWD
if [ -f $SCRIPTSHOME/helpers/localEnv.sh ] ; then
	debug2 Sourcing local environment script
	. $SCRIPTSHOME/helpers/localEnv.sh
fi


export DATECMD

#
# $1 layer path
#
add_layer() {
	info_do_or_die $1/add-layer.sh
}

banner_and_do() {
        hardInfo "$@"
        $@
}

sourcedLocalDir() {
	LOCAL_DIR=$(readlink -f $(dirname ${BASH_SOURCE[1]}))
}

currentLocalDir() {
	LOCAL_DIR=$(readlink -f $(dirname $0))
}

announceCurrentScript() {
	CURRENT_SCRIPT=$(readlink -f $0)
	hardInfo "NOW RUNNING: $(readlink -f $0) (PWD=$PWD)"
}

#
# side effect: sets LOCAL_DIR to the directory containing the current script, and LOCAL_PREV_DIR to the working directory at the time of calling this function
#
commonScriptPrologue() {
	LOCAL_PREV_DIR=$PWD
	currentLocalDir
	announceCurrentScript
}

#
# side effect: returns to LOCAL_PREV_DIR
#
commonScriptEpilogue() {
	local rc=$? # in our system it would mean 0 unless someone broke conventions
	hardInfo "FINISHED RUNNING: $(readlink -f $0) (PWD=$PWD --> $LOCAL_PREV_DIR) rc=$rc"
	cd $LOCAL_PREV_DIR
	exit $rc
}

commonScriptPrologueLogRunAndEpilogue() {
	commonScriptPrologue 					# announces script and sets LOCAL_DIR
	export logTag=$(basename $LOCAL_DIR)	# may want to put it in inner or more outer scope
	cd $LOCAL_DIR							# start working at the script directory. This is not necessary for all scripts, but can be useful for some
	main $@									# call the main function
	commonScriptEpilogue					# just say we're done and change directory to what it was proir to executing this script
}


# Note about shells and terminals: we could decide on behavior for non interactive shells.
# Checking [ -t 0 ] is not enough, as it will return true for running from a shell inside another script.
# Essentially it shouldn't matter, as running a shell should just fail with an error code, and should not affect a script anyway
# unless it is a debug_shell - and then it should have not been run anyhow in non (super) temporary code
# May add a specific logic/check for that, but it's not important now, and it is not necessary.
debug_shell() {
	if [ -n "$BASH" ] ; then
		debug ${@-"Running bash shell"}
		# hacky and good enough. You can and should ignore the readonly variables
		declare -p > $TMP_TOP/debug_stop_vars_to_source.env
		declare -f >> $TMP_TOP/debug_stop_vars_to_source.env
		bash -c "source $TMP_TOP/debug_stop_vars_to_source.env ; exec bash"
	elif [ -n "$ZSH_VERSION" ] ; then
		debug "Running zsh shell"
		zsh
	else
		debug "Running sh shell"
		sh
	fi
}

debug_shell_exec() {
	if [ -n "$BASH" ] ; then
		debug ${@-"Running bash shell"}
		exec bash
	elif [ -n "$ZSH_VERSION" ] ; then
		debug "Running zsh shell"
		exec zsh
	else
		debug "Running sh shell"
		exec sh
	fi
}

#
# $1 get compound var
# An utility function used to get the value of a shell variable whose name is compound and is built at runtime
# For example:
# e.g. get_compound_var config__imager__ext_partition_${label}_size_bytes
#
get_compound_var() {
	local varname=$1
	eval echo \$$(eval "echo $varname")
}
export -f get_compound_var

#
# like fatalError, but not for all levels, only for the caller (unless the global flag is set)
#
fatal_debug() {
	debug "fatal_debug: $@"
	local prev_spawn_shell_on_fatal_error=$SPAWN_SHELL_ON_FATAL_ERROR
	debug_shell "\x1b[31;44;5m\n\nRunning a debug shell.\n\x1b[25;37mReason:\n$@\x1b[0m"
	SPAWN_SHELL_ON_FATAL_ERROR=$prev_spawn_shell_on_fatal_error
	fatalError "$@"
}

# The following exports are set so that children scripts benefit from the facilities in this file as well
# Exporting functions is (probably) bash only. Do it for the sake of child shell processes
if [ ! "$BASH" = "" ] ; then
	export -f fatalError error warn info debug debug_notsecure debug2 verbose hardError hardWarn hardInfo hardDebug hardVerbose
	export -f add_layer banner_and_do
	export -f info_do_or_die verbose_do_or_die debug_do_or_die source_file_or_die do_or_die dod info_eval_or_die verbose_eval_or_die debug_eval_or_die eval_or_die
	export -f info_do debug_do verbose_do hard_info_do hard_verbose_do
	export -f sourcedLocalDir currentLocalDir announceCurrentScript commonScriptPrologue commonScriptEpilogue commonScriptPrologueLogRunAndEpilogue $@
	export -f debug_shell debug_shell_exec
	export -f fatal_debug
fi
export SPAWN_SHELL_ON_FATAL_ERROR

export COMMON_ENV_HAS_ALREADY_BEEN_SOURCED=y
