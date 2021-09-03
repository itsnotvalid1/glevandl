#!/bin/bash

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Build toolchain." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -c --check    - Run shellcheck." >&2
	echo "  -h --help     - Show this help and exit." >&2
	echo "  --config-file - Config file. Default: '${config_file}'." >&2
	echo "  --build-top   - Top build directory. Default: '${build_top}'." >&2
	echo "  --destdir     - Install destdir directory. Default: '${destdir}'." >&2
	echo "  --prefix      - Install prefix. Default: '${prefix}'." >&2
	echo "Option steps:" >&2
	echo "  -1 --git-clone     - Clone git repos." >&2
	echo "  -2 --binutils      - Build binutils." >&2
	echo "  -3 --gcc-bootstrap - Build bootstrap gcc." >&2
	echo "  -4 --headers       - Build Linux headers." >&2
	echo "  -5 --glibc-lp64    - Build glibc_lp64." >&2
	echo "  -6 --glibc-ilp32   - Build glibc_ilp32." >&2
	echo "  -7 --gcc-final     - Build final gcc." >&2
	echo "  -8 --archive       - Create toolchain archive files." >&2
	echo "Environment:" >&2
	echo "  DEBUG_TOOLCHAIN_SRC - Default: '${DEBUG_TOOLCHAIN_SRC}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="ch12345678"
	local long_opts="check,help,\
config-file:,build-top:,destdir:,prefix:,\
git-clone,binutils,gcc-bootstrap,headers,glibc-lp64,glibc-ilp32,gcc-final,archive"

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
		-c | --check)
			check=1
			shift
			;;
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
		-2 | --binutils)
			step_binutils=1
			shift
			;;
		-3 | --gcc-bootstrap)
			step_gcc_bootstrap=1
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
		-7 | --gcc-final)
			step_gcc_final=1
			shift
			;;
		-8 | --archive)
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
	if [[ ${current_step} ]]; then
		echo "${script_name}: current_step = ${current_step}" >&2
	fi
	echo "${script_name}: Done: ${result}: ${end_time} sec ($(sec_to_min ${end_time}) min)" >&2
}

print_git_info() {
	local repo=${1}

	git -C ${repo} rev-parse HEAD
	git -C ${repo} show --oneline --no-patch 
}

git_clone() {
	git_checkout_safe ${binutils_src} ${binutils_repo} "${binutils_branch}"
	git_checkout_safe ${gcc_src} ${gcc_repo} "${gcc_branch}"
	pushd ${gcc_src}
	bash -x ./contrib/download_prerequisites
	popd
	git_checkout_safe ${glibc_src} ${glibc_repo} "${glibc_branch}"
	git_checkout_safe ${linux_src} ${linux_repo} "${linux_branch}"

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
	} | tee --append ${log_file}
}

build_binutils() {
	local dir="${build_dir}/binutils"

	rm -rf ${dir}
	mkdir -p ${dir}

	export PATH="${dest_pre}/bin:${path_orig}"

	pushd ${dir}
	${binutils_src}/configure \
		${target_opts} \
		--prefix=${dest_pre} \
		--with-sysroot=${dest_pre}
	popd

	make -C ${dir} -j ${cpus} all
	make -C ${dir} install

	export PATH="${path_orig}"
	find ${dest_pre} -type f -ls >> ${dir}/manifest.txt
}

build_gcc_bootstrap() {
	local dir="${build_dir}/gcc_bootstrap"

	rm -rf ${dir}
	mkdir -p ${dir}

	export PATH="${dest_pre}/bin:${path_orig}"
	mkdir -p ${dest_pre}/usr/lib

	pushd ${dir}
	${gcc_src}/configure \
		${target_opts} \
		--prefix=${dest_pre} \
		--with-sysroot=${dest_pre} \
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

	make -C ${dir} -j ${cpus} all-gcc all-target-libgcc
	make -C ${dir} install-gcc install-target-libgcc

	unset BUILD_CC CC CXX AR RANLIB AS LD
	export PATH="${path_orig}"
	find ${dest_pre} -type f -ls >> ${dir}/manifest.txt
}

build_headers() {
	make -C ${linux_src} -j ${cpus} \
		ARCH=${target_arch} \
		CROSS_COMPILE="${target_triple}-" \
		INSTALL_HDR_PATH="${dest_pre}/usr" \
		headers_install

	find ${dest_pre} -type f -ls >> ${build_dir}/headers-manifest.txt
}

build_glibc() {
	local abi=${1}
	local dir="${build_dir}/glibc_${abi}"

	rm -rf ${dir}
	mkdir -p ${dir}
	export PATH="${dest_pre}/bin:${path_orig}"

	pushd ${dir}
	${glibc_src}/configure \
		--with-headers=${headers_dir} \
		--enable-obsolete-rpc \
		--enable-add-ons \
		--prefix=/usr \
		--host=${target_triple} \
		BUILD_CC="/usr/bin/gcc" \
		CC="${dest_pre}/bin/${target_triple}-gcc -mabi=${abi}" \
		CXX="${dest_pre}/bin/${target_triple}-g++ -mabi=${abi}" \
		AR=${target_triple}-ar \
		AS=${target_triple}-as \
		LD=${target_triple}-ld \
		NM=${target_triple}-nm \
		OBJCOPY=${target_triple}-objcopy \
		OBJDUMP=${target_triple}-objdump \
		RANLIB=${target_triple}-ranlib \
		READELF=${target_triple}-readelf \
		STRIP=${target_triple}-strip
	popd

	make -C ${dir} -j ${cpus} all
	#make -C ${dir} -j ${cpus} tests
	make -C ${dir} DESTDIR=${dest_pre} install
	export PATH="${path_orig}"
	find ${dest_pre} -type f -ls >> ${dir}/manifest.txt
}

build_gcc_final() {
	local dir="${build_dir}/gcc_final"

	rm -rf ${dir}
	mkdir -p ${dir}

	export PATH="${dest_pre}/bin:${path_orig}"

	pushd ${dir}
	${gcc_src}/configure \
		${target_opts} \
		--prefix=${dest_pre} \
		--with-sysroot=${dest_pre} \
		--with-multilib-list=lp64,ilp32 \
		--enable-gnu-indirect-function \
		--enable-languages=c,c++,fortran \
		--enable-threads \
		--enable-shared \
		--disable-libsanitizer \
		--disable-bootstrap
	popd

	make -C ${dir} -j ${cpus} all
	make -C ${dir} install

	export PATH="${path_orig}"
	find ${dest_pre} -type f -ls >> ${dir}/manifest.txt
}

archive_toolchain() {
	tar -cvzf "${build_top}/ilp32-toolchain--${build_name}.tar.gz" \
		-C ${destdir} ${prefix#/}
}

archive_libraries() {
	tar -cvzf "${build_top}/ilp32-libraries--${build_name}.tar.gz" \
		-C ${destdir} \
		${prefix#/}/lib/ld-linux-aarch64_ilp32.so.1 \
		${prefix#/}/libilp32 \
		${prefix#/}/lib/ld-linux-aarch64.so.1 \
		${prefix#/}/lib64
}

archive_glibc_tests() {
	tar -cvzf "${build_top}/glibc-src--${build_name}.tar.gz" \
		-C "${src_dir}" "glibc"

	local abi
	for abi in lp64 ilp32; do
		tar -cvzf "${build_top}/glibc-${abi}-tests--${build_name}.tar.gz" \
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
	} | tee --append ${log_file}
}

print_info() {
	local log_file=${1}

	print_gcc_info ${dest_pre}/bin/${target_triple}-gcc ${log_file}
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

test_for_file() {
	local type=${1}
	local file=${2}

	if [[ ! -f ${file} ]]; then
		echo -e "${script_name}: ${FUNCNAME[0]}: ERROR: Bad ${type}: '${file}'" >&2
		usage
		exit 1
	fi
}

test_for_headers() {
	test_for_file "kernel headers" "${headers_dir}/linux/netfilter.h"
}

test_for_binutils() {
	test_for_file "binutils" "${dest_pre}/${target_triple}/bin/ld"
}

test_for_gcc() {
	test_for_file "gcc" "${dest_pre}/bin/${target_triple}-gcc"
}

test_for_glibc() {
	test_for_file "glibc" "${dest_pre}/lib/ld-linux-aarch64_ilp32.so.1"
}

#===============================================================================
# program start
#===============================================================================

export PS4='\[\033[0;33m\]+${BASH_SOURCE##*/}:${LINENO}: \[\033[0;37m\]'
set -x

script_name="${0##*/}"
build_time="$(date +%Y.%m.%d-%H.%M.%S)"

current_step="setup"
trap "on_exit 'failed.'" EXIT
set -e

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
source ${SCRIPTS_TOP}/lib/util.sh
source ${SCRIPTS_TOP}/lib/toolchain.sh

process_opts "${@}"

cpus=$(cpu_count)
path_orig="${PATH}"

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

if [[ ${config_file} && -f ${config_file} ]]; then
	source ${config_file}
fi

build_top="${build_top:-$(pwd)}"

build_dir="${build_dir:-${build_top}/build}"
src_dir="${src_dir:-${build_top}/src}"

prefix="${prefix:-/opt/ilp32}"
destdir="${destdir:-${build_top}/destdir}"
dest_pre="${destdir}${prefix}"
headers_dir="${dest_pre}/usr/include"

build_name="${build_name:-${build_time}}"
log_file="${log_file:-${build_top}/${script_name}--${build_name}.log}"

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
	binutils_branch=${binutils_branch_master}
	gcc_branch=${gcc_branch_master}
	glibc_branch=${glibc_branch_master}
	linux_branch=${linux_branch_master}
fi

if [[ ${use_release_branches} ]]; then
	echo "${script_name}: Using toolchain release branches." >&2
	binutils_branch=${binutils_branch_release}
	gcc_branch=${gcc_branch_release}
	glibc_branch=${glibc_branch_release}
	linux_branch=${linux_branch_release}
fi

if [[ ${use_stable_branches} ]]; then
	echo "${script_name}: Using toolchain stable branches." >&2
	binutils_branch=${binutils_branch_stable}
	gcc_branch=${gcc_branch_stable}
	glibc_branch=${glibc_branch_stable}
	linux_branch=${linux_branch_stable}
fi

binutils_branch=${binutils_branch:-${binutils_branch_stable}}
gcc_branch=${gcc_branch:-${gcc_branch_stable}}
glibc_branch=${glibc_branch:-${glibc_branch_stable}}
linux_branch=${linux_branch:-${linux_branch_stable}}

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

if [[ ${check} ]]; then
	run_shellcheck "${0}"
	trap "on_exit 'Success'" EXIT
	exit 0
fi

if [[ ${DESTDIR} ]]; then
	echo "${script_name}: ERROR: Use --destdir option, not DESTDIR environment variable." >&2
	exit 1
fi

SECONDS=0

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

if [[ ${host_arch} != ${target_arch} ]]; then
	target_opts="${target_opts:-"--target=${target_triple}"}"
else
	target_opts="${target_opts:-"--target=${target_triple} --host=${target_triple} --build=${target_triple}"}"
fi

mkdir -p ${build_top}
cp -vf ${BASH_SOURCE} ${build_top}/${script_name}--${build_name}.sh

print_branch_info ${log_file}

printenv

while true; do
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
		unset step_git_clone
	elif [[ ${step_binutils} ]]; then
		current_step="step_binutils"
		test_for_src
		mkdir -p ${dest_pre}
		rm -rf ${dest_pre}/*
		build_binutils
		unset step_binutils
	elif [[ ${step_gcc_bootstrap} ]]; then
		current_step="step_gcc_bootstrap"
		test_for_src
		test_for_binutils
		build_gcc_bootstrap
		unset step_gcc_bootstrap
	elif [[ ${step_headers} ]]; then
		current_step="step_headers"
		test_for_src
		test_for_gcc
		build_headers
		unset step_headers
	elif [[ ${step_glibc_lp64} ]]; then
		current_step="step_glibc_lp64"
		test_for_src
		test_for_gcc
		test_for_headers
		build_glibc lp64
		unset step_glibc_lp64
	elif [[ ${step_glibc_ilp32} ]]; then
		current_step="step_glibc_ilp32"
		test_for_src
		test_for_gcc
		test_for_headers
		build_glibc ilp32
		unset step_glibc_ilp32
	elif [[ ${step_gcc_final} ]]; then
		current_step="step_gcc_final"
		test_for_src
		test_for_glibc
		build_gcc_final
		unset step_gcc_final
	elif [[ ${step_archive} ]]; then
		current_step="step_archive"
		test_for_binutils
		test_for_gcc
		test_for_glibc
		archive_toolchain
		archive_libraries
		archive_glibc_tests
		print_info ${log_file}
		unset step_archive
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
