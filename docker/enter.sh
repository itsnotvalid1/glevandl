#!/usr/bin/env bash

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Enter ilp32-builder Docker image." >&2
	echo "Usage: ${name} [flags] -- [command]" >&2
	echo "Option flags:" >&2
	echo "  -a --docker-args    - Args for docker run. Default: '${docker_args}'" >&2
	echo "  -h --help           - Show this help and exit." >&2
	echo "  -n --container-name - Container name. Default: '${container_name}'." >&2
	echo "  -r --as-root        - Run as root user." >&2
	echo "  -t --tag            - Print Docker tag to stdout and exit." >&2
	echo "  -v --verbose        - Verbose execution." >&2
	echo "Args:" >&2
	echo "  command             - Default: '${user_cmd}'" >&2
	echo "Environment:" >&2
	echo "  DOCKER_TAG          - Default: '${DOCKER_TAG}'" >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="a:hn:rtv"
	local long_opts="docker-args:,help,container-name:,as-root,tag,verbose"

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
trap "on_exit 'failed.'" EXIT
set -e

process_opts "${@}"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
PROJECT_TOP=${PROJECT_TOP:-"$(cd "${SCRIPTS_TOP}/../../.." && pwd)"}

VERSION=${VERSION:-"1"}
DOCKER_NAME=${DOCKER_NAME:-"ilp32-builder"}
DOCKER_TAG=${DOCKER_TAG:-"${DOCKER_NAME}:${VERSION}"}

work_dir=${work_dir:-"/ilp32"}

container_name=${container_name:-${DOCKER_NAME}}
user_cmd=${user_cmd:-"/bin/bash"}

HISTFILE=${HISTFILE:-"${work_dir}/${container_name}--bash_history"}
DOCKER_EXTRA_ARGS=${DOCKER_EXTRA_ARGS:-""}

if [[ -n "${usage}" ]]; then
	usage
	trap - EXIT
	exit 0
fi

if [[ ${tag} ]]; then
	show_tag
	trap - EXIT
	exit 0
fi

if [ ${ILP32_BUILDER} ]; then
	echo "${name}: ERROR: Already in ilp32-builder container." >&2
	exit 1
fi

if [[ ! ${as_root} ]]; then
	USER_ARGS=${USER_ARGS:-"-u $(id -u):$(id -g) \
		-v /etc/group:/etc/group:ro \
		-v /etc/passwd:/etc/passwd:ro \
	"}
fi

set +e

docker run -it --rm   \
	${USER_ARGS} \
	-v ${PROJECT_TOP}:${work_dir}:rw \
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
