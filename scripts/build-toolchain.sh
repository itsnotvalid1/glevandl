#!/bin/bash

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Build toolchain." >&2
	echo "Usage: ${name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help                 - Show this help and exit." >&2
	echo "  --build-top   <directory> - Top build directory. Default: '${build_top}'." >&2
#	echo "  --dest-dir    <directory> - Make DESTDIR. Default: '${dest_dir}'." >&2
	echo "  --install-dir <directory> - Install directory. Default: '${install_dir}'." >&2
	echo "Option steps:" >&2
	echo "  -1 --git-clone     - Clone git repos." >&2
	echo "  -2 --binutils      - Build binutils." >&2
	echo "  -3 --gcc-bootstrap - Bild bootstrap gcc." >&2
	echo "  -4 --headers       - Build Linux headers." >&2
	echo "  -5 --glibc-lp64    - Build glibc_lp64." >&2
	echo "  -6 --glibc-ilp32   - Build glibc_ilp32." >&2
	echo "  -7 --gcc-final     - Build final gcc." >&2
	echo "  -8 --print-info    - Print toolchain info." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="h12345678"
	local long_opts="help,\
build-top:,dest-dir:,install-dir:,\
git-clone,binutils,gcc-bootstrap,headers,glibc-lp64,glibc-ilp32,gcc-final,print-info"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${name}" -- "$@")

	eval set -- "${opts}"
	
	if [[ ${1} == '--' ]]; then
		echo "${name}: ERROR: Must specify an option step." >&2
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
		--build-top)
			build_top="${2}"
			shift 2
			;;
		--dest-dir)
			dest_dir="${2}"
			shift 2
			;;
		--install-dir)
			install_dir="${2}"
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
		-8 | --print-info)
			step_print_info=1
			shift
			;;
		--)
			shift
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

	local end_time=${SECONDS}

	set +x
	if [[ ${current_step} ]]; then
		echo "${name}: current_step = ${current_step}" >&2
	fi
	echo "${name}: Done: ${result}: ${end_time} sec ($(sec_to_min ${end_time}) min)" >&2
}

git_clone() {
	git_checkout_safe ${binutils_src} ${binutils_repo} "${binutils_branch}"
	git_checkout_safe ${gcc_src} ${gcc_repo} "${gcc_branch}"
	pushd ${gcc_src}
	bash -x ./contrib/download_prerequisites
	popd
	git_checkout_safe ${glibc_src} ${glibc_repo} "${glibc_branch}"
	git_checkout_safe ${linux_src} ${linux_repo} "${linux_branch}"
}

build_binutils() {
	local dir="${build_dir}/binutils"

	rm -rf ${dir}
	mkdir -p ${dir}

	export PATH="${install_dir}/bin:${path_orig}"

	pushd ${dir}
	${binutils_src}/configure \
		${target_opts} \
		--prefix=${install_dir} \
		--with-sysroot=${install_dir}
	popd

	make -C ${dir} -j ${cpus} all
	make -C ${dir} install

	export PATH="${path_orig}"
}

build_gcc_bootstrap() {
	local dir="${build_dir}/gcc_bootstrap"

	rm -rf ${dir}
	mkdir -p ${dir}

	export PATH="${install_dir}/bin:${path_orig}"
	mkdir -p ${install_dir}/usr/lib

	pushd ${dir}
	${gcc_src}/configure \
		${target_opts} \
		--prefix=${install_dir} \
		--with-sysroot=${install_dir} \
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
}

build_headers() {
	make -C ${linux_src} -j ${cpus} \
		ARCH=${target_arch} \
		CROSS_COMPILE="${target_triple}-" \
		INSTALL_HDR_PATH="${install_dir}/usr" \
		headers_install
}

build_glibc() {
	local abi=${1}
	local dir="${build_dir}/glibc_${abi}"

	rm -rf ${dir}
	mkdir -p ${dir}
	export PATH="${install_dir}/bin:${path_orig}"

	pushd ${dir}
	${glibc_src}/configure \
		--with-headers=${headers_dir} \
		--enable-obsolete-rpc \
		--enable-add-ons \
		--prefix=/usr \
		--host=${target_triple} \
		BUILD_CC="/usr/bin/gcc" \
		CC="${install_dir}/bin/${target_triple}-gcc -mabi=${abi}" \
		CXX="${install_dir}/bin/${target_triple}-g++ -mabi=${abi}" \
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
	make -C ${dir} -j ${cpus} DESTDIR=${install_dir} install
	export PATH="${path_orig}"
}

build_gcc_final() {
	local dir="${build_dir}/gcc_final"

	rm -rf ${dir}
	mkdir -p ${dir}

	export PATH="${install_dir}/bin:${path_orig}"

	pushd ${dir}
	${gcc_src}/configure \
		${target_opts} \
		--prefix=${install_dir} \
		--with-sysroot=${install_dir} \
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
}

print_info() {
	local log_file=${1}

	print_gcc_info ${install_dir}/bin/${target_triple}-gcc ${log_file}
}

test_for_src() {
	local sources="binutils gcc glibc linux"

	for n in ${sources}; do
		local src_dir="${n}_src"
		local checker="${n}_checker"

		if [[ ! -f "${!checker}" ]]; then
			echo -e "${name}: ERROR: Bad ${n} src: '${src_dir}'" >&2
			echo -e "${name}: ERROR: Must set ${n}_src to root of ${n} sources." >&2
			usage
			exit 1
		fi
	done
}

test_for_headers() {
	if [[ ! -f ${headers_dir}/linux/netfilter.h ]]; then
		echo -e "${name}: ERROR: Bad kernel headers: '${headers_dir}'" >&2
		usage
		exit 1
	fi
}

test_for_binutils() {
	local file="${install_dir}/${target_triple}/bin/ld"

	if [[ ! -f ${file} ]]; then
		echo -e "${name}: ERROR: Bad binutils: '${file}'" >&2
		usage
		exit 1
	fi
}

test_for_gcc() {
	local file="${install_dir}/bin/${target_triple}-gcc"

	if [[ ! -f ${file} ]]; then
		echo -e "${name}: ERROR: Bad gcc: '${file}'" >&2
		usage
		exit 1
	fi
}

test_for_glibc() {
	echo "${FUNCNAME[0]}: TODO" >&2
}

#===============================================================================
# program start
#===============================================================================

export PS4='\[\033[0;33m\]+${BASH_SOURCE##*/}:${LINENO}: \[\033[0;37m\]'
set -x

name="${0##*/}"
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

build_top=${build_top:-"$(pwd)"}

build_dir=${build_dir:-"${build_top}/build"}
src_dir=${src_dir:-"${build_top}/src"}
install_dir=${install_dir:-"${build_top}/install"}
headers_dir="${install_dir}/usr/include"
log_file=${log_file:-"${build_top}/build-${build_time}.log"}

binutils_src="${src_dir}/binutils"
binutils_repo="git://sourceware.org/git/binutils-gdb.git"
binutils_branch="master"
binutils_checker="${binutils_src}/bfd/elfxx-aarch64.c"

gcc_src="${src_dir}/gcc"
gcc_repo="git://gcc.gnu.org/git/gcc.git"
gcc_branch="master"
gcc_checker="${gcc_src}/libgcc/memcpy.c"

glibc_src="${src_dir}/glibc"
glibc_repo="git://sourceware.org/git/glibc.git"
glibc_branch="arm/ilp32"
glibc_checker="${glibc_src}/elf/global.c"

linux_src="${src_dir}/linux"
linux_repo="https://git.kernel.org/pub/scm/linux/kernel/git/arm64/linux.git"
linux_branch="staging/ilp32-5.1"
linux_checker="${linux_src}/lib/bitmap.c"

binutils_branch_release="binutils-2_32"
gcc_branch_release="gcc-9_2_0-release"
glibc_branch_release="arm/ilp32"
linux_branch_release="staging/ilp32-5.1"

binutils_branch_stable="binutils-2_32-branch"
gcc_branch_stable="gcc-9-branch"
glibc_branch_stable="arm/ilp32"
linux_branch_stable="staging/ilp32-5.1"

binutils_branch=${binutils_branch_stable}
gcc_branch=${gcc_branch_stable}
glibc_branch=${glibc_branch_stable}
linux_branch=${linux_branch_stable}

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

SECONDS=0

host_arch=$(get_arch "$(uname -m)")
target_arch=$(get_arch "arm64")

case ${target_arch} in
arm64)
	target_triple="aarch64-linux-gnu"
	;;
*)
	echo "${name}: ERROR: Unsupported target arch '${target_arch}'." >&2
	exit 1
	;;
esac

if [[ ${host_arch} != ${target_arch} ]]; then
	target_opts="${target_opts:-"--target=${target_triple}"}"
else
	target_opts="${target_opts:-"--target=${target_triple} --host=${target_triple} --build=${target_triple}"}"
fi

cp -vf ${BASH_SOURCE} ${build_top}/

while true; do
	if [[ ${step_git_clone} ]]; then
		current_step="step_git_clone"
		git_clone
		unset step_git_clone
	elif [[ ${step_binutils} ]]; then
		current_step="step_binutils"
		test_for_src
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
	elif [[ ${step_print_info} ]]; then
		current_step="step_print_info"
		test_for_binutils
		test_for_gcc
		test_for_glibc
		print_info ${log_file}
		unset step_print_info
	else
		if [[ ${current_step} == "setup" ]]; then
			echo "${name}: ERROR: Must specify an option step." >&2
			usage
			exit 1
		fi
		break
	fi
done

unset current_step

trap "on_exit 'Success.'" EXIT
