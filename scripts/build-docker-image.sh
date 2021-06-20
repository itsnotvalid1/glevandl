#!/usr/bin/env bash

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Build ilp32-toolup, ilp32-builder and ilp32-runner container images." >&2
	echo "Usage: ${name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help           - Show this help and exit." >&2
	echo "  -f --force          - Removing existing docker image and rebuild." >&2
	echo "  -t --toolup         - Build ilp32-toolup container image." >&2
	echo "  -c --toolchain      - Build ilp32 toolchain." >&2
	echo "  -b --builder        - Build ilp32-builder container image." >&2
	echo "  -r --runner         - Build ilp32-runner container image." >&2
	echo "  --build-top         - Top build directory. Default: '${build_top}'." >&2
	echo "  --toolchain-destdir - Top toolchain directory. Default: '${toolchain_destdir}'." >&2
	echo "Environment:" >&2
	echo "  HOST_WORK_DIR       - Default: '${HOST_WORK_DIR}'" >&2
	echo "  CURRENT_WORK_DIR    - Default: '${CURRENT_WORK_DIR}'" >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hftcbr"
	local long_opts="help,force,toolup,toolchain,builder,runner,build-top:,--toolchain-destdir:"

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
		-f | --force)
			force=1
			shift
			;;
		-t | --toolup)
			step_toolup=1
			shift
			;;
		-c | --toolchain)
			step_toolchain=1
			shift
			;;
		-b | --builder)
			step_builder=1
			shift
			;;
		-r | --runner)
			step_runner=1
			shift
			;;
		--build-top)
			build_top="${2}"
			shift 2
			;;
		--toolchain-destdir)
			toolchain_destdir="${2}"
			shift 2
			;;
		--)
			shift
			if [[ ${1} ]]; then
				echo "${name}: ERROR: Got extra opts: '${@}'" >&2
				exit 1
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

	if [ -d ${tmp_dir} ]; then
		rm -rf ${tmp_dir}
	fi

	local end_time=${SECONDS}

	set +x
	if [[ ${current_step} != "done" ]]; then
		echo "${name}: ERROR: Step '${current_step}' failed." >&2
	fi
	echo "${name}: Done: ${result} ${end_time} sec ($(sec_to_min ${end_time}) min)" >&2
}

build_image() {
	local image_type=${1}
	local destdir=${2}
	local prefix=${3}

	local version=${VERSION:-"1"}
	local docker_name=${DOCKER_NAME:-"ilp32-${image_type}"}
	local docker_tag=${DOCKER_TAG:-"${docker_name}:${version}"}
	local docker_file=${DOCKER_FILE:-"${docker_top}/Dockerfile.${docker_name}"}

	if docker inspect --type image ${docker_tag} &>/dev/null; then
		if [[ ! ${force} ]]; then
			echo "${name}: ERROR: Docker image exists: ${docker_tag}" >&2
			exit 1
		fi

		echo "${name}: INFO: Removing existing docker image: ${docker_tag}" >&2
		docker rmi --force ${docker_tag}
	fi

	if [[ ${image_type} != "toolup" ]]; then
		local extra="--build-arg TOOLCHAIN_PREFIX=${prefix}"
	fi

	mkdir -p ${destdir}
	pushd ${destdir}
	docker build \
		${extra} \
		--build-arg DOCKER_FROM=${DOCKER_FROM} \
		--file ${docker_file} \
		--tag ${docker_tag} \
		--network=host \
		.

	popd
}

test_for_image() {
	local image_type=${1}

	local version=${VERSION:-"1"}
	local docker_name=${DOCKER_NAME:-"ilp32-${image_type}"}
	local docker_tag=${DOCKER_TAG:-"${docker_name}:${version}"}

	if docker inspect --type image ${docker_tag} &>/dev/null; then
		echo "${name}: INFO: Docker image exists: ${docker_tag}" >&2
		return 0
	fi
	return 1
}

test_for_toolchain() {
	if ! test -x "$(command -v ${toolchain_destdir}${toolchain_install_dir}/bin/${target_triple}-gcc)"; then
		echo "${name}: ERROR: No toolchain found: '${toolchain_destdir}${toolchain_install_dir}'" >&2
		return 1
	fi
	return 0
}

build_toolup() {
	if [[ ${force} ]] || ! test_for_image toolup; then
		tmp_dir="$(mktemp --tmpdir --directory ${name}.XXXX)"
		build_image toolup ${tmp_dir}
	fi
}

build_toolchain() {
	# FIXME: for debug
	if [[ -d ${DEBUG_TOOLCHAIN_SRC} ]]; then
		rm -rf ${build_top}/src
		mkdir -p ${build_top}
		cp -a --link ${DEBUG_TOOLCHAIN_SRC} ${build_top}/src
	fi
	# FIXME: for debug
	if [[ -d ${DEBUG_TOOLCHAIN_DESTDIR} ]]; then
		mkdir -p ${build_top}
		rsync -a --delete ${DEBUG_TOOLCHAIN_DESTDIR}/ ${toolchain_destdir}/
	fi

	mkdir -p ${toolchain_destdir}${toolchain_install_dir}

	${SCRIPTS_TOP}/enter-toolup.sh \
		--verbose \
		--container-name=build-toolchain--$(date +%H-%M-%S) \
		--docker-args="-v "$(to_host ${toolchain_destdir}${toolchain_install_dir})":${toolchain_install_dir}" \
		-- ${toolup_scripts_top}/build-toolchain.sh \
			--build-top=${toolup_build_top} \
			--install-dir=${toolchain_install_dir} \
			-12345678
}

build_builder() {
	if [[ ${force} ]] || ! test_for_image builder; then
		if test_for_toolchain; then
			build_image builder ${toolchain_destdir} ${toolchain_install_dir}
		fi
	fi
}

build_runner() {
	if [[ ${host_arch} != ${target_arch} ]]; then
		echo "${name}: ERROR: ilp32-runner must be built on '${target_arch}'" >&2
		exit 1
	fi

	if [[ ${force} ]] || ! test_for_image runner; then
		if test_for_toolchain; then
			build_image runner ${toolchain_destdir} ${toolchain_install_dir}
		fi
	fi
}

#===============================================================================
# program start
#===============================================================================
export PS4='\[\033[0;33m\]+${BASH_SOURCE##*/}:${LINENO}: \[\033[0;37m\]'
set -x

name="${0##*/}"
build_time="$(date +%Y.%m.%d-%H.%M.%S)"

current_step="setup"
trap "on_exit 'Failed.'" EXIT
set -e

SECONDS=0

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
source ${SCRIPTS_TOP}/lib/util.sh

process_opts "${@}"

export HOST_WORK_DIR=${HOST_WORK_DIR:-"$(pwd)"}
export CURRENT_WORK_DIR=${CURRENT_WORK_DIR:-"${HOST_WORK_DIR}"}

build_top="$(realpath -m ${build_top:-"${HOST_WORK_DIR}/build-${build_time}"})"
toolchain_destdir="$(realpath -m ${toolchain_destdir:-"${build_top}/destdir"})"

toolchain_install_dir=${toolchain_install_dir:-"/opt/ilp32"}

docker_top=${docker_top:-"$(cd "${SCRIPTS_TOP}/../docker" && pwd)"}

toolup_work_dir="$(${SCRIPTS_TOP}/enter-toolup.sh --print-work-dir)"

toolup_scripts_top="${toolup_work_dir}$(strip_current ${SCRIPTS_TOP})"
toolup_build_top="${toolup_work_dir}$(strip_current ${build_top})"
#toolup_sysroot="${toolup_work_dir}$(to_host ${sysroot})"

host_arch="$(uname -m)"
target_arch="aarch64"
target_triple="aarch64-linux-gnu"

if [[ -n "${usage}" ]]; then
	usage
	trap - EXIT
	exit 0
fi

case ${host_arch} in
arm64|aarch64)
	DOCKER_FROM=${DOCKER_FROM:-"arm64v8/debian:buster"}
	;;
amd64|x86_64)
	DOCKER_FROM=${DOCKER_FROM:-"debian:buster"}
	;;
*)
	echo "${name}: ERROR: Bad arch '${a}'" >&2
	exit 1
	;;
esac

while true; do
	if [[ ${step_toolup} ]]; then
		current_step="step_toolup"
		build_toolup
		unset step_toolup
	elif [[ ${step_toolchain} ]]; then
		current_step="step_toolchain"
		build_toolchain
		unset step_toolchain
	elif [[ ${step_builder} ]]; then
		current_step="step_builder"
		build_builder
		unset step_builder
	elif [[ ${step_runner} ]]; then
		current_step="step_runner"
		build_runner
		unset step_runner
	else
		current_step="done"
		break
	fi
done

trap "on_exit 'Success.'" EXIT
exit 0
