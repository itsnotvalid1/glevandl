#!/usr/bin/env bash

usage () {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Build ilp32-builder Docker image." >&2
	echo "Usage: ${name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -h --help   - Show this help and exit." >&2
	echo "  -f --force  - Removing existing docker image and rebuild." >&2
	echo "Environment:" >&2
	echo "  DOCKER_TAG  - Default: '${DOCKER_TAG}'" >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hf"
	local long_opts="help,force"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		echo "${FUNCNAME[0]}: @${1}@ @${2}@"
		case "${1}" in
		-h | --help)
			usage=1
			shift
			;;
		-f | --force)
			force=1
			shift
			;;
		--)
			shift
			user_cmd="${@}"
			if [[ ${user_cmd} ]]; then
				echo "${name}: ERROR: Extra opts: '${user_cmd}'" >&2
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
	echo "${name}: Done: ${result}: ${end_time} sec" >&2
}

#===============================================================================
# program start
#===============================================================================
export PS4='\[\033[0;33m\]+${BASH_SOURCE##*/}:${LINENO}: \[\033[0;37m\]'
set -x

name="${0##*/}"
trap "on_exit 'failed.'" EXIT
set -e

SECONDS=0

SCRIPT_TOP=${SCRIPT_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
PROJECT_TOP=${PROJECT_TOP:-"$(cd "${SCRIPT_TOP}/.." && pwd)"}

process_opts "${@}"

VERSION=${VERSION:-"1"}
DOCKER_NAME=${DOCKER_NAME:-"ilp32-builder"}
DOCKER_TAG=${DOCKER_TAG:-"${DOCKER_NAME}:${VERSION}"}

DOCKER_FILE=${DOCKER_FILE:-"${SCRIPT_TOP}/Dockerfile.${DOCKER_NAME}"}
DOCKER_BUILD_ARGS=${DOCKER_BUILD_ARGS:-""}

if [[ -n "${usage}" ]]; then
	usage
	trap - EXIT
	exit 0
fi

case "$(uname -m)" in
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

if docker inspect --type image ${DOCKER_TAG} &>/dev/null; then
	if [[ ! ${force} ]]; then
		echo "Docker image exists: ${DOCKER_TAG}" >&2
		trap "on_exit 'Success.'" EXIT
		exit 0
	fi
	
	echo "Removing existing docker image: ${DOCKER_TAG}" >&2
	docker rmi --force ${DOCKER_TAG}
fi

tmp_dir="$(mktemp --tmpdir --directory ${name}.XXXX)"

cd "${tmp_dir}"

docker build \
	--build-arg DOCKER_FROM=${DOCKER_FROM} \
	--file ${DOCKER_FILE} \
	--tag ${DOCKER_TAG} \
	--network=host \
	${DOCKER_BUILD_ARGS} \
	.

trap "on_exit 'Success.'" EXIT
exit 0
