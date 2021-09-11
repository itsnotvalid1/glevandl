#!/bin/bash

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Build toolchain." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help     - Show this help and exit." >&2
	echo "  --config-file - Config file. Default: '${config_file}'." >&2
	echo "  --build-top   - Top build directory. Default: '${build_top}'." >&2
	echo "  --destdir     - Install destdir directory. Default: '${destdir}'." >&2
	echo "  --prefix      - Install prefix. Default: '${prefix}'." >&2
	echo "Option steps:" >&2
	echo "  -1 --git-clone          - Clone git repos." >&2
	echo "  -2 --bootstrap-binutils - Build bootstrap binutils." >&2
	echo "  -3 --bootstrap-gcc      - Build bootstrap gcc." >&2
	echo "  -4 --headers            - Build Linux headers." >&2
	echo "  -5 --glibc-lp64         - Build glibc_lp64." >&2
	echo "  -6 --glibc-ilp32        - Build glibc_ilp32." >&2
	echo "  -7 --final-binutils     - Build binutils." >&2
	echo "  -8 --final-gcc          - Build final gcc." >&2
	echo "  -9 --archive            - Create toolchain archive files." >&2
	echo "Environment:" >&2
	echo "  DEBUG_TOOLCHAIN_SRC - Default: '${DEBUG_TOOLCHAIN_SRC}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="h123456789"
	local long_opts="help,\
config-file:,build-top:,destdir:,prefix:,\
git-clone,bootstrap-binutils,bootstrap-gcc,headers,glibc-lp64,glibc-ilp32,,final-binutils,final-gcc,archive"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"
	
	if [[ ${1} == '--' ]]; then
		echo "${script_name}: ERROR: Must specify an option step." >&2
		usage
		exit 1
	fi

	while true ; do
		#echo "${FUNCNAME[0]}: @${1}@ @${2}@"
		case "${1}" in
		-h | --help)
			usage=1
			shift
			;;
		--config-file)
			config_file="${2}"
			shift 2
			;;
		--build-top)
			build_top="${2}"
			shift 2
			;;
		--destdir)
			destdir="${2}"
			shift 2
			;;
		--prefix)
			prefix="${2}"
			shift 2
			;;
		--src-dir)
			src_dir="${2}"
			shift 2
			;;
		-1 | --git-clone)
			step_git_clone=1
			shift
			;;
		-2 | --bootstrap-binutils)
			step_bootstrap_binutils=1
			shift
			;;
		-3 | --bootstrap-gcc)
			step_bootstrap_gcc=1
			shift
			;;
		-4 | --headers)
			step_headers=1
			shift
			;;
		-5 | --glibc-lp64)
			step_glibc_lp64=1
			shift
			;;
		-6 | --glibc-ilp32)
			step_glibc_ilp32=1
			shift
			;;
		-7 | --final-binutils)
			step_final_binutils=1
			shift
			;;
		-8 | --final-gcc)
			step_final_gcc=1
			shift
			;;
		-9 | --archive)
			step_archive=1
			shift
			;;
		--)
			shift
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
	local end_time=${SECONDS}

	set +x
	declare -A steps=(
		[setup]='0'
		[step_git_clone]='1'
		[step_bootstrap_binutils]='2'
		[step_bootstrap_gcc]='3'
		[step_headers]='4'
		[step_glibc_lp64]='5'
		[step_glibc_ilp32]='6'
		[step_final_binutils]='7'
		[step_final_gcc]='8'
		[step_archive]='9'
	)

	if [[ ${current_step} ]]; then
		echo "${script_name}: current_step = ${current_step} (${steps[${current_step}]})" >&2
	fi
	echo "${script_name}: Done: ${result}: ${end_time} sec ($(sec_to_min ${end_time}) min)" >&2
}

print_git_info() {
	local repo=${1}

	git -C "${repo}" rev-parse HEAD
	git -C "${repo}" show --oneline --no-patch
}

git_clone() {
	git_checkout_safe "${binutils_src}" "${binutils_repo}" "${binutils_branch}"
	git_checkout_safe "${gcc_src}" "${gcc_repo}" "${gcc_branch}"
	pushd "${gcc_src}"
	bash -x ./contrib/download_prerequisites
	popd
	git_checkout_safe "${glibc_src}" "${glibc_repo}" "${glibc_branch}"
	git_checkout_safe "${linux_src}" "${linux_repo}" "${linux_branch}"

	{
		echo "--- git info ---"
		echo "${binutils_repo}:${binutils_branch}"
		print_git_info ${binutils_src}
		echo ""
		echo "${gcc_repo}:${gcc_branch}"
		print_git_info ${gcc_src}
		echo ""
		echo "${glibc_repo}:${glibc_branch}"
		print_git_info ${glibc_src}
		echo ""
		echo "${linux_repo}:${linux_branch}"
		print_git_info ${linux_src}
		echo "-------------------------"
	} | tee --append "${log_file}"
}

build_bootstrap_binutils() {
	local dir="${build_dir}/bootstrap_binutils"

	rm -rf "${dir}"
	mkdir -p "${dir}"

	export PATH="${bootstrap}/bin:${path_orig}"

	pushd "${dir}"
	"${binutils_src}/configure" \
		${target_opts} \
		--prefix=${bootstrap} \
		--with-sysroot=${bootstrap}
	popd

	make -C "${dir}" -j ${cpus} all
	make -C "${dir}" install

	export PATH="${path_orig}"
	find "${bootstrap}" -type f -ls > "${logs_dir}/manifest-bootstrap-binutils"
}

build_bootstrap_gcc() {
	local dir="${build_dir}/bootstrap_gcc"

	rm -rf "${dir}"
	mkdir -p "${dir}"

	export PATH="${bootstrap}/bin:${path_orig}"

	mkdir -p "${bootstrap}/usr/lib"

	pushd "${dir}"
	"${gcc_src}/configure" \
		${target_opts} \
		--prefix="${bootstrap}" \
		--with-sysroot="${bootstrap}" \
		--enable-gnu-indirect-function \
		--with-newlib \
		--without-headers \
		--with-multilib-list=lp64,ilp32 \
		--enable-languages=c \
		--enable-threads=no \
		--disable-shared \
		--disable-decimal-float \
		--disable-libsanitizer \
		--disable-bootstrap
	popd

#		--with-native-system-header-dir="/opt/ilp32/aarch64-linux-gnu/include-i"
#		--sysroot-headers-suffix="/opt/ilp32/aarch64-linux-gnu-d"
#		--with-build-sysroot="${destdir}-h" \
#		--with-local-prefix=

	make -C "${dir}" -j ${cpus} all-gcc all-target-libgcc
	make -C "${dir}" install-gcc install-target-libgcc

	unset BUILD_CC CC CXX AR RANLIB AS LD
	export PATH="${path_orig}"

	find "${bootstrap}" -type f -ls > "${logs_dir}/manifest-bootstrap-gcc"
}

build_headers() {
	export PATH="${bootstrap}/bin:${path_orig}"

	make -C "${linux_src}" -j ${cpus} \
		ARCH=${target_arch} \
		CROSS_COMPILE="${target_triple}-" \
		INSTALL_HDR_PATH="${destdir}${prefix}/usr" \
		headers_install

	export PATH="${path_orig}"
	find "${destdir}${prefix}" -type f -ls > "${logs_dir}/manifest-headers"
}

build_glibc() {
	local abi=${1}
	local dir="${build_dir}/glibc_${abi}"

	rm -rf "${dir}"
	mkdir -p "${dir}"

	export PATH="${bootstrap}/bin:${path_orig}"
	local cross="${bootstrap}/bin/${target_triple}"

	pushd "${dir}"
	"${glibc_src}/configure" \
		--prefix="/usr" \
		--with-headers="${destdir}${prefix}/usr/include" \
		--enable-obsolete-rpc \
		--enable-add-ons \
		--host="${target_triple}" \
		BUILD_CC="/usr/bin/gcc" \
		CC="${cross}-gcc -mabi=${abi}" \
		CXX="${cross}-g++ -mabi=${abi}" \
		AR="${cross}-ar" \
		AS="${cross}-as" \
		LD="${cross}-ld" \
		NM="${cross}-nm" \
		OBJCOPY="${cross}-objcopy" \
		OBJDUMP="${cross}-objdump" \
		RANLIB="${cross}-ranlib" \
		READELF="${cross}-readelf" \
		STRIP="${cross}-strip"
	popd

	make -C "${dir}" -j ${cpus} all
	make -C "${dir}" DESTDIR="${destdir}${prefix}" install

	unset BUILD_CC CC CXX AR RANLIB AS LD
	export PATH="${path_orig}"
	find "${destdir}${prefix}" -type f -ls > "${logs_dir}/manifest-glibc_${abi}"
}

build_final_binutils() {
	local dir="${build_dir}/final_binutils"

	rm -rf "${dir}"
	mkdir -p "${dir}"

	export PATH="${bootstrap}/bin:${path_orig}"

	pushd "${dir}"
	"${binutils_src}/configure" \
		${target_opts} \
		--prefix="${prefix}" \
		--with-sysroot="${prefix}"
	popd

	make -C "${dir}" -j ${cpus} all
	make -C "${dir}" DESTDIR="${destdir}" install

	export PATH="${path_orig}"
	find "${destdir}${prefix}" -type f -ls > "${logs_dir}/manifest-final-binutils.txt"
}

build_final_gcc() {
	local dir="${build_dir}/final_gcc"

	rm -rf "${dir}"
	mkdir -p "${dir}"

	export PATH="${bootstrap}/bin:${path_orig}"

	mkdir -p "${destdir}${prefix}/usr/lib"

	pushd "${dir}"
	"${gcc_src}/configure" \
		${target_opts} \
		--prefix="${prefix}" \
		--with-sysroot="${destdir}${prefix}" \
		--with-multilib-list=lp64,ilp32 \
		--enable-gnu-indirect-function \
		--enable-languages=c,c++,fortran \
		--enable-threads \
		--enable-shared \
		--disable-libsanitizer \
		--disable-bootstrap
	popd

#		--with-native-system-header-dir="/opt/ilp32/aarch64-linux-gnu/include-i"
#		--sysroot-headers-suffix="/opt/ilp32/aarch64-linux-gnu-d"
#		--with-build-sysroot="${destdir}-h" \
#		--with-local-prefix=

	make -C "${dir}" -j ${cpus} all
	make -C "${dir}" DESTDIR="${destdir}" install

	export PATH="${path_orig}"
	find "${destdir}${prefix}" -type f -ls > "${logs_dir}/manifest-final_gcc"
}

archive_toolchain() {
	tar -cvzf "${archives_dir}/ilp32-toolchain--${build_name}.tar.gz" \
		-C "${destdir}" "${prefix#/}"
}

archive_libraries() {
	tar -cvzf "${archives_dir}/ilp32-libraries--${build_name}.tar.gz" \
		-C "${destdir}" \
		"${prefix#/}/lib/ld-linux-aarch64_ilp32.so.1" \
		"${prefix#/}/libilp32" \
		"${prefix#/}/lib/ld-linux-aarch64.so.1" \
		"${prefix#/}/lib64"
}

archive_glibc_tests() {
	tar -cvzf "${archives_dir}/glibc-src--${build_name}.tar.gz" \
		-C "${src_dir}" "glibc"

	local abi
	for abi in lp64 ilp32; do
		tar -cvzf "${archives_dir}/glibc-${abi}-tests--${build_name}.tar.gz" \
			-C "${build_dir}" "glibc_${abi}"
	done
}

print_branch_info() {
	local log_file=${1}

	{
		echo "--- branch info ---"
		echo "binutils_repo   = ${binutils_repo}"
		echo "binutils_branch = ${binutils_branch}"
		echo "gcc_repo        = ${gcc_repo}"
		echo "gcc_branch      = ${gcc_branch}"
		echo "glibc_repo      = ${glibc_repo}"
		echo "glibc_branch    = ${glibc_branch}"
		echo "linux_repo      = ${linux_repo}"
		echo "linux_branch    = ${linux_branch}"
		echo "-------------------"
	} | tee --append "${log_file}"
}

print_env() {
	local log_file=${1}

	{
		echo "--- env -----------"
		printenv 
		echo "-------------------"
	} | tee --append "${log_file}"
}


print_final_gcc_info() {
	local log_file=${1}

	print_gcc_info "${destdir}${prefix}/bin/${target_triple}-gcc" "${log_file}"
}

test_for_file() {
	local warn=${1}
	local type=${2}
	local file=${3}

	if [[ ! -f "${file}" ]]; then
		if [[ "${warn}" == "warn" ]]; then
			echo -e "${script_name}: ${FUNCNAME[0]}: WARNING: Missing ${type}: '${file}'" >&2
		else
			echo -e "${script_name}: ${FUNCNAME[0]}: ERROR: Missing ${type}: '${file}'" >&2
			usage
			exit 1
		fi
	fi
}

test_for_src() {
	local sources="binutils gcc glibc linux"

	for n in ${sources}; do
		local src_dir="${n}_src"
		local checker="${n}_checker"

		if [[ ! -f "${!checker}" ]]; then
			echo -e "${script_name}: ${FUNCNAME[0]}: ERROR: Bad ${n} src: '${src_dir}'" >&2
			echo -e "${script_name}: ${FUNCNAME[0]}: ERROR: Must set ${n}_src to root of ${n} sources." >&2
			usage
			exit 1
		fi
	done
}

test_for_bootstrap_binutils() {
	test_for_file "fatal" "bootstrap-binutils" "${bootstrap}/bin/${target_triple}-ld"
}

test_for_bootstrap_gcc() {
	test_for_file "fatal" "bootstrap-gcc" "${bootstrap}/bin/${target_triple}-gcc"
}

test_for_headers() {
	test_for_file "fatal" "kernel headers" "${destdir}${prefix}/usr/include/linux/netfilter.h"
}

test_for_glibc() {
	test_for_file "fatal" "glibc ilp32 ld" "${destdir}${prefix}/lib/ld-linux-aarch64_ilp32.so.1"
	test_for_file "fatal" "glibc lp64 ld" "${destdir}${prefix}/lib/ld-linux-aarch64.so.1"
	test_for_file "fatal" "glibc headers" "${destdir}${prefix}/usr/include/stdio.h"
}

test_for_final_binutils() {
	test_for_file "fatal" "final-binutils" "${destdir}${prefix}/bin/${target_triple}-ld"
}

test_for_final_gcc() {
	test_for_file "fatal" "final-gcc" "${destdir}${prefix}/bin/${target_triple}-gcc"
}

#===============================================================================
export PS4='\[\033[0;33m\]+${BASH_SOURCE##*/}:${LINENO}: \[\033[0;37m\]'
set -x

script_name="${0##*/}"
build_time="$(date +%Y.%m.%d-%H.%M.%S)"
build_name="${build_name:-${build_time}}"

current_step="setup"
trap "on_exit 'failed.'" EXIT
set -e

SCRIPTS_TOP="${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}"
source "${SCRIPTS_TOP}/lib/util.sh"
source "${SCRIPTS_TOP}/lib/toolchain.sh"

process_opts "${@}"

cpus=$(cpu_count)
path_orig="${PATH}"

host_arch=$(get_arch "$(uname -m)")
target_arch=$(get_arch "arm64")

case ${target_arch} in
arm64)
	target_triple="aarch64-linux-gnu"
	;;
*)
	echo "${script_name}: ERROR: Unsupported target arch '${target_arch}'." >&2
	exit 1
	;;
esac

binutils_branch_master="master"
gcc_branch_master="master"
glibc_branch_master="arm/ilp32"
linux_branch_master="ilp32-5.5.y"

binutils_branch_stable="binutils-2_32-branch"
gcc_branch_stable="releases/gcc-9"
glibc_branch_stable="arm/ilp32"
linux_branch_stable="ilp32-5.5.y"

binutils_branch_release="binutils-2_32"
gcc_branch_release="gcc-9_2_0-release"
glibc_branch_release="arm/ilp32"
linux_branch_release="ilp32-5.5.y"

if [[ ${config_file} && -f "${config_file}" ]]; then
	source "${config_file}"
fi

build_top="${build_top:-$(pwd)}"

src_dir="${src_dir:-${build_top}/src}"
build_dir="${build_dir:-${build_top}/build}"
bootstrap="${bootstrap:-${build_top}/bootstrap}"
destdir="${destdir:-${build_top}/destdir}"

prefix="${prefix:-/opt/ilp32}"

logs_dir="${logs_dir:-${build_top}/logs-${build_name}}"
log_file="${log_file:-${logs_dir}/${build_name}.log}"

archives_dir="${archives_dir:-${build_top}/archives-${build_name}}"

binutils_src="${binutils_src:-${src_dir}/binutils}"
binutils_repo="${binutils_repo:-git://sourceware.org/git/binutils-gdb.git}"
binutils_checker="${binutils_checker:-${binutils_src}/bfd/elfxx-aarch64.c}"

gcc_src="${gcc_src:-${src_dir}/gcc}"
gcc_repo="${gcc_repo:-git://gcc.gnu.org/git/gcc.git}"
gcc_checker="${gcc_checker:-${gcc_src}/libgcc/memcpy.c}"

glibc_src="${glibc_src:-${src_dir}/glibc}"
glibc_repo="${glibc_repo:-git://sourceware.org/git/glibc.git}"
glibc_checker="${glibc_checker:-${glibc_src}/elf/global.c}"

linux_src="${linux_src:-${src_dir}/linux}"
#linux_repo="${linux_repo:-https://git.kernel.org/pub/scm/linux/kernel/git/arm64/linux.git}"
linux_repo="${linux_repo:-https://github.com/glevand/ilp32--linux.git}"
linux_checker="${linux_checker:-${linux_src}/lib/bitmap.c}"

if [[ ${use_master_branches} ]]; then
	echo "${script_name}: Using toolchain master branches." >&2
	binutils_branch="${binutils_branch_master}"
	gcc_branch="${gcc_branch_master}"
	glibc_branch="${glibc_branch_master}"
	linux_branch="${linux_branch_master}"
fi

if [[ ${use_release_branches} ]]; then
	echo "${script_name}: Using toolchain release branches." >&2
	binutils_branch="${binutils_branch_release}"
	gcc_branch="${gcc_branch_release}"
	glibc_branch="${glibc_branch_release}"
	linux_branch="${linux_branch_release}"
fi

if [[ ${use_stable_branches} ]]; then
	echo "${script_name}: Using toolchain stable branches." >&2
	binutils_branch="${binutils_branch_stable}"
	gcc_branch="${gcc_branch_stable}"
	glibc_branch="${glibc_branch_stable}"
	linux_branch="${linux_branch_stable}"
fi

binutils_branch="${binutils_branch:-${binutils_branch_stable}}"
gcc_branch="${gcc_branch:-${gcc_branch_stable}}"
glibc_branch="${glibc_branch:-${glibc_branch_stable}}"
linux_branch="${linux_branch:-${linux_branch_stable}}"

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

if [[ ${DESTDIR} ]]; then
	echo "${script_name}: ERROR: Use --destdir option, not DESTDIR environment variable." >&2
	exit 1
fi

SECONDS=0

if [[ ${host_arch} != ${target_arch} ]]; then
	target_opts="${target_opts:-"--target=${target_triple}"}"
else
	target_opts="${target_opts:-"--target=${target_triple} --host=${target_triple} --build=${target_triple}"}"
fi

mkdir -p "${build_dir}" "${logs_dir}"

cp -vf "${BASH_SOURCE}" "${logs_dir}/${build_name}--${script_name}.sh"

print_branch_info "${log_file}"
print_env "${log_file}"

if [[ ${step_git_clone} ]]; then
	current_step="step_git_clone"

	if [[ ${DEBUG_TOOLCHAIN_SRC} && -d ${DEBUG_TOOLCHAIN_SRC} ]]; then
		echo "${script_name}: INFO: Using DEBUG_TOOLCHAIN_SRC='${DEBUG_TOOLCHAIN_SRC}'." >&2
		rm -rf ${src_dir}
		cp -a --link ${DEBUG_TOOLCHAIN_SRC} ${src_dir}
	else
		echo "${script_name}: INFO: DEBUG_TOOLCHAIN_SRC not found: '${DEBUG_TOOLCHAIN_SRC}'." >&2
	fi
	git_clone
fi

if [[ ${step_bootstrap_binutils} ]]; then
	current_step="step_bootstrap_binutils"
	test_for_src
	mkdir -p "${bootstrap}"
	rm -rf "${bootstrap}"/*
	build_bootstrap_binutils
fi

if [[ ${step_bootstrap_gcc} ]]; then
	current_step="step_bootstrap_gcc"
	test_for_src
	test_for_bootstrap_binutils
	build_bootstrap_gcc
fi

if [[ ${step_headers} ]]; then
	current_step="step_headers"
	test_for_src
	test_for_bootstrap_binutils
	test_for_bootstrap_gcc
	mkdir -p "${destdir}${prefix}"
	rm -rf "${destdir}${prefix}"/*
	build_headers
fi

if [[ ${step_glibc_lp64} ]]; then
	current_step="step_glibc_lp64"
	test_for_src
	test_for_bootstrap_binutils
	test_for_bootstrap_gcc
	test_for_headers
	build_glibc lp64
fi

if [[ ${step_glibc_ilp32} ]]; then
	current_step="step_glibc_ilp32"
	test_for_src
	test_for_bootstrap_binutils
	test_for_bootstrap_gcc
	test_for_headers
	build_glibc ilp32
fi

if [[ ${step_final_binutils} ]]; then
	current_step="step_final_binutils"
	test_for_src
	test_for_bootstrap_binutils
	test_for_bootstrap_gcc
	build_final_binutils
fi

if [[ ${step_final_gcc} ]]; then
	current_step="step_final_gcc"
	test_for_src
	test_for_glibc
	test_for_final_binutils
	build_final_gcc
fi

if [[ ${step_archive} ]]; then
	current_step="step_archive"
	test_for_glibc
	test_for_final_binutils
	test_for_final_gcc
	mkdir -p "${archives_dir}"
	archive_toolchain
	archive_libraries
	archive_glibc_tests
	print_final_gcc_info "${log_file}"
	unset current_step
fi

if [[ ${current_step} == "setup" ]]; then
		echo "${script_name}: ERROR: Must specify an option step." >&2
		usage
		exit 1
fi

trap "on_exit 'Success.'" EXIT
exit 0
