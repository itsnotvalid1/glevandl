#!/usr/bin/env bash

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Generate Docker manifest list." >&2
	echo "Usage: ${name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help           - Show this help and exit." >&2
	echo "  -t --toolup         - Build ilp32-toolup container image." >&2
	echo "  -b --builder        - Build ilp32-builder container image." >&2
	echo "  -r --runner         - Build ilp32-runner container image." >&2
	echo "  --build-top         - Top build directory. Default: '${build_top}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="htbr"
	local long_opts="help,toolup,builder,runner,build-top:"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		#echo "${FUNCNAME[0]}: @${1}@ @${2}@"
		case "${1}" in
		-h | --help)
			usage=1
			shift
			;;
		-t | --toolup)
			step_toolup=1
			shift
			;;
		-b | --builder)
			step_builder=1
			shift
			;;
		-r | --runner)
			step_runner=1
			shift
			;;
		--build-top)
			build_top="${2}"
			shift 2
			;;
		--)
			shift
			if [[ ${1} ]]; then
				echo "${name}: ERROR: Got extra opts: '${@}'" >&2
				exit 1
			fi
			break
			;;
		*)
			echo "${name}: ERROR: Internal opts: '${@}'" >&2
			exit 1
			;;
		esac
	done
}

on_exit() {
	local result=${1}

	if [ -d ${tmp_dir} ]; then
		rm -rf ${tmp_dir}
	fi

	local end_time=${SECONDS}

	set +x
	if [[ ${current_step} != "done" ]]; then
		echo "${name}: ERROR: Step '${current_step}' failed." >&2
	fi
	echo "${name}: Done: ${result} ${end_time} sec ($(sec_to_min ${end_time}) min)" >&2
}


#===============================================================================
# program start
#===============================================================================
export PS4='\[\033[0;33m\]+${BASH_SOURCE##*/}:${LINENO}: \[\033[0;37m\]'
set -x

name="${0##*/}"
build_time="$(date +%Y.%m.%d-%H.%M.%S)"

current_step="setup"
trap "on_exit 'Failed.'" EXIT
set -e

SECONDS=0

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
source ${SCRIPTS_TOP}/lib/util.sh

host_arch=$(get_arch $(uname -m))
target_arch=$(get_arch "arm64")
target_triple="aarch64-linux-gnu"

process_opts "${@}"

build_top="$(realpath -m ${build_top:-"${HOST_WORK_DIR}/build-${build_time}"})"

if [[ -n "${usage}" ]]; then
	usage
	trap - EXIT
	exit 0
fi

trap "on_exit 'Success.'" EXIT
exit 0
