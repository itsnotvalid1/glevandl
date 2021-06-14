#!/usr/bin/env bash

#!/usr/bin/env bash

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Build lp64 and ilp32 hello-world programs." >&2
	echo "Usage: ${name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help                   - Show this help and exit." >&2
	echo "  -v --verbose                - Verbose execution." >&2
	echo "  --build-top     <directory> - Top build directory. Default: '${build_top}'." >&2
	echo "  --target-prefix <prefix>    - Target prefix. Default: '${target_prefix}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hv"
	local long_opts="help,verbose,\
build-top:,target-prefix:"

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
		-v | --verbose)
			set -x
			verbose=1
			shift
			;;
		--build-top)
			build_top="${2}"
			shift 2
			;;
		--target-prefix)
			target_prefix="${2}"
			shift 2
			;;
		--)
			shift
			user_cmd="${@}"
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

	set +x
	echo "${name}: Done: ${result}" >&2
}

run_file() {
	local prog
	local abi

	for prog in ${progs}; do
		for abi in ${abis}; do
			local base=${build_top}/${prog}--${abi}
			for file in ${base}.o ${base}; do
				if [[ -f ${file} ]]; then
					file ${file}
				else
					echo "${name}: INFO: ${file} not built." >&2
					
				fi
			done
		done
	done
}

run_ldd() {
	local prog
	local abi

	for prog in ${progs}; do
		for abi in ${abis}; do
			local base=${build_top}/${prog}--${abi}
			for file in ${base}; do
				if [[ -f ${file} ]]; then
					ldd ${file}
				else
					echo "${name}: INFO: ${file} not built." >&2
					
				fi
			done
		done
	done
}


#===============================================================================
# program start
#===============================================================================

export PS4='\[\033[0;33m\]+${BASH_SOURCE##*/}:${LINENO}: \[\033[0;37m\]'

name="${0##*/}"
build_time="$(date +%Y.%m.%d-%H.%M.%S)"

trap "on_exit 'failed.'" EXIT
set -e

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}

process_opts "${@}"

host_arch="$(uname -m)"
build_top=${build_top:-"$(pwd)"}
target_prefix=${target_prefix:-"aarch64-linux-gnu-"}

if [[ -n "${usage}" ]]; then
	usage
	trap - EXIT
	exit 0
fi

progs="hello-world"
abis="lp64 ilp32"

if [ ${verbose} ]; then
	link_extra="-Wl,--verbose"
fi

old_xtrace="$(shopt -po xtrace || :)"
for prog in ${progs}; do
	for abi in ${abis}; do
		set -o xtrace
		${target_prefix}gcc \
			-mabi=${abi} \
			-c \
			-o ${build_top}/${prog}--${abi}.o \
			${SCRIPTS_TOP}/${prog}.c
		${target_prefix}gcc \
			-mabi=${abi} \
			${link_extra} \
			-o ${build_top}/${prog}--${abi} \
			${SCRIPTS_TOP}/${prog}.c || :
		eval "${old_xtrace}"
	done
done

run_file

case ${host_arch} in
	x86_64)
		;;
	aarch64)
		run_ldd
		;;
	*)
		echo "${name}: ERROR: Unsupported host arch '${host_arch}'." >&2
		exit 1
		;;
esac

trap "on_exit 'Success.'" EXIT
exit 0
