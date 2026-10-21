#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 tzzs
#
# Status and logs reply-size measurement for the rpcd backend.
#
#   bash tests/performance/measure-status.sh
#
# The plugin needs a sandbox root and fake `uci`/`ubus` modules, so this script
# creates both and runs measure-status.uc against them. The fakes are the ones
# tests/state/stubs.uc owns, shared with tests/state/plugin.uc: the measurement
# drives the same backend through the same stand-ins as the functional suite, so
# a reply size here is the size the state suite already proved correct.
#
# It also prints the environment the numbers were taken in, because a byte count
# without its ucode build is not reproducible.
#
# Exit status: 0 when every measured budget holds, 1 otherwise (including a
# failed assertion), 2 when the run itself is broken (no ucode interpreter).
#
# Host only: this script uses bash. The router never runs it.

set -u
set -o pipefail

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) || exit 2
root=$(CDPATH='' cd -- "${here}/../.." && pwd) || exit 2

UCODE="${UCODE:-${HOME}/.local/opt/ucode-host/bin/ucode}"
UCODE_LIB="${UCODE_LIB:-${HOME}/.local/opt/ucode-host/lib/ucode}"

if [ ! -x "${UCODE}" ]; then
	printf 'measure-status: ucode interpreter not found at %s\n' "${UCODE}" >&2
	printf 'Set UCODE=/path/to/ucode when it lives elsewhere.\n' >&2
	exit 2
fi

sandbox=$(mktemp -d "${TMPDIR:-/tmp}/airconnect-perf-status.XXXXXX") || exit 2
trap 'rm -rf "${sandbox}"' EXIT INT TERM

stubdir="${sandbox}/stubs"
rootdir="${sandbox}/root"
mkdir -p "${stubdir}" "${rootdir}"

printf 'ucode: %s\n' "$("${UCODE}" -e 'print("host ucode\n")' >/dev/null 2>&1 && printf '%s' "${UCODE}")"
printf 'uname: %s\n\n' "$(uname -srm)"

AIRCONNECT_MANAGER_ROOT="${rootdir}" \
AIRCONNECT_MANAGER_STUBS="${stubdir}" \
"${UCODE}" -L "${stubdir}" -L "${UCODE_LIB}" "${here}/measure-status.uc"
status=$?

if [ "${status}" -ne 0 ]; then
	printf '\nmeasure-status: FAILED (exit %d)\n' "${status}"
	exit 1
fi
exit 0
