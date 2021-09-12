#!/bin/bash

to_minutes() {
	local sec=${1}
	local min=$((sec / 60))
	local frac=$(((sec - min * 60) * 100 / 60))
	
	echo "${min}.${frac}"
}

on_exit() {
	local result=${1}
	local end_time=${SECONDS}

	set +x
	if [[ ${step} ]]; then
		echo "${script_name}: step = ${step}" >&2
	fi
	echo "${script_name}: Done: ${result}: ${end_time} sec ($(to_minutes ${end_time})) min)" >&2
}

#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}):\[\e[0m\] '
set -x

trap "on_exit 'failed.'" EXIT
set -e

script_name="${0##*/}"
build_time="$(date +%Y.%m.%d-%H.%M.%S)"

SECONDS=0
SCRIPTS_TOP="${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}"

fist_step=${1:-2}

step_names=("" git-clone binutils gcc-bootstrap headers glibc-lp64 glibc-ilp32 gcc-final)

for ((step = fist_step; step <= 7; step++)); do
	name="${step_names[${step}]}"
	echo "${script_name}: step = (${step}) '${name}'"
	${SCRIPTS_TOP}/build-ilp32-toolchain.sh -${step}
	tar -czf "arc-${build_time}--${step}-${name}.tar.gz" destdir
done

unset step
trap "on_exit 'Success.'" EXIT
exit 0

