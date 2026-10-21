#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 tzzs
#
# Verify that the two extracted AirConnect engines are non-empty ELF binaries.
#
# This lives in a script rather than in a Makefile recipe on purpose: the
# OpenWrt build system expands Build/Compile through several nested macros, and
# a shell body containing $f / $FILE_BIN is re-expanded as make variables on the
# way through ("empty: " instead of "empty: /path/file"). Keeping the loop in a
# real script removes that class of failure entirely and makes the check
# testable on the host.
#
# Usage: verify-engines.sh <file> [<file> ...]
#
# Exits 0 when every argument is a non-empty ELF file, and non-zero naming the
# first offending path and what was detected.

set -u

if [ "$#" -eq 0 ]; then
	printf 'verify-engines: usage: verify-engines.sh <file> [<file> ...]\n' >&2
	exit 2
fi

# Prefer the file(1) database when present; the magic byte check is the
# fallback for minimal SDK containers that do not ship it.
FILE_BIN=''
if command -v file >/dev/null 2>&1; then
	FILE_BIN=file
fi

status=0
for target in "$@"; do
	if [ ! -f "$target" ]; then
		printf 'verify-engines: missing: %s\n' "$target" >&2
		status=1
		continue
	fi
	if [ ! -s "$target" ]; then
		printf 'verify-engines: empty: %s\n' "$target" >&2
		status=1
		continue
	fi

	if [ -n "$FILE_BIN" ]; then
		description=$("$FILE_BIN" "$target" 2>/dev/null)
		case "$description" in
			*ELF*) continue ;;
			*)
				printf 'verify-engines: not an ELF binary: %s (%s)\n' \
					"$target" "${description:-no output}" >&2
				status=1
				;;
		esac
	else
		header=$(od -An -tx1 -N4 "$target" 2>/dev/null)
		case "$header" in
			*'7f 45 4c 46'*) continue ;;
			*)
				printf 'verify-engines: not an ELF binary: %s (header:%s)\n' \
					"$target" "${header:-unreadable}" >&2
				status=1
				;;
		esac
	fi
done

exit "$status"
