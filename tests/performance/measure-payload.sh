#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 tzzs
#
# Static payload measurement for the LuCI package.
#
#   bash tests/performance/measure-payload.sh
#
# What is measured
# ----------------
# Everything the browser must fetch before the AirConnect page can render:
#
#   packages/luci-app-airconnect-manager/htdocs/luci-static/resources/**
#       installed as /www/luci-static/resources/** by feeds/luci/luci.mk
#   root/usr/share/luci/menu.d/*.json      the menu entry that resolves the view
#   root/usr/share/rpcd/acl.d/*.json       the ACL LuCI reads before calling rpcd
#
# Every file is counted twice: its bytes on disk, and its `gzip -9` size, because
# a real LuCI serves static resources compressed and the transfer cost is the
# compressed one. Sizes are read from disk, never estimated.
#
# What is NOT measured here
# -------------------------
# Request count, TCP/TLS overhead, cache headers, and the bytes LuCI core itself
# loads (luci.js, the form framework, the theme) are outside this package and
# outside this script. The numbers below are this package's contribution only.
#
# Budgets
# -------
# Every cap is derived from a measurement taken on 2026-10-22 in this repository
# (see docs/PERFORMANCE-RESULTS.zh-CN.md for the table and the command). The
# headroom is deliberate: a cap that trips on an ordinary edit teaches everyone
# to raise the cap instead of reading the number, so each cap allows roughly a
# doubling of what exists today while still catching an accidental dependency,
# a base64-encoded font, a committed source map or a copied-in framework.
#
#   measured total 47,775 bytes uncompressed -> cap 65,536 (64 KiB, +37 %)
#   measured total 14,646 bytes gzip -9      -> cap 32,768 (32 KiB, +124 %)
#
# Per-file caps, same rule (measured value in the comment):
#
#   view/airconnect-manager/overview.js  30,327 B -> 49,152 (48 KiB, +62 %)
#   airconnect-manager/manager.css        9,388 B -> 24,576 (24 KiB, +162 %)
#   airconnect-manager/rules.js           7,437 B -> 12,288 (12 KiB, +65 %)
#   menu.d / acl.d JSON                    265/358 B -> 2,048 (2 KiB)
#   any other file                                     32,768 (32 KiB)
#
# The default per-file cap exists so a new file is covered automatically instead
# of silently escaping the total: it may be added, it just may not be huge.
#
# Exit status: 0 when every budget holds, 1 when any budget is exceeded, 2 when
# the run itself is broken (missing package directory).
#
# Host only: this script uses bash. The router never runs it.

set -u
set -o pipefail
LC_ALL=C
export LC_ALL

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) || exit 2
root=$(CDPATH='' cd -- "${here}/../.." && pwd) || exit 2

pkg="${root}/packages/luci-app-airconnect-manager"
res="${pkg}/htdocs/luci-static/resources"

# --- budgets ----------------------------------------------------------------

TOTAL_CAP=65536
GZIP_TOTAL_CAP=32768
DEFAULT_FILE_CAP=32768

cap_for() {
	case "$1" in
		*/view/airconnect-manager/overview.js) printf '49152\n' ;;
		*/airconnect-manager/manager.css) printf '24576\n' ;;
		*/airconnect-manager/rules.js) printf '12288\n' ;;
		*/luci/menu.d/*.json) printf '2048\n' ;;
		*/rpcd/acl.d/*.json) printf '2048\n' ;;
		*) printf '%s\n' "${DEFAULT_FILE_CAP}" ;;
	esac
}

# A path is reported relative to the repository root: the installed location is
# mentioned in the header comment, and a relative path is what a reader can open.
relative() {
	case "$1" in
		"${root}/"*) printf '%s\n' "${1#"${root}/"}" ;;
		*) printf '%s\n' "$1" ;;
	esac
}

# `gzip -c` reading from stdin stores no file name and a zero mtime, so the same
# content always yields the same size. Compressing the file by name would embed
# both and make the number depend on checkout time.
gzip_size() {
	gzip -9 -c < "$1" | wc -c | tr -d ' '
}

file_size() {
	wc -c < "$1" | tr -d ' '
}

# --- discovery --------------------------------------------------------------

if [ ! -d "${res}" ]; then
	printf 'measure-payload: %s does not exist; is this a checkout of the repository?\n' \
		"${res}" >&2
	exit 2
fi

workdir=$(mktemp -d "${TMPDIR:-/tmp}/airconnect-payload.XXXXXX") || exit 2
trap 'rm -rf "${workdir}"' EXIT INT TERM

# Everything installed for this package, discovered rather than listed, so a new
# resource file is measured without editing this script.
{
	find "${res}" -type f -print
	printf '%s\n' \
		"${pkg}/root/usr/share/luci/menu.d/luci-app-airconnect-manager.json" \
		"${pkg}/root/usr/share/rpcd/acl.d/luci-app-airconnect-manager.json"
} | LC_ALL=C sort > "${workdir}/files"

# --- measure ----------------------------------------------------------------

total=0
total_gzip=0
count=0
violations=0

label_width=98
rule=$(printf '%*s' "$((label_width - 8))" '' | tr ' ' '-')

printf "%-${label_width}s %9s %9s %9s\n" 'file' 'bytes' 'gzip -9' 'cap'
printf "%-${label_width}s %9s %9s %9s\n" "${rule}--------" '---------' '---------' '---------'

while IFS= read -r file; do
	if [ ! -f "${file}" ]; then
		printf 'FAIL  missing file: %s\n' "$(relative "${file}")"
		violations=$((violations + 1))
		continue
	fi
	bytes=$(file_size "${file}")
	gz=$(gzip_size "${file}")
	cap=$(cap_for "${file}")
	count=$((count + 1))
	total=$((total + bytes))
	total_gzip=$((total_gzip + gz))

	mark=''
	if [ "${bytes}" -gt "${cap}" ]; then
		mark='  OVER'
		violations=$((violations + 1))
	fi
	printf "%-${label_width}s %9d %9d %9d%s\n" "$(relative "${file}")" "${bytes}" "${gz}" "${cap}" "${mark}"
done < "${workdir}/files"

printf "%-${label_width}s %9s %9s %9s\n" "${rule}--------" '---------' '---------' '---------'
printf "%-${label_width}s %9d %9d %9d\n" "total (${count} files)" "${total}" "${total_gzip}" "${TOTAL_CAP}"

# --- assertions -------------------------------------------------------------

if [ "${total}" -gt "${TOTAL_CAP}" ]; then
	printf 'FAIL  total payload %d bytes exceeds the %d byte cap by %d\n' \
		"${total}" "${TOTAL_CAP}" "$((total - TOTAL_CAP))"
	violations=$((violations + 1))
fi
if [ "${total_gzip}" -gt "${GZIP_TOTAL_CAP}" ]; then
	printf 'FAIL  total gzip payload %d bytes exceeds the %d byte cap by %d\n' \
		"${total_gzip}" "${GZIP_TOTAL_CAP}" "$((total_gzip - GZIP_TOTAL_CAP))"
	violations=$((violations + 1))
fi

# A package that ships no resource at all is a packaging defect, not a pass: the
# page would render without its stylesheet or its validation rules.
if [ "${count}" -lt 5 ]; then
	printf 'FAIL  only %d files measured; the package must install at least 5 static files\n' "${count}"
	violations=$((violations + 1))
fi

if [ "${violations}" -ne 0 ]; then
	printf '\nFAILED  %d budget violation(s)\n' "${violations}"
	exit 1
fi

printf '\nOK  %d files, %d bytes (%.1f KiB) uncompressed, %d bytes (%.1f KiB) gzip -9\n' \
	"${count}" "${total}" \
	"$(awk -v n="${total}" 'BEGIN { printf "%.1f", n / 1024 }')" \
	"${total_gzip}" \
	"$(awk -v n="${total_gzip}" 'BEGIN { printf "%.1f", n / 1024 }')"
exit 0
