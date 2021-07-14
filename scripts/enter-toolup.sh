#!/usr/bin/env bash

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Enter ilp32 Docker image." >&2
	echo "Usage: ${name} [flags] -- [command]" >&2
	echo "Option flags:" >&2
	echo "  -a --docker-args    - Args for docker run. Default: '${docker_args}'" >&2
	echo "  -h --help           - Show this help and exit." >&2
	echo "  -n --container-name - Container name. Default: '${container_name}'." >&2
	echo "  -r --as-root        - Run as root user." >&2
	echo "  -t --tag            - Print Docker tag to stdout and exit." >&2
	echo "  -v --verbose        - Verbose execution." >&2
	echo "  -w --print-work-dir - Print container work directory ILP32_WORK_DIR to stdout and exit." >&2
	echo "Args:" >&2
	echo "  command             - Default: '${user_cmd}'" >&2
	echo "Environment:" >&2
	echo "  HOST_WORK_DIR       - Default: '${HOST_WORK_DIR}'" >&2
	echo "  ILP32_WORK_DIR      - Default: '${ILP32_WORK_DIR}'" >&2
	echo "  DOCKER_TAG          - Default: '${DOCKER_TAG}'" >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="a:hn:rtvw"
	local long_opts="docker-args:,help,container-name:,as-root,tag,verbose,print-work-dir"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		#echo "${FUNCNAME[0]}: @${1}@ @${2}@"
		case "${1}" in
		-a | --docker-args)
			docker_args="${2}"
			shift 2
			;;
		-h | --help)
			usage=1
			shift
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
		-v | --verbose)
			set -x
			verbose=1
			shift
			;;
		-w | --print-work-dir)
			print_work_dir=1
			shift
			;;
		--)
			shift
			user_cmd="${@}"
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

#===============================================================================
# program start
#===============================================================================
export PS4='\[\033[0;33m\]+${BASH_SOURCE##*/}:${LINENO}: \[\033[0;37m\]'

name="${0##*/}"

image_type=${name%%.*}
image_type=${image_type##*-}

trap "on_exit 'failed.'" EXIT
set -e

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
source ${SCRIPTS_TOP}/lib/util.sh

host_arch=$(get_arch "$(uname -m)")
target_arch=$(get_arch "arm64")
target_triple="aarch64-linux-gnu"

process_opts "${@}"

VERSION=${VERSION:-"1"}
DOCKER_NAME=${DOCKER_NAME:-"ilp32-${image_type}"}
DOCKER_TAG=${DOCKER_TAG:-"${DOCKER_NAME}:${VERSION}-${host_arch}"}

HOST_WORK_DIR=${HOST_WORK_DIR:-"$(pwd)"}
ILP32_WORK_DIR=${ILP32_WORK_DIR:-"/ilp32"}

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

if [[ ${print_work_dir} ]]; then
	echo "${ILP32_WORK_DIR}"
	trap - EXIT
	exit 0
fi

if [ ${ILP32_BUILDER} ]; then
	echo "${name}: ERROR: Already in ilp32-builder container." >&2
	echo "${name}: INFO: Try running: '${user_cmd}'." >&2
	exit 1
fi

if [[ ! ${as_root} ]]; then
	USER_ARGS=${USER_ARGS:-"-u $(id -u):$(id -g) \
		-v /etc/group:/etc/group:ro \
		-v /etc/passwd:/etc/passwd:ro \
	"}
fi

HISTFILE=${HISTFILE:-"${ILP32_WORK_DIR}/${container_name}--bash_history"}

docker run --rm   \
	${USER_ARGS} \
	-e HOST_WORK_DIR=${HOST_WORK_DIR} \
	-e CURRENT_WORK_DIR=${ILP32_WORK_DIR} \
	-v ${HOST_WORK_DIR}:${ILP32_WORK_DIR}:rw \
	-w ${ILP32_WORK_DIR} \
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
