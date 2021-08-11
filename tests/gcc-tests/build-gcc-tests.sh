#!/usr/bin/env bash

script_name="${0##*/}"
progs="pr82274-1 pr82274-2"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
LIB_TOP=${LIB_TOP:-"$(cd "${SCRIPTS_TOP}/../lib" && pwd)"}

gcc_opts_extra=" -ftrapv"

source "${LIB_TOP}/build-common.sh"
