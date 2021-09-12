#!/usr/bin/env bash

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Build ilp32-toolup, ilp32-builder and ilp32-runner container images." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help           - Show this help and exit." >&2
	echo "  -f --force          - Removing existing docker image and rebuild." >&2
	echo "  -t --toolup         - Build ilp32-toolup container image." >&2
	echo "  -c --toolchain      - Build ilp32 toolchain." >&2
	echo "  -b --builder        - Build ilp32-builder container image." >&2
	echo "  -r --runner         - Build ilp32-runner container image." >&2
	echo "  --build-top         - Top build directory. Default: '${build_top}'." >&2
	echo "  --toolchain-destdir - Top toolchain directory. Default: '${toolchain_destdir}'." >&2
	echo "  --toolchain-prefix  - Top toolchain directory. Default: '${toolchain_prefix}'." >&2
	echo "Environment:" >&2
	echo "  DEBUG_TOOLCHAIN_SRC - Default: '${DEBUG_TOOLCHAIN_SRC}'." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hftcbr"
	local long_opts="help,force,toolup,toolchain,builder,runner,\
build-top:,--toolchain-destdir:,--toolchain-prefix:"

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
		--toolchain-prefix)
			toolchain_prefix="${2}"
			shift 2
			;;
		--)
			shift
			if [[ ${1} ]]; then
				echo "${script_name}: ERROR: Got extra opts: '${@}'" >&2
				exit 1
			fi
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

	if [ -d ${tmp_dir} ]; then
		rm -rf ${tmp_dir}
	fi

	local end_time=${SECONDS}

	set +x
	if [[ ${current_step} != "done" ]]; then
		echo "${script_name}: ERROR: Step '${current_step}' failed." >&2
	fi
	echo "${script_name}: Done: ${result} ${end_time} sec ($(sec_to_min ${end_time}) min)" >&2
}

docker_from() {
	local image_type=${1}

	local from_amd64_toolup="debian:buster"
	local from_amd64_builder="debian:buster"
	local from_amd64_runner="alpine:latest"

	local from_arm64_toolup="arm64v8/debian:buster"
	local from_arm64_builder="arm64v8/debian:buster"
	local from_arm64_runner="arm64v8/alpine:latest"

	local from="from_${host_arch}_${image_type}"
	echo "${!from}"
}

build_image() {
	local image_type=${1}
	local destdir=${2}
	local prefix=${3}

	local version=${VERSION:-${default_image_version}}
	local docker_name=${DOCKER_NAME:-"ilp32-${image_type}"}
	local docker_tag=${DOCKER_TAG:-"${docker_name}:${version}-${host_arch}"}
	local docker_file=${DOCKER_FILE:-"${docker_top}/Dockerfile.${docker_name}"}

	if docker inspect --type image ${docker_tag} &>/dev/null; then
		if [[ ! ${force} ]]; then
			echo "${script_name}: ERROR: Docker image exists: ${docker_tag}" >&2
			exit 1
		fi

		echo "${script_name}: INFO: Removing existing docker image: ${docker_tag}" >&2
		docker rmi --force ${docker_tag}
	fi

	case ${image_type} in
	runner|builder)
		local docker_extra="--build-arg TOOLCHAIN_PREFIX=${prefix}"
		;;
	esac

	mkdir -p ${destdir}
	pushd ${destdir}

	docker build \
		${docker_extra} \
		--build-arg DOCKER_FROM=$(docker_from ${image_type}) \
		--file ${docker_file} \
		--tag ${docker_tag} \
		--network=host \
		.

	popd
}

test_for_image() {
	local image_type=${1}

	local version=${VERSION:-${default_image_version}}
	local docker_name=${DOCKER_NAME:-"ilp32-${image_type}"}
	local docker_tag=${DOCKER_TAG:-"${docker_name}:${version}-${host_arch}"}

	if docker inspect --type image ${docker_tag} &>/dev/null; then
		echo "${script_name}: INFO: Docker image exists: ${docker_tag}" >&2
		return 0
	fi
	return 1
}

test_for_toolchain() {
	if test -x "$(command -v ${toolchain_dest_pre}/bin/${target_triple}-gcc)"; then
		return 0
	fi
	echo "${script_name}: INFO: No toolchain found: '${toolchain_dest_pre}'" >&2
	return 1
}

build_toolup() {
	if [[ ${force} ]] || ! test_for_image toolup; then
		tmp_dir="$(mktemp --tmpdir --directory ${script_name}.XXXX)"
		build_image toolup ${tmp_dir}
	fi
}

build_toolchain() {
	mkdir -p ${toolchain_dest_pre}

	local common_parent

	if [[ ${DEBUG_TOOLCHAIN_SRC} && -d "${DEBUG_TOOLCHAIN_SRC}" ]]; then
		common_parent="$(find_common_parent "${build_top}" "${DEBUG_TOOLCHAIN_SRC}")"
	fi

	${SCRIPTS_TOP}/enter-ilp32-toolup.sh \
		--verbose \
		--container-name=build-toolchain--$(date +%H-%M-%S) \
		--work-dir=${build_top} \
		--docker-args="\
			-v ${PROJECT_TOP}:${PROJECT_TOP}:ro \
			-v ${toolchain_dest_pre}:${toolchain_prefix} \
			${common_parent:+-v ${common_parent}:${common_parent}} \
			-e DEBUG_TOOLCHAIN_SRC" \
		-- ${PROJECT_TOP}/scripts/build-ilp32-toolchain.sh \
			--build-top=${build_top} \
			--destdir="/" \
			--prefix=${toolchain_prefix} \
			-12345678
}

build_builder() {
	local image_type=builder

	if [[ ${force} ]] || ! test_for_image ${image_type}; then
		if [[ ${force} ]] || ! test_for_toolchain; then
			echo "${script_name}: INFO: Building toolchain..." >&2
			build_toolchain
		fi
		echo "${script_name}: INFO: Using existing toolchain." >&2
		build_image ${image_type} ${toolchain_destdir} ${toolchain_prefix}
	fi
}

build_runner() {
	local image_type=runner

	if [[ ${force} ]] || ! test_for_image ${image_type}; then
		if ! test_for_toolchain; then
			echo "${script_name}: INFO: Building toolchain..." >&2
			build_toolchain
		fi
		echo "${script_name}: INFO: Using existing toolchain." >&2
		build_image ${image_type} ${toolchain_destdir} ${toolchain_prefix}
	fi
}

#===============================================================================
# program start
#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}):\[\e[0m\] '
set -x

script_name="${0##*/}"
build_time="$(date +%Y.%m.%d-%H.%M.%S)"

current_step="setup"
trap "on_exit 'Failed.'" EXIT
set -e

SECONDS=0

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
source ${SCRIPTS_TOP}/lib/util.sh

PROJECT_TOP=${PROJECT_TOP:-"$(cd "${SCRIPTS_TOP}/.." && pwd)"}
docker_top=${docker_top:-"${PROJECT_TOP}/docker"}

host_arch=$(get_arch $(uname -m))
target_arch=$(get_arch "arm64")
target_triple="aarch64-linux-gnu"
default_image_version="2"

build_top="$(realpath -m ${build_top:-"$(pwd)/build-${build_time}"})"

process_opts "${@}"

toolchain_destdir="$(realpath -m ${toolchain_destdir:-"${build_top}/destdir"})"
toolchain_prefix=${toolchain_prefix:-"/opt/ilp32"}
toolchain_dest_pre="${toolchain_destdir}${toolchain_prefix}"

if [[ -n "${usage}" ]]; then
	usage
	trap - EXIT
	exit 0
fi

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
