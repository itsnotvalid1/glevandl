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
	echo "  --src-dir    - SPEC CPU source directory. Default: '${src_dir}'." >&2
	echo "  --spec-conf  - SPEC config file. Default: '${spec_conf}'." >&2
	echo "  --build-dir  - Top build directory. Default: '${build_dir}'." >&2
	echo "  --prefix     - Toolchain prefix. Default: '${prefix}'." >&2
	echo "  -d --dry-run - Pass --dry-run." >&2
	echo "Option steps:" >&2
	echo "  -1 --install - Install SPEC CPU." >&2
	echo "  -2 --run     - Run intrate test." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="chvd12"
	local long_opts="check,help,verbose,\
src-dir:,spec-conf:,build-dir:,prefix:,dry-run,\
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
		--src-dir)
			src_dir="${2}"
			shift 2
			;;
		--spec-conf)
			spec_conf="${2}"
			shift 2
			;;
		--build-dir)
			build_dir="${2}"
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
		echo "${name}: current_step = ${current_step}" >&2
	fi
	echo "${name}: Done: ${result}: ${end_time} sec ($(sec_to_min ${end_time}) min)" >&2
}

run_shellcheck() {
	local file=${1}

	shellcheck=${shellcheck:-"shellcheck"}

	if ! test -x "$(command -v "${shellcheck}")"; then
		echo "${name}: ERROR: Please install '${shellcheck}'." >&2
		exit 1
	fi

	${shellcheck} "${file}"
}

sec_to_min() {
	local sec=${1}
	local min="$((sec / 60))"
	local frac="$(((sec * 100) / 60))"
	local len=${#frac}

	if [[ ${len} -eq 1 ]]; then
		frac="0${frac}"
	elif [[ ${len} -gt 2 ]]; then
		frac=${frac:(-2)}
	fi
	echo "${min}.${frac}"
}

check_directory() {
	local src="${1}"
	local msg="${2}"
	local usage="${3}"

	if [[ ! -d "${src}" ]]; then
		echo "${script_name}: ERROR (${FUNCNAME[0]}): Directory not found${msg}: '${src}'" >&2
		[[ -z "${usage}" ]] || usage
		exit 1
	fi
}

check_file() {
	local src="${1}"
	local msg="${2}"
	local usage="${3}"

	if [[ ! -f "${src}" ]]; then
		echo -e "${name}: ERROR: File not found${msg}: '${src}'" >&2
		[[ -z "${usage}" ]] || usage
		exit 1
	fi
}

check_opt() {
	option=${1}
	shift
	value=${*}

	if [[ ! ${value} ]]; then
		echo "${name}: ERROR (${FUNCNAME[0]}): Must provide --${option} option." >&2
		usage
		exit 1
	fi
}

get_arch() {
	local a=${1}

	case "${a}" in
	arm64|aarch64)			echo "arm64" ;;
	amd64|x86_64)			echo "amd64" ;;
	ppc|powerpc|ppc32|powerpc32)	echo "ppc32" ;;
	ppc64|powerpc64)		echo "ppc64" ;;
	ppc64le|powerpc64le)		echo "ppc64le" ;;
	*)
		echo "${script_name}: ERROR (${FUNCNAME[0]}): Bad arch '${a}'" >&2
		exit 1
		;;
	esac
}

check_tools() {
	local prefix=${1}

	if [[ ! ${prefix} ]]; then
		echo "${script_name}: ERROR: Must provide --prefix option." >&2
		usage
		exit 1
	fi

	if ! test -x "$(command -v "${CC}")"; then
		echo "${script_name}: ERROR: Bad compiler: '${CC}'." >&2
		usage
		exit 1
	fi
	if [[ ! -f ${prefix}/lib/ld-linux-aarch64_ilp32.so.1 ]]; then
		echo "${script_name}: ERROR: Bad ld: '${prefix}/lib/ld-linux-aarch64_ilp32.so.1'." >&2
		usage
		exit 1
	fi
	if [[ ! -d ${prefix}/libilp32 ]]; then
		echo "${script_name}: ERROR: Bad libilp32: '${prefix}/libilp32'." >&2
		usage
		exit 1
	fi
	if ! test -x "$(command -v "${OBJDUMP}")"; then
		OBJDUMP="${prefix}/bin/objdump"
		if ! test -x "$(command -v "${OBJDUMP}")"; then
			echo "${script_name}: INFO: objdump not found." >&2
			unset OBJDUMP
		fi
	fi
}

build_progs() {
	mkdir -p "${build_dir}"

	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	for prog in ${progs}; do
		for abi in ${abis}; do
			gcc_opts="gcc_opts_${abi}"
			set -o xtrace
			${CC} \
				"${!gcc_opts}" \
				"${link_extra}" \
				-DLINKAGE_dynamic \
				-o "${build_dir}/${prog}--${abi}" \
				"${SCRIPTS_TOP}/${prog}.c" || :
			${CC} \
				"${!gcc_opts}" \
				"${link_extra}" \
				-static \
				-DLINKAGE_static \
				-o "${build_dir}/${prog}--${abi}-static" \
				"${SCRIPTS_TOP}/${prog}.c" || :
			eval "${old_xtrace}"
		done
	done
}

run_file() {
	local prog
	local abi

	for prog in ${progs}; do
		for abi in ${abis}; do
			local base=${build_dir}/${prog}--${abi}
			for file in ${base}; do
				if [[ -f ${file} ]]; then
					file "${file}"
				else
					echo "${script_name}: INFO: ${file} not built." >&2
				fi
			done
		done
	done
}

run_ld_so() {
	local prog
	local abi

	if [[ ${host_arch} != "arm64" ]]; then
		return
	fi

	for prog in ${progs}; do
		for abi in ${abis}; do
			local ld_so="ld_so_${abi}"
			local file=${build_dir}/${prog}--${abi}
			file "${!ld_so}"
			if [[ -f ${file} ]]; then
				"${!ld_so}" --list "${file}" || :
			else
				echo "${script_name}: INFO: ${file} not built." >&2
			fi
		done
	done
}

run_objdump() {
	local prog
	local abi

	if [[ ! ${OBJDUMP} ]]; then
		return
	fi

	for prog in ${progs}; do
		for abi in ${abis}; do
			local base=${build_dir}/${prog}--${abi}
			for file in ${base}; do
				if [[ -f ${file} ]]; then
					"${OBJDUMP}" -x "${file}"
					#"${OBJDUMP}" --dynamic-syms "${file}"
					#"${OBJDUMP}" --dynamic-reloc "${file}"
				else
					echo "${script_name}: INFO: ${file} not built." >&2
				fi
			done
		done
	done
}

archive_libs() {
	local name="ilp32-libraries"
	local dir="${build_dir}/${script_name}"

	mkdir -p "${dir}/${prefix}/lib/"

	cp -a "${prefix}/lib/ld-linux-aarch64_ilp32.so.1" "${dir}/${prefix}/lib/"
	cp -a "${prefix}/libilp32 ${dir}/${prefix}/"

	cp -a "${prefix}/lib/ld-linux-aarch64.so.1" "${dir}/${prefix}/lib/"
	cp -a "${prefix}/lib64 ${dir}/${prefix}/"

	date > "${dir}/${prefix}/info.txt"
	uname -a >> "${dir}/${prefix}/info.txt"
	${CC} --version >> "${dir}/${prefix}/info.txt"

	#tar -C ${dir} -cvzf ${build_dir}/${script_name}.tar.gz ${prefix#/}
}

test_for_src()
{
	local build_dir=${1}

	check_file "${build_dir}/bin/harness/runcpu"
}

install_tests() {
	local src_dir=${1}
	local build_dir=${2}

	mkdir -p "${build_dir}"

	if [[ ${verbose} ]]; then
		tput() {
			echo "tput: ${1}"
		}

		export -f tput
		bash -x "${src_dir}/install.sh" -d "${build_dir}" -f
		export -f -n tput
	else
		"${src_dir}/install.sh" -d "${build_dir}" -f
	fi

	echo "${script_name}: INFO: Install done." >&2
}

update_tests() {
	local build_dir=${1}

	test_for_src "${build_dir}"

	pushd "${build_dir}"

	# shellcheck source=/dev/null
	source "${build_dir}/shrc"

	local cmd="runcpu \
		${verbose:+--verbose=99}
		${extra_ops}
		 --update"

	echo "y" | eval ${cmd}

	popd
	echo "${script_name}: INFO: Update done." >&2
}

run_tests() {
	local build_dir=${1}
	local abi=${2}
	shift 2
	local extra_ops="${*}"

	local conf_copy="${build_dir}/${spec_conf##*/}"
	cp -avf ${spec_conf} ${conf_copy}

	pushd "${build_dir}"
	export PATH=${prefix}/bin:${PATH}

	ulimit -s unlimited

	# shellcheck source=/dev/null
	source "${build_dir}/shrc"

	local gcc_opts="gcc_opts_${abi}"

	local cmd="runcpu \
		${extra_ops}
		${verbose:+--verbose=99}
		${dry_run:+--dry-run}
		--configfile=${conf_copy}
		--define abi=${abi}
		--define gcc_opts=${gcc_opts}
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

process_opts "${@}"

host_arch=$(get_arch "$(uname -m)")

prefix=${prefix:-"/opt/ilp32"}
spec_conf=${spec_conf:-"${SCRIPTS_TOP}/ilp32.cfg"}

build_dir=${build_dir:-"$(pwd)/cpu2017-build"}

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

check_opt 'src-dir' "${src_dir}"
check_directory "${src_dir}" "" "usage"

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
	-Wl,--dynamic-linker=${prefix}/lib/ld-linux-aarch64_ilp32.so.1
	-Wl,--rpath=${prefix}/libilp32
"}

gcc_opts_lp64=${gcc_opts_lp64:-"
	-mabi=lp64
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
		install_tests "${src_dir}" "${build_dir}"
		update_tests "${build_dir}"
		unset step_install
	elif [[ ${step_run} ]]; then
		current_step="step_run"
		test_for_src "${build_dir}"
		#extra_ops+=" --ignore-errors"
		for abi in ${abis}; do
			run_tests "${build_dir}" ${abi} ${extra_ops}
		done
		unset step_run
	else
		if [[ ${current_step} == "setup" ]]; then
			echo "${name}: ERROR: Must specify an option step." >&2
			usage
			exit 1
		fi
		break
	fi
	unset current_step
done

trap "on_exit 'Success.'" EXIT
exit 0
