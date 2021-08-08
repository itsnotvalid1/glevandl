#!/usr/bin/env bash

script_name="${0##*/}"
progs="pr82274-1 pr82274-2"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${0%/*}" && pwd)"}
LIB_TOP=${LIB_TOP:-"$(cd "${SCRIPTS_TOP}/../lib" && pwd)"}

source "${LIB_TOP}/build-common.sh"
