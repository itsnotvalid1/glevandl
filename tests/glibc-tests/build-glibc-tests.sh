#!/usr/bin/env bash

usage () {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Build and run glibc tests." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help    - Show this help and exit." >&2
	echo "  -v --verbose - Verbose execution." >&2
	echo "  --build-top  - Top build directory. Default: '${build_top}'." >&2
	echo "  --prefix     - Toolchain prefix. Default: '${prefix}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hv"
	local long_opts="help,verbose,build-top:,prefix:"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "${@}")

	eval set -- "${opts}"

	while true ; do
		#echo "${FUNCNAME[0]}: @${1}@ @${2}@"
		case "${1}" in
		-h | --help)
			usage=1
			shift
			;;
		-v | --verbose)
			set -x
			verbose=1
			shift
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
				echo "${script_name}: ERROR: Extra args found: '${*}'" >&2
				usage=1
			fi
			break
			;;
		*)
			echo "${script_name}: ERROR: Internal opts: '${*}'" >&2
			exit 1
			;;
		esac
	done
}

on_exit() {
	local result=${1}
	local end_time=${SECONDS}

	set +x
	echo "${script_name}: Done: ${result}: ${end_time} sec ($(sec_to_min ${end_time}) min)" >&2
}

#===============================================================================
# program start
#===============================================================================
export PS4='\[\033[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}): \[\033[0;37m\]'
script_name="${0##*/}"

SCRIPTS_TOP="${SCRIPTS_TOP:-$(cd "${BASH_SOURCE%/*}" && pwd)}"
LIB_TOP="${LIB_TOP:-$(cd "${SCRIPTS_TOP}/../lib" && pwd)}"

source "${LIB_TOP}/test-lib.sh"

trap "on_exit 'failed.'" EXIT
set -e

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
source "${SCRIPTS_TOP}/../lib/test-lib.sh"

process_opts "${@}"

host_arch=$(get_arch "$(uname -m)")

prefix=${prefix:-"/opt/ilp32"}

build_top=${build_top:-"$(pwd)/glibc-test"}

if [[ -n "${usage}" ]]; then
	usage
	trap - EXIT
	exit 0
fi

SECONDS=0

abis="lp64 ilp32"

CC=${CC:-"${prefix}/bin/aarch64-linux-gnu-gcc"}
OBJDUMP=${OBJDUMP:-"${CC%-gcc}-objdump"}

ld_so_ilp32="${ld_so_ilp32:-$(realpath -e "${prefix}/lib/ld-linux-aarch64_ilp32.so.1")}"
ld_so_lp64="${ld_so_lp64:-$(realpath -e "${prefix}/lib/ld-linux-aarch64.so.1")}"

gcc_opts_ilp32=${gcc_opts_ilp32:-"
	-mabi=ilp32
	-Wl,--verbose
	-Wl,--dynamic-linker=${prefix}/lib/ld-linux-aarch64_ilp32.so.1
	-Wl,--rpath=${prefix}/libilp32
"}

gcc_opts_lp64=${gcc_opts_lp64:-"
	-mabi=lp64
	-Wl,--verbose
	-Wl,--dynamic-linker=${prefix}/lib/ld-linux-aarch64.so.1
	-Wl,--rpath=${prefix}/lib64
"}

check_tools "${prefix}"

case "${host_arch}" in
arm64|aarch64)
	echo "arm64"
	;;
amd64|x86_64)
	echo "amd64"
	;;
*)
	echo "${script_name}: ERROR: Unsupported arch '${host_arch}'" >&2
	exit 1
	;;
esac

run_glibc_test () {
	local build_top=${1}
	local abi=${2}
	shift 2
	local extra_ops="${*}"

	echo "${script_name}: ERROR: TODO" >&2
}

for abi in ${abis}; do
	run_glibc_test "${build_top}" "${abi}" "${extra_ops}"
done

trap "on_exit 'Success.'" EXIT
exit 0

