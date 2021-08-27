#!/usr/bin/env bash

usage () {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Build lp64 and ilp32 SPEC CPU programs." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -c --check   - Run shellcheck." >&2
	echo "  -h --help    - Show this help and exit." >&2
	echo "  -v --verbose - Verbose execution." >&2
	echo "  --build-top  - Top build directory. Default: '${build_top}'." >&2
	echo "  --prefix     - Toolchain prefix. Default: '${prefix}'." >&2
	echo "  --spec-src   - SPEC CPU source directory. Default: '${spec_src}'." >&2
	echo "  --spec-conf  - SPEC CPU config file. Default: '${spec_conf}'." >&2
	echo "  -d --dry-run - Pass --dry-run." >&2
	echo "Option steps:" >&2
	echo "  -1 --install - Install SPEC CPU." >&2
	echo "  -2 --run     - Run intrate test." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="chvd12"
	local long_opts="check,help,verbose,\
spec-src:,spec-conf:,build-top:,prefix:,dry-run,\
install,run"

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
		--spec-src)
			spec_src="${2}"
			shift 2
			;;
		--spec-conf)
			spec_conf="${2}"
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
		-d | --dry-run)
			dry_run=1
			shift
			;;
		-1 | --install)
			step_install=1
			shift
			;;
		-2 | --run)
			step_run=1
			shift
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
	if [[ ${current_step} ]]; then
		echo "${script_name}: current_step = ${current_step}" >&2
	fi
	echo "${script_name}: Done: ${result}: ${end_time} sec ($(sec_to_min ${end_time}) min)" >&2
}



test_for_src()
{
	local build_top=${1}

	check_file "${build_top}/bin/harness/runcpu"
}

install_spec_cpu() {
	local spec_src=${1}
	local build_top=${2}

	mkdir -p "${build_top}"

	if [[ ${verbose} ]]; then
		tput() {
			echo "tput: ${1}"
		}

		export -f tput
		bash -x "${spec_src}/install.sh" -d "${build_top}" -f
		export -f -n tput
	else
		"${spec_src}/install.sh" -d "${build_top}" -f
	fi

	echo "${script_name}: INFO: Install done." >&2
}

update_spec_cpu() {
	local build_top=${1}

	test_for_src "${build_top}"

	pushd "${build_top}"

	# shellcheck source=/dev/null
	source "${build_top}/shrc"

	local cmd="runcpu \
		${verbose:+--verbose=99}
		${extra_ops}
		 --update"

	echo "y" | eval ${cmd}

	popd
	echo "${script_name}: INFO: Update done." >&2
}

run_spec_cpu() {
	local build_top=${1}
	local abi=${2}
	shift 2
	local extra_ops="${*}"

	local conf_copy="${build_top}/${spec_conf##*/}"
	cp -avf ${spec_conf} ${conf_copy}

	pushd "${build_top}"
	export PATH=${prefix}/bin:${PATH}

	ulimit -s unlimited

	# shellcheck source=/dev/null
	source "${build_top}/shrc"

	local gcc_opts="gcc_opts_${abi}"

#		--define gcc_opts=${gcc_opts}

	local cmd="runcpu \
		${extra_ops}
		${verbose:+--verbose=99}
		${dry_run:+--dry-run}
		--configfile=${conf_copy}
		--define abi=${abi}
		--copies=1
		--iterations=1
		--tune=base
		--size=test
		--noreportable
		--nopower
		intrate"

	eval ${cmd}
}

#===============================================================================
# program start
#===============================================================================
export PS4='\[\033[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}): \[\033[0;37m\]'

script_name="${0##*/}"
#build_time="$(date +%Y.%m.%d-%H.%M.%S)"

current_step="setup"
trap "on_exit 'failed.'" EXIT
set -e

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
source "${SCRIPTS_TOP}/../lib/test-lib.sh"

process_opts "${@}"

host_arch=$(get_arch "$(uname -m)")

prefix=${prefix:-"/opt/ilp32"}
spec_conf=${spec_conf:-"${SCRIPTS_TOP}/ilp32.cfg"}

build_top=${build_top:-"$(pwd)/cpu2017-build"}

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

check_opt 'spec-src' "${spec_src}"
check_directory "${spec_src}" "" "usage"

check_file "${spec_conf}" "" "usage"

SECONDS=0

progs="spec-cpu"
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

while true; do
	if [[ ${step_install} ]]; then
		current_step="step_install"
		install_spec_cpu "${spec_src}" "${build_top}"
		update_spec_cpu "${build_top}"
		unset step_install
	elif [[ ${step_run} ]]; then
		current_step="step_run"
		test_for_src "${build_top}"
		extra_ops+=" --ignore-errors"

		# FIXME for debug
		abis="lp64"
		for abi in ${abis}; do
			run_spec_cpu "${build_top}" ${abi} ${extra_ops}
		done
		unset step_run
	else
		if [[ ${current_step} == "setup" ]]; then
			echo "${script_name}: ERROR: Must specify an option step." >&2
			usage
			exit 1
		fi
		break
	fi
	unset current_step
done

trap "on_exit 'Success.'" EXIT
exit 0
