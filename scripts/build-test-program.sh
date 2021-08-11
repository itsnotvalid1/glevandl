#!/usr/bin/env bash

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Build ilp32 test program images." >&2
	echo "Usage: ${name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help   - Show this help and exit." >&2
	echo "  --build-top - Top build directory. Default: '${build_top}'." >&2
	echo "  --prefix    - Toolchain prefix. Default: '${prefix}'." >&2
	echo "  --src-top   - Top source directory. Default: '${src_top}'." >&2
	echo "  --test-name - Test name. Guessed: '${test_name_guessed}', Default: '${test_name}'." >&2
	echo "Environment:" >&2
	echo "  HOST_WORK_DIR       - Default: '${HOST_WORK_DIR}'" >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="h"
	local long_opts="help,src-top:,test-name:,build-top:,prefix:"

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
		--src-top)
			src_top="${2}"
			shift 2
			;;
		--test-name)
			test_name="${2}"
			shift 2
			;;
		--build-top)
			build_top="${2}"
			shift 2
			;;
		--prefix)
			prefix="${2}"
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

	local end_time=${SECONDS}

	set +x
	echo "${name}: Done: ${result}: ${end_time} sec" >&2
}

#===============================================================================
# program start
#===============================================================================
export PS4='\[\033[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}): \[\033[0;37m\]'
set -x

name="${0##*/}"

trap "on_exit 'failed.'" EXIT
set -e

SECONDS=0

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
source ${SCRIPTS_TOP}/lib/util.sh

process_opts "${@}"

HOST_WORK_DIR=${HOST_WORK_DIR:-"$(pwd)"}
CURRENT_WORK_DIR=${CURRENT_WORK_DIR:-"${HOST_WORK_DIR}"}

docker_top=${docker_top:-"$(cd "${SCRIPTS_TOP}/../docker" && pwd)"}

check_opt 'prefix' ${prefix}

check_opt 'src-top' ${src_top}
check_directory ${src_top}
src_top="$(realpath -e ${src_top})"

test_name_guessed="${src_top##*/}"
test_name=${test_name:-"${test_name_guessed}"}

build_top="$(realpath -m ${build_top:-"${HOST_WORK_DIR}/auto-build/${test_name}"})"

builder_work_dir="$(${SCRIPTS_TOP}/enter-builder.sh --print-work-dir)"

builder_src_top="${builder_work_dir}$(strip_current ${src_top})"
builder_build_top="${builder_work_dir}$(strip_current ${build_top})"

host_arch=$(get_arch "$(uname -m)")
target_arch=$(get_arch "arm64")
target_triple="aarch64-linux-gnu"

if [[ -n "${usage}" ]]; then
	usage
	trap - EXIT
	exit 0
fi

${SCRIPTS_TOP}/enter-builder.sh \
	--verbose \
	--container-name=build-${test_name}--$(date +%H-%M-%S) \
	-- ${builder_src_top}/build-${test_name}.sh \
		--verbose \
		--build-top=${builder_build_top} \
		--prefix=${prefix}

trap "on_exit 'Success.'" EXIT
exit 0
