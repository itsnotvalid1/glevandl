#!/usr/bin/env bash

usage () {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Build lp64 and ilp32 programs: ${progs}." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -c --check   - Run shellcheck." >&2
	echo "  -h --help    - Show this help and exit." >&2
	echo "  -v --verbose - Verbose execution." >&2
	echo "  --build-top  - Top build directory. Default: '${build_top}'." >&2
	echo "  --prefix     - Toolchain prefix. Default: '${prefix}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="chv"
	local long_opts="check,help,verbose,build-top:,prefix:"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "${@}")

	eval set -- "${opts}"

	while true ; do
		#echo "${FUNCNAME[0]}: @${1}@ @${2}@"
		case "${1}" in
		-c | --check)
			check=1
			shift
			;;
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

	set +x
	echo "${script_name}: Done: ${result}" >&2
}

#===============================================================================
# program start
#===============================================================================
export PS4='\[\033[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}): \[\033[0;37m\]'

trap "on_exit 'failed.'" EXIT
set -e

if [[ ! ${progs} ]]; then
	echo "${script_name}: ERROR: 'progs' not defined." >&2
	exit 1
fi

source "${LIB_TOP}/test-lib.sh"

build_time="$(date +%Y.%m.%d-%H.%M.%S)"

process_opts "${@}"

abis="lp64 ilp32"
host_arch=$(get_arch "$(uname -m)")
build_top=${build_top:-"$(pwd)"}
prefix=${prefix:-"/opt/ilp32"}

if [[ -n "${usage}" ]]; then
	usage
	trap - EXIT
	exit 0
fi

if [[ ${check} ]]; then
	run_shellcheck "${0}"
	trap "on_exit 'Success'" EXIT
	exit 0
fi

CC=${CC:-"${prefix}/bin/aarch64-linux-gnu-gcc"}
OBJDUMP=${OBJDUMP:-"${CC%-gcc}-objdump"}

ld_so_ilp32="${ld_so_ilp32:-$(realpath -e "${prefix}/lib/ld-linux-aarch64_ilp32.so.1")}"
ld_so_lp64="${ld_so_lp64:-$(realpath -e "${prefix}/lib/ld-linux-aarch64.so.1")}"

if [[ ${verbose} ]]; then
	gcc_opts_common+=" -Wl,--verbose"
fi

gcc_opts_ilp32=${gcc_opts_ilp32:-"
	-mabi=ilp32
	-Wl,--dynamic-linker=${prefix}/lib/ld-linux-aarch64_ilp32.so.1
	-Wl,--rpath=${prefix}/libilp32
	${gcc_opts_common}
"}

gcc_opts_lp64=${gcc_opts_lp64:-"
	-mabi=lp64
	-Wl,--dynamic-linker=${prefix}/lib/ld-linux-aarch64.so.1
	-Wl,--rpath=${prefix}/lib64
	${gcc_opts_common}
"}

check_tools "${prefix}"

build_progs
if [[ ${verbose} ]]; then
	run_file
	run_ld_so
	run_objdump
fi
archive_libs "${build_top}" "${prefix}"

trap "on_exit 'Success.'" EXIT
exit 0
