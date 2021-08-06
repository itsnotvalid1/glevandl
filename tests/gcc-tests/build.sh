#!/usr/bin/env bash

usage () {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Build lp64 and ilp32 test programs." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -c --check              - Run shellcheck." >&2
	echo "  -h --help               - Show this help and exit." >&2
	echo "  -v --verbose            - Verbose execution." >&2
	echo "  --build-top <directory> - Top build directory. Default: '${build_top}'." >&2
	echo "  --prefix    <directory> - Toolchain prefix. Default: '${prefix}'." >&2
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
export PS4='\[\033[0;33m\]+${BASH_SOURCE##*/}:${LINENO}: \[\033[0;37m\]'

progs="pr82274-1 pr82274-2"
abis="lp64 ilp32"

script_name="${0##*/}"
build_time="$(date +%Y.%m.%d-%H.%M.%S)"

trap "on_exit 'failed.'" EXIT
set -e

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
source "${SCRIPTS_TOP}/../lib/test-lib.sh"

process_opts "${@}"

host_arch=$(get_arch $(uname -m))
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

ld_so_ilp32="${ld_so_ilp32:-$(realpath -e ${prefix}/lib/ld-linux-aarch64_ilp32.so.1)}"
ld_so_lp64="${ld_so_lp64:-$(realpath -e ${prefix}/lib/ld-linux-aarch64.so.1)}"

gcc_opts_common=" -ftrapv"

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

check_tools ${prefix}

if [ ${verbose} ]; then
	link_extra="-Wl,--verbose"
fi

build_progs
run_file
run_ld_so
run_objdump
archive_libs ${build_top} ${prefix}

trap "on_exit 'Success.'" EXIT
exit 0
