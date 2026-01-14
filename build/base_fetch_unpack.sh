# The default for fetch will be donothing, to allow fully offline builds by default
: ${fetch_existing_repo_update_command="git pull --rebase"} # Can set it to nothing
: ${fetch_to_existing_folder_strategy="donothing"} # donothing|delete|checkout|update|update_and_checkout
: ${fetch_clone_strategy="fullclone"} # copy|fullclone|shallowclone. Read comments carefully below
: ${fetch_commit=""}
: ${fetch_clone_flags=""}

# The default for unpack is to update and checkout, to allow a build update in case the developer is working on it
: ${unpack_existing_repo_update_command="git pull --rebase"} # Can set it to nothing
: ${unpack_to_existing_folder_strategy="update_and_checkout"} # donothing|delete|checkout|update|update_and_checkout
: ${unpack_clone_strategy="shallowclone"} # copy|fullclone|shallowclone. Read comments carefully below
: ${unpack_commit=$fetch_commit} # The assumption is that only one commit matters (and actually only for unpacking, if fetch uses full clones as it should), but you can modify it
: ${unpack_clone_flags=""}

export fetch_existing_repo_update_command fetch_to_existing_folder_strategy fetch_clone_strategy fetch_commit fetch_clone_flags
export unpack_existing_repo_update_command unpack_to_existing_folder_strategy unpack_clone_strategy unpack_commit unpack_clone_flags

#
# Handles all kinds of cases in case the fetch or unpacking directory ($1) exists and we want to unpack a git repo
# the function will not clone a repo, but rather update it, delete the folder, checkout a commit, or do nothing
# The function assumes that the working directory is $1, and it is the responsibility of the caller to handle its paths
#
# The function is quite generic in order to allow different startegies for both fetch and unpack (although it is an overkill - but one that can save a great amount of space...)
#
# $1 destination folder to clone to
# $2 fetch_or_unpack - fetch|unpack  - used to set some variables according to some global variables
#
# The function returns 0 if no further cloning is to be done, and 1 otherwise
#
base_fetch_unpack_git_handle_existing_folder() {

	local dst=$1
	local fetch_or_unpack=$2

	local existing_repo_update_command=$(eval echo \$$(echo ${fetch_or_unpack}_existing_repo_update_command))
	local existing_folder_strategy=$(eval echo \$$(echo ${fetch_or_unpack}_to_existing_folder_strategy))
	local clone_strategy=$(eval echo \$$(echo ${fetch_or_unpack}_clone_strategy))
	local commit=$(eval echo \$$(echo ${fetch_or_unpack}_commit))

	if [ ! -d "$dst/.git" ] ; then
		fatalError "You are trying to fetch a git folder into what was previously [a link to] an extracted tarball folder, or a folder without a .git subfolder . If you intended to do so, please remove $unpack_dest_path manually, and redo the operation"
	fi

	local is_shallow=false
	# piping the git log through wc for a Linux kernel or Android build will take a long time. piping it to head is immediate
	if [ "$(git log --pretty=oneline | head -2 |  wc -l)" = "1" ] ; then
		is_shallow=true
	fi
	if [ "$is_shallow" = "true" -a ! "$clone_strategy" = "shallowclone" ] ; then
		fatalError "You are trying to unshallow a shallow clone. Please unshallow the clone yourself, or delete $dst to ensure you kno what you are doing"
	fi
	if [ ! "$is_shallow" = "true" -a "$clone_strategy" = "shallowclone" ] ; then
		error "You are trying to shallow an unshallow clone. We won't let you do that, but just let you proceed as you probably don't even care. If you do, you will delete $dst yourself and rebuild"
	fi

	case $existing_folder_strategy in
			delete)
				warn "$dst existed. removing it and unpacking again"
				debug_do_or_die rm -rf $dst
				return 1
				;;
			update)
				warn "$dst existed. Updating repo"
				debug_do_or_die $existing_repo_update_command
				return 0
				;;
			update_and_checkout)
				verbose "$dst existed. Updating repo and checking out commit if provided"
				debug_do_or_die $existing_repo_update_command
				# could fallthrough instead of repeating the checkout code, but the messages are different so I preferred to duplicate
				if [ -n "$commit" ] ; then
					debug_do_or_die git checkout $commit
				else
					warn "$dst existed but no commit was provided. Skipping ${fetch_or_unpack}ing"
					return 0
				fi
				;;
			checkout)
				if [ -n "$commit" ] ; then
					verbose $dst existed. checking out
					debug_do_or_die git checkout $commit
					return 0
				else
					warn "$dst existed but no commit was provided. Skipping ${fetch_or_unpack}ing"
					return 0
				fi
				;;
			donothing|*)
				warn "$dst existed. Skipping ${fetch_or_unpack}ing"
				return 0
				;;
		esac
}

#
# fetch a git repo from the remote repository.
# this is implemented in a simpler way than the unpacking, to encourage you to only fetch full clones, and keep the repo as is. You can
# easily understand the logic and do things like in the unpacking if you want to, which is why we provided the preparation code for a unified flow for both
#
base_fetch_git() {
	local dst=$fetch_local_target_path
	if [ -d $fetch_local_target_path ] ; then
		# The next couple of lines rely on a function that can return non-zero also when it is not an error case
		# If 0 we will proceed with the cloning. Otherwise, we will return now.
		# To be easier on the reader, we change directory and not do return codes in a subshell. a reall error would exit
		cd $fetch_local_target_path || exit 1
		if base_fetch_unpack_git_handle_existing_folder $fetch_local_target_path fetch ; then
			cd - &> /dev/null
			warn "$fetch_local_target_path existed. Skipping cloning from internet. You may want to update your scripts if you want to automagically pull the repositories, but we will not allow that now for the sake of (more) reproducible builds (i.e., imagine upstream rebases...)"
			( cd $fetch_local_target_path && verbose "Head of your git tree: $(git log --pretty=oneline --abbrev-commit | head -1)" ) || fatalError "Something was wrong with the logic or you cloned an empty git tree"
			return
		else
			cd - &> /dev/null
			verbose "Proceeding unpacking git"
		fi
	fi

	info "Cloning repo: $fetch_remote_uri --> $fetch_local_target_path"
	debug_do_or_die git clone $fetch_flags $fetch_remote_uri $fetch_local_target_path || fatalError "Failed to clone repository"

	( cd $fetch_local_target_path && verbose "Head of your git tree: $(git log --pretty=oneline --abbrev-commit | head -1)" ) || fatalError "Something was wrong with the logic or you cloned an empty git tree"

}

base_unpack_git() {
	local dst=$unpack_dest_path
	if [ -d "$dst" ] ; then
		# The next couple of lines rely on a function that can return non-zero also when it is not an error case
		# If 0 we will proceed with the cloning. Otherwise, we will return now.
		# To be easier on the reader, we change directory and not do return codes in a subshell. a reall error would exit
		cd $dst || exit 1
		if base_fetch_unpack_git_handle_existing_folder $unpack_dest_path unpack ; then
			cd - &> /dev/null
			( cd $dst && verbose "Head of your git tree: $(git log --pretty=oneline --abbrev-commit | head -1)" ) || fatalError "Something was wrong with the logic or you cloned an empty git tree"
			return
		else
			cd - &> /dev/null
			verbose "Proceeding unpacking git"
		fi
	fi



	# It is more straightforward to avoid the flags below, especially if you want to do some work on the checked out tree
	# if you don't clone the entire tree you need to do more work (e.g. unshallow), and if you want to check out
	# a specific commit, you will not be able to do so without further hacking.
	# I did take care of a shallow clone for a specific commit for you, but if you happen to run it on an
	# ancient version of git, you can forget about shallow clones of a specific commit.
	local lcf=$unpack_clone_flags # local clone flags
	local lcp="file://"   # protocol.

	case $unpack_clone_strategy in
		copy)
			# Can also copy other dot files and exclude .git but I chose to avoid it for now for brevity
			warn "Use the copy strategy only if you don't need to work with git, and you need the top of the tree(!!)"
			do_or_die mkdir -p $unpack_dest_path
			debug_do_or_die cp -a $fetch_local_target_path/* $unpack_dest_path
			return
			;;
		shallowclone)
			lcf="--depth=1"
			lcp="file://"
			;;
		fullclone)
			lcf=""
			lcp=""
			;;
		*)
			fatalError "Unsupported unpack_clone_strategy $unpack_clone_strategy"
			;;
	esac

	if [ -n "$fetch_commit" ] ; then
		lcf="$lcf -b $fetch_commit"
	fi

	info "Cloning local repo: $fetch_local_target_path --> $unpack_dest_path $lcf"
	debug_do_or_die git clone ${lcf} ${lcp}$fetch_local_target_path $unpack_dest_path || fatalError "Failed to local clone repository"

	( cd $unpack_dest_path && verbose "Head of your git tree: $(git log --pretty=oneline --abbrev-commit | head -1)") || fatalError "Something was wrong with the logic or you cloned an empty git tree"
}

base_fetch_tarball() {
	if [ ! -d "$config_toplevel__downloads_base_path" ] ; then
		fatalError "$config_toplevel__downloads_base_path does not exist."
	fi

	if [ -f "$fetch_local_target_path" -a -n "$fetch_expected_sha256" ] ; then
		if [ "$(sha256sum $fetch_local_target_path | cut -d ' ' -f 1)" = "$fetch_expected_sha256" ] ; then
			verbose "Already have the tarball at $fetch_local_target_path. Skipping tarball downloading from the internet ($fetch_expected_sha256)."
			return
		else
			warn "Existing tarball does not have the expected sha256sum. Will download tarball again"
		fi
	fi

	info "Fetching tarball: $fetch_remote_uri --> $fetch_local_target_path"
	wget $fetch_remote_uri -O $fetch_local_target_path || fatalError "Failed to fetch tarball"
	if [ -z "$fetch_expected_sha256" ] ; then
		error "No digest set for tarball at fetch_expected_sha256. Skipping verification. This may well be a fatal error in the future"
	else
		local fetch_actual_sha256="$(sha256sum $fetch_local_target_path | cut -d ' ' -f 1)"
		if [ ! "$fetch_actual_sha256" = "$fetch_expected_sha256" ] ; then
			fatalError "Wrong sha256 sum. Expected: $fetch_expected_sha256 . Actual: $fetch_actual_sha256"
		fi
	fi
	verbose "Done fetching tarball."
}

base_unpack_tarball() {
	# Sanity check to avoid unintenional git/tarball mixing
	if [ -d "$unpack_link_dst/.git" ] ; then
		fatalError "You are trying to unpack a tarball into what was previously a git folder. If you intended to do so, please remove $unpack_link_dst manually, and redo the operation"
	fi

	# Note that unlike the git case, we do not check for existence because we would need to know what's inside the tarball for that
	# the calling process can check for itself should it want to
	info "Unpacking tarball: $fetch_local_target_path --> $unpack_dest_path"
	tar -C $unpack_dest_path -xf $fetch_local_target_path || fatalError "Failed to unpack $fetch_local_target_path"
	if [ -n "$post_unpack_command" ] ; then
		info_do_or_die eval $post_unpack_command
	fi
}

base_do_fetch() {
	if [ ! -d "$config_toplevel__downloads_base_path" ] ; then
		fatalError "$config_toplevel__downloads_base_path does not exist."
	fi

	if [[ $fetch_remote_uri = git://* ]] ; then
		base_fetch_git
		return
	fi

	local bn=$(basename $fetch_remote_uri)
	local type=${bn##*.}
	case $type in
		git)
			base_fetch_git
			;;
		zip|rar|arj|7z)
			fatalError "Please use normal tarballs. $type is not accepted here. Thank you."
			;;
		*)
			base_fetch_tarball	# we won't do error handling, if you decided to unpack something else, it's your problem...
			;;
	esac
}

base_do_unpack() {
	if [[ $fetch_remote_uri = git://* ]] ; then
		base_unpack_git
		return
	fi
	local bn=$(basename $fetch_remote_uri)
	local type=${bn##*.}
	case $type in
		git)
			base_unpack_git
			;;
		zip|rar|arj|7z)
			fatalError "Please use normal tarballs. $type is not accepted here. Thank you."
			;;
		*)
			base_unpack_tarball	# we won't do error handling, if you decided to unpack something else, it's your problem...
			;;
	esac
}



# These are the functions we really want to export
export -f base_do_fetch base_do_unpack
# The next functions are exported just to keep other scripts happy, these are bash limitations
# and the alternatives would be to source this file everywhere.
export -f base_fetch_git base_unpack_git base_fetch_tarball base_unpack_tarball
export -f base_fetch_unpack_git_handle_existing_folder
