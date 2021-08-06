#!/usr/bin/env bash

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

	if ! test -x "$(command -v ${CC})"; then
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
	if ! test -x "$(command -v ${OBJDUMP})"; then
		OBJDUMP="${prefix}/bin/objdump"
		if ! test -x "$(command -v ${OBJDUMP})"; then
			echo "${script_name}: INFO: objdump not found." >&2
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

	echo "${progs}" > ${build_top}/programs
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
			local file=${build_top}/${prog}--${abi}
			file ${!ld_so}
			if [[ -f ${file} ]]; then
				${!ld_so} --list ${file} || :
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
			local base=${build_top}/${prog}--${abi}
			for file in ${base}; do
				if [[ -f ${file} ]]; then
					${OBJDUMP} -x ${file}
					#${OBJDUMP} --dynamic-syms ${file}
					#${OBJDUMP} --dynamic-reloc ${file}
				else
					echo "${script_name}: INFO: ${file} not built." >&2
				fi
			done
		done
	done
}

archive_libs() {
	local build_top=${1}
	local prefix=${2}

	local archive="ilp32-libraries"
	local dir="${build_top}/${archive}"

	mkdir -p ${dir}${prefix}/lib/

	cp -a ${prefix}/lib/ld-linux-aarch64_ilp32.so.1 ${dir}${prefix}/lib/
	cp -a ${prefix}/libilp32 ${dir}${prefix}/

	cp -a ${prefix}/lib/ld-linux-aarch64.so.1 ${dir}${prefix}/lib/
	cp -a ${prefix}/lib64 ${dir}${prefix}/

	echo "$(date)" > ${dir}${prefix}/info.txt
	echo "$(uname -a)" >> ${dir}${prefix}/info.txt
	echo "$(${CC} --version)" >> ${dir}${prefix}/info.txt

	tar -cvzf ${build_top}/${archive}.tar.gz -C ${dir} ${prefix#/}
}
