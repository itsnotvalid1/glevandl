#!/usr/bin/env bash

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Build ilp32 Linux kernel" >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help         - Show this help and exit." >&2
	echo "  -b --build-dir    - Build directory. Default: '${build_dir}'." >&2
	echo "  -i --install-dir  - Install directory. Default: '${install_dir}'." >&2
	echo "  -s --kernel-src   - Kernel source directory. Default: '${kernel_src}'." >&2
	echo "Args:" >&2
	echo "  user make options - Default: '${user_make_options}'" >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hb:i:s:"
	local long_opts="help,build-dir:,install-dir:,kernel-src:"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		#echo "${FUNCNAME[0]}: @${1}@ @${2}@"
		case "${1}" in
		-h | --help)
			usage=1
			shift
			;;
		-b | --build-dir)
			build_dir="${2}"
			shift 2
			;;
		-i | --install-dir)
			install_dir="${2}"
			shift 2
			;;
		-s | --kernel-src)
			kernel_src="${2}"
			shift 2
			;;
		--)
			shift
			user_make_options="${@}"
			break
			;;
		*)
			echo "${script_name}: ERROR: Internal opts: '${@}'" >&2
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
set -ex

script_name="${0##*/}"
trap "on_exit 'failed.'" EXIT

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
PROJECT_TOP=${PROJECT_TOP:-"$(cd "${SCRIPTS_TOP}/.." && pwd)"}

source ${SCRIPTS_TOP}/lib/util.sh

process_opts "${@}"

cpus="$(getconf _NPROCESSORS_ONLN || echo 1)"

install_dir=${install_dir:-"${build_dir}/install"}
headers_dir=${headers_dir:-"${install_dir}/kernel-headers"}

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

if test -x "$(command -v ccache)"; then
	ccache='ccache '
else
	echo "${script_name}: INFO: Please install ccache"
fi

check_opt 'build-dir' ${build_dir}

check_opt 'kernel-src' ${kernel_src}
check_directory "${kernel_src}"

export CCACHE_DIR=${CCACHE_DIR:-"${build_dir}.ccache"}

mkdir -p ${build_dir}
mkdir -p ${install_dir} ${install_dir}/boot ${install_dir}/lib/modules
mkdir -p ${headers_dir}
mkdir -p ${CCACHE_DIR}

make_options="-j${cpus} ARCH=arm64 CROSS_COMPILE='${ccache}aarch64-linux-gnu-' INSTALL_MOD_PATH='${install_dir}' INSTALL_PATH='${install_dir}/boot' INSTALL_HDR_PATH='${headers_dir}' INSTALLKERNEL=non-existent-file ${user_make_options}"

cmd="make -C ${kernel_src} ${make_options} mrproper"
eval ${cmd}

cmd="make -C ${kernel_src} ${make_options} O='${build_dir}' defconfig"
eval ${cmd}

cmd="make -C ${kernel_src} ${make_options} O='${build_dir}' savedefconfig"
eval ${cmd}

cmd="make -C ${kernel_src} ${make_options} O='${build_dir}' prepare"
eval ${cmd}

cmd="make -C ${kernel_src} ${make_options} headers_install"
eval ${cmd}

cmd="make -C ${kernel_src} ${make_options} O='${build_dir}'"
eval ${cmd}

cmd="make -C ${kernel_src} ${make_options} O='${build_dir}' install"
eval ${cmd}

cmd="make -C ${kernel_src} ${make_options} O='${build_dir}' modules_install"
eval ${cmd}

echo "${script_name}: INFO: kernel headers installed to '${headers_dir}'." >&2
trap "on_exit 'Success.'" EXIT
