#!/usr/bin/env bash

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Build lp64 and ilp32 vdso test programs." >&2
	echo "Usage: ${name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help               - Show this help and exit." >&2
	echo "  -v --verbose            - Verbose execution." >&2
	echo "  --build-top <directory> - Top build directory. Default: '${build_top}'." >&2
	echo "  --prefix    <directory> - Toolchain prefix. Default: '${prefix}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hv"
	local long_opts="help,verbose,build-top:,prefix:"

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
		--prefix)
			prefix="${2}"
			shift 2
			;;
		--)
			shift
			if [[ ${1} ]]; then
				echo "${name}: ERROR: Extra args found: '${@}'" >&2
				usage=1
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

	set +x
	echo "${name}: Done: ${result}" >&2
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
		echo "${name}: ERROR (${FUNCNAME[0]}): Bad arch '${a}'" >&2
		exit 1
		;;
	esac
}

check_tools() {
	local prefix=${1}

	if [[ ! ${prefix} ]]; then
		echo "${name}: ERROR: Must provide --prefix option." >&2
		usage
		exit 1
	fi

	if ! test -x "$(command -v ${CC})"; then
		echo "${name}: ERROR: Bad compiler: '${CC}'." >&2
		usage
		exit 1
	fi
	if [[ ! -f ${prefix}/lib/ld-linux-aarch64_ilp32.so.1 ]]; then
		echo "${name}: ERROR: Bad ld: '${prefix}/lib/ld-linux-aarch64_ilp32.so.1'." >&2
		usage
		exit 1
	fi
	if [[ ! -d ${prefix}/libilp32 ]]; then
		echo "${name}: ERROR: Bad libilp32: '${prefix}/libilp32'." >&2
		usage
		exit 1
	fi
	if ! test -x "$(command -v ${OBJDUMP})"; then
		OBJDUMP="${prefix}/bin/objdump"
		if ! test -x "$(command -v ${OBJDUMP})"; then
			echo "${name}: INFO: objdump not found." >&2
			unset OBJDUMP
		fi
	fi
}

build_progs() {
	mkdir -p ${build_top}

	old_xtrace="$(shopt -po xtrace || :)"
	for prog in ${progs}; do
		for abi in ${abis}; do
			gcc_opts="gcc_opts_${abi}"
			set -o xtrace
			${CC} \
				${!gcc_opts} \
				${link_extra} \
				-DLINKAGE_dynamic \
				-o ${build_top}/${prog}--${abi} \
				${SCRIPTS_TOP}/${prog}.c || :
			${CC} \
				${!gcc_opts} \
				${link_extra} \
				-static \
				-DLINKAGE_static \
				-o ${build_top}/${prog}--${abi}-static \
				${SCRIPTS_TOP}/${prog}.c || :
			eval "${old_xtrace}"
		done
	done
}

run_file() {
	local prog
	local abi

	for prog in ${progs}; do
		for abi in ${abis}; do
			local base=${build_top}/${prog}--${abi}
			for file in ${base}; do
				if [[ -f ${file} ]]; then
					file ${file}
				else
					echo "${name}: INFO: ${file} not built." >&2
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
			local file=${build_top}/${prog}--${abi}
			file ${!ld_so}
			if [[ -f ${file} ]]; then
				${!ld_so} --list ${file} || :
			else
				echo "${name}: INFO: ${file} not built." >&2
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
			local base=${build_top}/${prog}--${abi}
			for file in ${base}; do
				if [[ -f ${file} ]]; then
					${OBJDUMP} -x ${file}
					#${OBJDUMP} --dynamic-syms ${file}
					#${OBJDUMP} --dynamic-reloc ${file}
				else
					echo "${name}: INFO: ${file} not built." >&2
				fi
			done
		done
	done
}

archive_libs() {
	local name="ilp32-libraries"
	local dir="${build_top}/${name}"

	mkdir -p ${dir}/${prefix}/lib/

	cp -a ${prefix}/lib/ld-linux-aarch64_ilp32.so.1 ${dir}/${prefix}/lib/
	cp -a ${prefix}/libilp32 ${dir}/${prefix}/

	cp -a ${prefix}/lib/ld-linux-aarch64.so.1 ${dir}/${prefix}/lib/
	cp -a ${prefix}/lib64 ${dir}/${prefix}/

	echo "$(date)" > ${dir}/${prefix}/info.txt
	echo "$(uname -a)" >> ${dir}/${prefix}/info.txt
	echo "$(${CC} --version)" >> ${dir}/${prefix}/info.txt

	#tar -C ${dir} -cvzf ${build_top}/${name}.tar.gz ${prefix#/}
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

host_arch=$(get_arch $(uname -m))
build_top=${build_top:-"$(pwd)"}

if [[ -n "${usage}" ]]; then
	usage
	trap - EXIT
	exit 0
fi

progs="vdso-test"
abis="lp64 ilp32"

CC=${CC:-"${prefix}/bin/aarch64-linux-gnu-gcc"}
OBJDUMP=${OBJDUMP:-"${CC%-gcc}-objdump"}

ld_so_ilp32="${ld_so_ilp32:-$(realpath -e ${prefix}/lib/ld-linux-aarch64_ilp32.so.1)}"
ld_so_lp64="${ld_so_lp64:-$(realpath -e ${prefix}/lib/ld-linux-aarch64.so.1)}"

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

check_tools ${prefix}

if [ ${verbose} ]; then
	link_extra="-Wl,--verbose"
fi

build_progs
run_file
run_ld_so
run_objdump
archive_libs

trap "on_exit 'Success.'" EXIT
exit 0
