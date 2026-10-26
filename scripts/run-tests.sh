#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 tzzs
#
# One entry point for every host-runnable test suite.
#
#   bash scripts/run-tests.sh [--verbose]
#
# Suites are discovered by convention, never from a list that can go stale:
#
#   tests/<suite>/run.uc     host ucode interpreter
#   tests/<suite>/*.mjs      node
#   tests/<suite>/**/*.sh    bash
#
# Anything else under tests/ is a fixture or a helper and is not run. Pass/fail
# is judged by exit status only, so a suite may print TAP or its own summary.
# A failing suite does not stop the run: one break must not hide the rest.
#
# The ucode interpreter is resolved from $UCODE, then
# ~/.local/opt/ucode-host/bin/ucode, then `ucode` on PATH. When none is found
# the run stops with instructions instead of quietly skipping the ucode suites:
# skipping them is how the trailing-newline validation bug survived.
#
# Exit status: 0 when every suite passed, 1 when any suite failed, 2 when the
# run itself is broken (no suites found, no interpreter, bad argument).
#
# Host only: this script uses bash. The router never runs it.

set -u
set -o pipefail

usage() {
	cat <<'EOF'
usage: bash scripts/run-tests.sh [--verbose]

Runs every host test suite under tests/ and prints one PASS/FAIL line per
suite, followed by a "N passed, M failed" summary.

  --verbose, -v   stream each suite's full output instead of only a tail on
                  failure
  --help, -h      show this message
EOF
}

verbose=0
while [ $# -gt 0 ]; do
	case "$1" in
		--verbose|-v)
			verbose=1
			;;
		--help|-h)
			usage
			exit 0
			;;
		*)
			printf 'run-tests: unknown argument: %s\n\n' "$1" >&2
			usage >&2
			exit 2
			;;
	esac
	shift
done

# Resolve the repository root from this script's location, so the runner works
# from any working directory.
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) || exit 2
root=$(CDPATH='' cd -- "${here}/.." && pwd) || exit 2
tests_dir="${root}/tests"

if [ ! -d "${tests_dir}" ]; then
	printf 'run-tests: %s does not exist; is this a checkout of the repository?\n' \
		"${tests_dir}" >&2
	exit 2
fi

# --- ucode interpreter ------------------------------------------------------

no_ucode() {
	cat >&2 <<'EOF'
run-tests: no ucode interpreter found.

The ucode suites are not optional. Without a real interpreter they cannot run,
and silently skipping them is how the trailing-newline validation bug survived.
Build the same host interpreter CI uses (pinned upstream commit, not a tag: the
last release tag predates syntax the suites and shipped modules rely on), or
point the runner at one you already have:

  # build it once, into the layout the runner looks for
  ref=aabdeb4f5060c91c5929bf6d7af745c6aabf5ec5
  curl -fsSL "https://github.com/jow-/ucode/archive/${ref}.tar.gz" | tar -xz
  cd "ucode-${ref}"
  cmake -B build -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$HOME/.local/opt/ucode-host" \
    -DCMAKE_INSTALL_LIBDIR=lib
  cmake --build build --parallel
  cmake --install build

  # or reuse an existing binary
  UCODE=/path/to/ucode bash scripts/run-tests.sh

Lookup order: $UCODE, $HOME/.local/opt/ucode-host/bin/ucode, `ucode` on PATH.
EOF
	exit 2
}

resolve_ucode() {
	if [ -n "${UCODE:-}" ]; then
		case "${UCODE}" in
			*/*)
				printf '%s\n' "${UCODE}"
				return 0
				;;
			*)
				command -v "${UCODE}" 2>/dev/null && return 0
				return 1
				;;
		esac
	fi
	if [ -x "${HOME:-}/.local/opt/ucode-host/bin/ucode" ]; then
		printf '%s\n' "${HOME}/.local/opt/ucode-host/bin/ucode"
		return 0
	fi
	command -v ucode 2>/dev/null
}

ucode_path=$(resolve_ucode) || no_ucode
[ -n "${ucode_path}" ] || no_ucode

if [ ! -x "${ucode_path}" ]; then
	printf 'run-tests: %s is not an executable ucode interpreter.\n' \
		"${ucode_path}" >&2
	printf 'Fix or unset the UCODE variable, or install one as described below.\n\n' >&2
	no_ucode
fi

ucode_dir=$(CDPATH='' cd -- "$(dirname -- "${ucode_path}")" 2>/dev/null && pwd) ||
	ucode_dir=$(dirname -- "${ucode_path}")
ucode_lib="${ucode_dir}/../lib/ucode"
have_ucode_lib=0
if [ -d "${ucode_lib}" ]; then
	ucode_lib=$(CDPATH='' cd -- "${ucode_lib}" && pwd)
	have_ucode_lib=1
fi

# The node and shell suites resolve ucode on their own, so hand them the build
# this run selected instead of letting them guess a different one.
export UCODE="${ucode_path}"
if [ "${have_ucode_lib}" -eq 1 ]; then
	export UCODE_LIB="${ucode_lib}"
else
	unset UCODE_LIB 2>/dev/null || true
fi

# --- discovery --------------------------------------------------------------

workdir=$(mktemp -d "${TMPDIR:-/tmp}/airconnect-tests.XXXXXX") || exit 2
trap 'rm -rf "${workdir}"' EXIT INT TERM

{
	find "${tests_dir}" -mindepth 2 -maxdepth 2 -type f -name 'run.uc' -print
	find "${tests_dir}" -mindepth 2 -maxdepth 2 -type f -name '*.mjs' -print
	find "${tests_dir}" -mindepth 2 -type f -name '*.sh' -print
} | LC_ALL=C sort > "${workdir}/suites"

suites=()
while IFS= read -r suite; do
	suites+=("${suite}")
done < "${workdir}/suites"

if [ "${#suites[@]}" -eq 0 ]; then
	printf 'run-tests: found no suites under %s.\n' "${tests_dir}" >&2
	printf 'Expected tests/<suite>/run.uc, tests/<suite>/*.mjs or tests/<suite>/**/*.sh.\n' >&2
	exit 2
fi

# --- timing -----------------------------------------------------------------

# Whole milliseconds. `date +%s%N` is GNU and newer BSD date; older BSD date
# prints a literal N, which the numeric check catches.
now_ms() {
	local stamp
	stamp=$(date +%s%N 2>/dev/null)
	case "${stamp}" in
		''|*[!0-9]*)
			printf '%s000\n' "$(date +%s)"
			;;
		*)
			printf '%s\n' "$(( stamp / 1000000 ))"
			;;
	esac
}

format_duration() {
	printf '%d.%02ds' "$(( $1 / 1000 ))" "$(( ($1 % 1000) / 10 ))"
}

# --- run --------------------------------------------------------------------

cd "${root}" || exit 2

printf 'ucode: %s' "${ucode_path}"
if [ "${have_ucode_lib}" -eq 1 ]; then
	printf ' (-L %s)' "${ucode_lib}"
else
	printf ' (no module directory alongside it)'
fi
printf '\n\n'

passed=0
failed=0
index=0

for suite in "${suites[@]}"; do
	index=$((index + 1))
	label=${suite#"${root}/"}
	log="${workdir}/${index}.log"

	cmd=()
	case "${suite}" in
		*.mjs)
			cmd=(node "${suite}")
			;;
		*.sh)
			cmd=(bash "${suite}")
			;;
		*.uc)
			cmd=("${ucode_path}")
			if [ "${have_ucode_lib}" -eq 1 ]; then
				cmd+=(-L "${ucode_lib}")
			fi
			cmd+=("${suite}")
			;;
		*)
			# Unreachable: the discovery patterns above only yield these.
			printf 'SKIP  %s (unknown suite type)\n' "${label}"
			continue
			;;
	esac

	started=$(now_ms)
	status=0
	if [ "${verbose}" -eq 1 ]; then
		"${cmd[@]}" 2>&1 | tee "${log}"
		status=${PIPESTATUS[0]}
	else
		"${cmd[@]}" > "${log}" 2>&1
		status=$?
	fi
	elapsed=$(( $(now_ms) - started ))

	if [ "${status}" -eq 0 ]; then
		passed=$((passed + 1))
		printf 'PASS  %s (%s)\n' "${label}" "$(format_duration "${elapsed}")"
		continue
	fi

	failed=$((failed + 1))
	printf 'FAIL  %s (%s, exit %d)\n' \
		"${label}" "$(format_duration "${elapsed}")" "${status}"
	printf '      command:'
	printf ' %q' "${cmd[@]}"
	printf '\n'
	if [ "${verbose}" -eq 0 ]; then
		if [ -s "${log}" ]; then
			tail -n 20 "${log}" | sed 's/^/      | /'
		else
			printf '      | (no output)\n'
		fi
	fi
done

printf '\n%d passed, %d failed\n' "${passed}" "${failed}"

if [ "${failed}" -ne 0 ]; then
	exit 1
fi
exit 0
