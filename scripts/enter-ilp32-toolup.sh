#!/usr/bin/env bash

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Enter ilp32 Docker image." >&2
	echo "Usage: ${script_name} [flags] -- [command]" >&2
	echo "Option flags:" >&2
	echo "  -h --help           - Show this help and exit." >&2
	echo "  -v --verbose        - Verbose execution." >&2
	echo "  -a --docker-args    - Args for docker run. Default: '${docker_args}'" >&2
	echo "  -n --container-name - Container name. Default: '${container_name}'." >&2
	echo "  -r --as-root        - Run as root user." >&2
	echo "  -t --tag            - Print Docker tag to stdout and exit." >&2
	echo "  --work-dir          - Work directory. Default: '${work_dir}'." >&2
	echo "Args:" >&2
	echo "  command             - Default: '${user_cmd}'" >&2
	echo "Environment:" >&2
	echo "  DOCKER_TAG          - Default: '${DOCKER_TAG}'" >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hva:n:rt"
local long_opts="help,verbose,\
docker-args:,container-name:,as-root,tag,work-dir:"

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
		-v | --verbose)
			set -x
			verbose=1
			shift
			;;
		-a | --docker-args)
			docker_args="${2}"
			shift 2
			;;
		-n | --container-name)
			container_name="${2}"
			shift 2
			;;
		-r | --as-root)
			as_root=1
			shift
			;;
		-t | --tag)
			tag=1
			shift
			;;
		--work-dir)
			work_dir="${2}"
			shift 2
			;;
		--)
			shift
			user_cmd="${@}"
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
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}):\[\e[0m\] '

script_name="${0##*/}"

image_type=${script_name%%.*}
image_type=${image_type##*-}

trap "on_exit 'failed.'" EXIT
set -e

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
source ${SCRIPTS_TOP}/lib/util.sh

PROJECT_TOP=${PROJECT_TOP:-"$(cd "${SCRIPTS_TOP}/.." && pwd)"}

host_arch=$(get_arch $(uname -m))
target_arch=$(get_arch "arm64")
target_triple="aarch64-linux-gnu"
default_image_version="2"

process_opts "${@}"

VERSION=${VERSION:-${default_image_version}}
DOCKER_NAME=${DOCKER_NAME:-"ilp32-${image_type}"}
DOCKER_TAG=${DOCKER_TAG:-"${DOCKER_NAME}:${VERSION}-${host_arch}"}

container_name=${container_name:-${DOCKER_NAME}}

if [[ ! ${user_cmd} ]]; then
	user_cmd="/bin/bash"
	DOCKER_EXTRA_ARGS+="-it"
fi

if [[ -n "${usage}" ]]; then
	usage
	trap - EXIT
	exit 0
fi

if [[ ${tag} ]]; then
	echo "${DOCKER_TAG}"
	trap - EXIT
	exit 0
fi

if [[ "${image_type}" == "toolup" && ${ILP32_TOOLUP} ]]; then
	echo "${script_name}: ERROR: Already in ilp32-toolup container." >&2
	echo "${script_name}: INFO: Try running: '${user_cmd}'." >&2
	exit 1
fi

if [[ "${image_type}" == "builder" && ${ILP32_BUILDER} ]]; then
	echo "${script_name}: ERROR: Already in ilp32-builder container." >&2
	echo "${script_name}: INFO: Try running: '${user_cmd}'." >&2
	exit 1
fi

if [[ "${image_type}" == "runner" && ${ILP32_RUNNER} ]]; then
	echo "${script_name}: ERROR: Already in ilp32-runner container." >&2
	echo "${script_name}: INFO: Try running: '${user_cmd}'." >&2
	exit 1
fi

check_opt 'work-dir' ${work_dir}

if [[ ! ${as_root} ]]; then
	USER_ARGS=${USER_ARGS:-"-u $(id -u):$(id -g) \
		-v /etc/group:/etc/group:ro \
		-v /etc/passwd:/etc/passwd:ro \
	"}
fi

container_id=$(get_container_id)

if [[ ${container_id} ]]; then
	DOCKER_VOLUMES+=" --volumes-from ${container_id}"
else
	DOCKER_VOLUMES+=" -v ${PROJECT_TOP}:${PROJECT_TOP}:ro"
fi

HISTFILE="${HISTFILE:-${work_dir}/${container_name}--bash_history}"

docker run --rm   \
	${DOCKER_VOLUMES} \
	${USER_ARGS} \
	-w ${work_dir} \
	-e HISTFILE=${HISTFILE} \
	--network host \
	--name ${container_name} \
	--hostname ${container_name} \
	--add-host ${container_name}:127.0.0.1 \
	${DOCKER_EXTRA_ARGS} \
	${docker_args} \
	${DOCKER_TAG} \
	${user_cmd}

trap "on_exit 'Success.'" EXIT
exit 0
