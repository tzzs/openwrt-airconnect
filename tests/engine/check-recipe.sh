#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 tzzs
#
# Host-only static and behavioural checks for the airconnect-engine recipe.
# Needs neither OpenWrt nor a router: bash + make + zip + unzip are enough.
#
# Usage: bash tests/engine/check-recipe.sh
# Exit status: 0 when every check passes, 1 otherwise.

set -u
set -o pipefail

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "${here}/../.." && pwd)

makefile="${root}/packages/airconnect-engine/Makefile"
extract="${root}/packages/airconnect-engine/files/extract-engines.sh"

passed=0
failed=0

ok() {
	passed=$((passed + 1))
	printf 'ok   - %s\n' "$1"
}

no() {
	failed=$((failed + 1))
	printf 'FAIL - %s\n' "$1"
	[ $# -gt 1 ] && printf '       %s\n' "$2"
}

section() {
	printf '\n# %s\n' "$1"
}

# --- tools ------------------------------------------------------------------
section 'host tooling'
for tool in make zip unzip sh; do
	if command -v "${tool}" >/dev/null 2>&1; then
		ok "tool present: ${tool}"
	else
		no "tool present: ${tool}" 'required on the host'
	fi
done

# --- (1) recipe content -----------------------------------------------------
section 'recipe content'
if grep -qx 'PKG_VERSION:=1.12.4' "${makefile}"; then
	ok 'PKG_VERSION is 1.12.4'
else
	no 'PKG_VERSION is 1.12.4' 'version was changed'
fi
if grep -qx 'PKG_HASH:=ae59d595be80db7f4e93c94c9029baff59dc7515ec03e44505ab2792bbcd1903' "${makefile}"; then
	ok 'PKG_HASH matches the verified 1.12.4 digest'
else
	no 'PKG_HASH matches the verified 1.12.4 digest' 'hash must not change'
fi
if grep -Eq '^PKG_SOURCE_URL:=https://github.com/philippe44/AirConnect/releases/download/' "${makefile}"; then
	ok 'PKG_SOURCE_URL points at the philippe44/AirConnect releases path'
else
	no 'PKG_SOURCE_URL points at the philippe44/AirConnect releases path' 'wrong source URL'
fi
if grep -Eq '^[[:space:]]*DEPENDS:=@\(aarch64\|\|x86_64\)' "${makefile}"; then
	ok 'DEPENDS restricts the build to aarch64/x86_64'
else
	no 'DEPENDS restricts the build to aarch64/x86_64' 'architecture gate missing'
fi
if grep -q 'AIRCONNECT_ARCH' "${makefile}" && grep -Eq 'define Build/Prepare' "${makefile}" &&
	awk '/define Build\/Prepare/{f=1} f&&/AIRCONNECT_ARCH/{print; c=1} f&&/^endef/{exit}' "${makefile}" | grep -q 'AIRCONNECT_ARCH'; then
	ok 'Build/Prepare references AIRCONNECT_ARCH'
else
	no 'Build/Prepare references AIRCONNECT_ARCH' 'prepare must use the normalized arch'
fi
if grep -q 'unzip -l' "${makefile}" || grep -q 'unzip -l' "${extract}"; then
	ok 'unzip -l diagnostics are present (recipe or extract helper)'
else
	no 'unzip -l diagnostics are present (recipe or extract helper)' 'missing archive listing on failure'
fi
if [ -f "${extract}" ] && head -1 "${extract}" | grep -qx '#!/bin/sh'; then
	ok 'extraction helper exists with a POSIX #!/bin/sh shebang'
else
	no 'extraction helper exists with a POSIX #!/bin/sh shebang' 'missing or wrong shebang'
fi
if grep -Eq '^[[:space:]]*PKG_LICENSE:=MIT AND Apache-2.0 AND BSD-3-Clause AND LGPL-2.0 AND LGPL-2.1 AND GPL-2.0 AND GPL-3.0$' "${makefile}"; then
	ok 'PKG_LICENSE lists the actual linked component set (S5 audit)'
else
	no 'PKG_LICENSE lists the actual linked component set (S5 audit)' 'license line no longer MIT-only'
fi
notices="${root}/packages/airconnect-engine/files/THIRD-PARTY-NOTICES"
if [ -f "${notices}" ]; then
	ok 'third-party notices file ships with the package'
else
	no 'third-party notices file ships with the package' 'THIRD-PARTY-NOTICES missing'
fi
if grep -Eq '^[[:space:]]*PKG_LICENSE_FILES:=' "${makefile}"; then
	ok 'PKG_LICENSE_FILES points at the shipped notices'
else
	no 'PKG_LICENSE_FILES points at the shipped notices' 'no license-files metadata'
fi
if ! grep -q 'init.d' "${makefile}" && ! grep -q '/etc/config' "${makefile}"; then
	ok 'engine package adds no init script or config'
else
	no 'engine package adds no init script or config' 'T6 must not add services'
fi

# --- (2) ARCH mapping logic -------------------------------------------------
section 'ARCH normalization'
# Pull the mapping block verbatim from the recipe so the test cannot drift from
# the shipped logic. It runs from the AIRCONNECT_ARCH assignment up to (but not
# including) the include of package.mk.
block=$(awk '
	/^AIRCONNECT_ARCH := \$\(ARCH\)$/ { capture = 1 }
	/^include \$\(INCLUDE_DIR\)\/package.mk$/ { if (capture) exit }
	capture { print }
' "${makefile}")

if [ -z "${block}" ]; then
	no 'extracted the ARCH mapping block from the recipe' 'mapping block not found'
else
	ok 'extracted the ARCH mapping block from the recipe'
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/airconnect-eng.XXXXXX") || {
	no 'create a temp dir for mapping fixtures' 'mktemp failed'
	exit 1
}
trap 'rm -rf "${tmp}"' EXIT

# Each entry: "ARCH|expected" where expected is the normalized token or the
# literal "ERROR" when the build must refuse.
cases='x86_64|x86_64
aarch64|aarch64
aarch64_generic|aarch64
aarch64_cortex-a53|aarch64
arm_cortex-a7_neon-vfpv4|arm
arm|arm
armv7|armv7
mips|mips
mipsel|mipsel
riscv64|ERROR'

while IFS='|' read -r arch expected; do
	[ -n "${arch}" ] || continue
	frag="${tmp}/arch-${arch}.mk"
	{
		printf 'ARCH := %s\n\n' "${arch}"
		printf '%s\n\n' "${block}"
		printf 'all:\n\t@echo "$(AIRCONNECT_ARCH)"\n'
	} > "${frag}"

	out=$(make -f "${frag}" 2>"${tmp}/err" all || true)
	if [ "${expected}" = ERROR ]; then
		if [ -s "${tmp}/err" ] && grep -q 'unsupported ARCH' "${tmp}/err"; then
			ok "ARCH=${arch} correctly refuses to build"
		else
			no "ARCH=${arch} correctly refuses to build" "expected an error, got: ${out}"
		fi
	else
		if [ "${out}" = "${expected}" ]; then
			ok "ARCH=${arch} normalizes to ${expected}"
		else
			no "ARCH=${arch} normalizes to ${expected}" "got: ${out}"
		fi
	fi
done <<EOF
${cases}
EOF

# --- (3) extraction script with a synthetic archive -------------------------
section 'extraction of a synthetic archive'
work="${tmp}/extract"
rm -rf "${work}"
mkdir -p "${work}/dl" "${work}/build"

# Build an archive that mirrors the upstream layout: the two normalized
# aarch64 binaries plus a couple of unrelated files, each with an ELF magic
# header so the later ELF check would accept them.
printf '\x7fELF\xff\x00aarch64-upnp' > "${work}/dl/airupnp-linux-aarch64-static"
printf '\x7fELF\xff\x00aarch64-cast' > "${work}/dl/aircast-linux-aarch64-static"
printf 'not a binary' > "${work}/dl/README.txt"
( cd "${work}/dl" && zip -q "${work}/AirConnect-1.12.4.zip" \
	airupnp-linux-aarch64-static aircast-linux-aarch64-static README.txt )

if [ -f "${work}/AirConnect-1.12.4.zip" ]; then
	ok 'synthetic AirConnect-1.12.4.zip built'
else
	no 'synthetic AirConnect-1.12.4.zip built' 'zip step failed'
fi

if sh "${extract}" "${work}/AirConnect-1.12.4.zip" "${work}/build" aarch64; then
	ok 'extract-engines.sh places both aarch64 binaries'
else
	no 'extract-engines.sh places both aarch64 binaries' 'extraction failed'
fi
if [ -f "${work}/build/airupnp-linux-aarch64-static" ] &&
   [ -f "${work}/build/aircast-linux-aarch64-static" ] &&
   [ ! -f "${work}/build/README.txt" ]; then
	ok 'exactly the two expected binaries land in the build dir'
else
	no 'exactly the two expected binaries land in the build dir' 'wrong files extracted'
fi

# Missing-arch name: ask for an arch the archive does not contain, and confirm
# it fails and prints the archive listing (the self-diagnosing requirement).
if sh "${extract}" "${work}/AirConnect-1.12.4.zip" "${work}/build" x86_64 2>"${work}/err"; then
	no 'extract fails cleanly when the arch binary is missing' 'should have errored'
else
	ok 'extract fails cleanly when the arch binary is missing'
	if grep -q 'archive contents were' "${work}/err" && grep -q 'airupnp-linux-aarch64-static' "${work}/err"; then
		ok 'failure prints the real archive listing'
	else
		no 'failure prints the real archive listing' 'diagnostic listing missing'
	fi
fi

# Missing archive: an unreadable source must error with an actionable message.
if sh "${extract}" "${work}/DoesNotExist.zip" "${work}/build" aarch64 2>"${work}/err"; then
	no 'extract fails on a missing archive' 'should have errored'
else
	ok 'extract fails on a missing archive'
fi

printf '\ncheck-recipe: %d passed, %d failed\n' "${passed}" "${failed}"
[ "${failed}" -eq 0 ] || exit 1
exit 0
