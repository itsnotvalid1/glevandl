#!/usr/bin/env bash

script_name="${0##*/}"
progs="vdso-basic-test"

SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
LIB_TOP=${LIB_TOP:-"$(cd "${SCRIPTS_TOP}/../lib" && pwd)"}

source "${LIB_TOP}/build-common.sh"
