#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 tzzs
#
# Build the four packages on an x86_64 Linux host, including WSL2 on Windows.
#
# This is the local counterpart to the `build` job in .github/workflows/release.yml.
# It does the same steps in the same order so a local build and a CI build produce
# comparable packages, including the generated Chinese LuCI translation package,
# and so the manual steps documented in docs/RELEASE.zh-CN.md are exercised before
# they are trusted in CI.
#
# Why a separate script rather than just running make
# --------------------------------------------------
# The steps that are easy to get wrong are all outside `make`: downloading the
# right SDK, feeding it the right packages, verifying the 95 MB upstream archive
# before it is used, and separating the three package builds so a failure names
# one package instead of stopping the run. Doing them by hand is how the wrong
# SDK version gets used without anyone noticing.
#
# Usage
# -----
#   bash scripts/build-local.sh                 # aarch64_generic (armsr-armv8)
#   bash scripts/build-local.sh --clean         # remove the SDK first
#   bash scripts/build-local.sh --keep          # leave the SDK in place afterwards
#   bash scripts/build-local.sh --output DIR    # where the APKs land
#
# Requires: curl, tar with zstd support, sha256sum, and ~10 GB of disk.
# Runs on Linux only. The router never runs this.

set -euo pipefail

SDK_VERSION='25.12.6'
TARGET='armsr-armv8'
ARCH='aarch64_generic'
GCC='14.3.0'
LIBC='musl'

CLEAN=0
KEEP=0
OUTPUT=''

usage() {
	cat <<'EOF'
usage: bash scripts/build-local.sh [options]

Builds airconnect-engine, airconnect-manager, luci-app-airconnect-manager and
luci-i18n-airconnect-manager-zh-cn against a pinned OpenWrt SDK on an x86_64 Linux
host (including WSL2).

  --output DIR   where the APKs are copied (default packages/output)
  --clean        delete any existing SDK first
  --keep         do not delete the SDK when the build finishes
  --help         show this message

The SDK is left in ~/openwrt-sdk-* by default so a second run does not
re-download 260 MB. Pass --clean to start from scratch.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--output) shift; OUTPUT=${1:-} ;;
		--clean) CLEAN=1 ;;
		--keep) KEEP=1 ;;
		-h|--help) usage; exit 0 ;;
		*) printf 'build-local: unknown argument: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
	esac
	shift
done

# --- paths -----------------------------------------------------------------

here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "${here}/.." && pwd)
OUTPUT=${OUTPUT:-"${root}/packages/output"}

SDK_NAME="openwrt-sdk-${SDK_VERSION}-${TARGET}_gcc-${GCC}_${LIBC}.Linux-x86_64"
SDK_DIR="${HOME}/${SDK_NAME}"
SDK_TARBALL="/tmp/${SDK_NAME}.tar.zst"
SDK_URL="https://downloads.openwrt.org/releases/${SDK_VERSION}/targets/${TARGET}/${SDK_NAME}.tar.zst"

# The upstream archive the engine recipe expects. The hash is the recipe's own
# PKG_HASH; a mismatch means either a bad download or a recipe that was edited
# without updating its hash, and both must stop the build.
ENGINE_ZIP_NAME='AirConnect-1.12.4.zip'
ENGINE_SHA256='ae59d595be80db7f4e93c94c9029baff59dc7515ec03e44505ab2792bbcd1903'
ENGINE_URL="https://github.com/philippe44/AirConnect/releases/download/1.12.4/${ENGINE_ZIP_NAME}"

log()  { printf '\n=== %s ===\n' "$*"; }
die()  { printf 'build-local: %s\n' "$*" >&2; exit 1; }

# --- preflight -------------------------------------------------------------

# The tools that are not on a stock desktop Linux install, and whose absence is
# otherwise discovered minutes into the build.
for tool in curl tar sha256sum make; do
	command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
done

# `tar -I zstd` needs the zstd compressor, and OpenWrt ships the SDK as .tar.zst.
if ! command -v zstd >/dev/null 2>&1; then
	die "zstd not found. On Debian/Ubuntu: sudo apt install zstd"
fi

# A 260 MB SDK plus the build tree plus the feed checkouts is comfortably over
# 10 GB. Better to say so now than to run out of disk inside make.
avail_kb=$(df -Pk "$HOME" | awk 'NR == 2 { print $4 }')
if [ "${avail_kb}" -lt 10485760 ]; then
	printf 'build-local: warning: only %s MB free in %s\n' \
		"$(( avail_kb / 1024 ))" "$HOME" >&2
	printf 'A full build needs about 10 GB. Continuing anyway.\n\n' >&2
fi

# --- SDK -------------------------------------------------------------------

if [ "$CLEAN" = 1 ] && [ -d "$SDK_DIR" ]; then
	log 'removing the existing SDK'
	rm -rf "$SDK_DIR"
fi

if [ -d "$SDK_DIR" ]; then
	log "reusing the SDK at ${SDK_DIR}"
else
	log "downloading ${SDK_NAME}"
	mkdir -p "${HOME}"
	curl -fsSL --retry 3 --retry-delay 2 -o "$SDK_TARBALL" "$SDK_URL" ||
		die "SDK download failed: $SDK_URL"

	# A truncated download otherwise fails deep inside tar with a confusing error.
	tarball_size=$(wc -c < "$SDK_TARBALL")
	if [ "$tarball_size" -lt 100000000 ]; then
		rm -f "$SDK_TARBALL"
		die "the SDK tarball is only ${tarball_size} bytes; the download was truncated"
	fi

	tar -I zstd -xf "$SDK_TARBALL" -C "${HOME}" ||
		die "SDK extraction failed; the tarball may be corrupt"
	rm -f "$SDK_TARBALL"
fi

[ -d "$SDK_DIR" ] || die "no SDK directory at $SDK_DIR"
cd "$SDK_DIR"

# --- feeds -----------------------------------------------------------------

# The same set the CI workflow installs. ucode and rpcd are the runtime the
# manager needs; curl is a runtime dependency of discovery.uc; luci-base is the
# LuCI package's dependency; libopenssl is what lets libcurl configure with TLS.
log 'installing feeds'
./scripts/feeds update packages luci
./scripts/feeds install \
	ucode ucode-mod-fs ucode-mod-socket ucode-mod-ubus ucode-mod-uci \
	rpcd rpcd-mod-ucode curl luci-base libopenssl

# --- frontend build --------------------------------------------------------

# The LuCI page is a bundled React + shadcn/ui app (app.js + app.css), built
# from the package's frontend/ directory by Vite. The bundle is not committed,
# so it must exist before the SDK copies the package tree below. node + npm are
# required here; the script bails early if they are missing rather than failing
# deep inside the SDK build with a "no app.js" copy.
log 'building the React frontend'
command -v node >/dev/null 2>&1 || die 'node is required to build the frontend'
command -v npm  >/dev/null 2>&1 || die 'npm is required to build the frontend'
FRONTEND_DIR="${root}/packages/luci-app-airconnect-manager/frontend"
[ -d "$FRONTEND_DIR" ] || die "missing $FRONTEND_DIR"
(
	cd "$FRONTEND_DIR"
	npm ci
	npm run build
)
BUNDLE_DIR="${root}/packages/luci-app-airconnect-manager/htdocs/luci-static/resources/airconnect-manager"
[ -f "$BUNDLE_DIR/app.js" ]  || die "frontend build did not produce app.js"
[ -f "$BUNDLE_DIR/app.css" ] || die "frontend build did not produce app.css"

# --- link the packages -----------------------------------------------------

# Copied rather than symlinked: the SDK's package scanner follows real paths,
# and a symlink into the working tree makes the build depend on the checkout
# layout instead of on the files.
#
# `cp -r`, not `cp -a`: the scanner decides whether to re-read a package by
# comparing the Makefile's mtime with the stamp it wrote on the last scan. A
# checkout can easily be older than that stamp, and `cp -a` preserves the old
# mtime -- so a package added or changed since the last scan is treated as
# already scanned, never appears in tmp/.packageinfo, and `make defconfig`
# silently drops its CONFIG_PACKAGE_* symbol. The build then reports "no APK
# was produced" without naming the package. `cp -r` refreshes the mtime while
# still copying the mode bits (the init script stays executable).
log 'linking the packages into the SDK'
for pkg in airconnect-engine airconnect-manager luci-app-airconnect-manager; do
	[ -d "${root}/packages/${pkg}" ] || die "missing packages/${pkg}"
	rm -rf "${SDK_DIR}/package/${pkg}"
	cp -r "${root}/packages/${pkg}" "${SDK_DIR}/package/${pkg}"
done

# --- upstream archive ------------------------------------------------------

log 'fetching the upstream engine archive'
mkdir -p dl
if [ ! -f "dl/${ENGINE_ZIP_NAME}" ]; then
	curl -fsSL --retry 3 --retry-delay 2 -o "dl/${ENGINE_ZIP_NAME}" "$ENGINE_URL" ||
		die "engine archive download failed: $ENGINE_URL"
fi

# The two static binaries are the entire payload of airconnect-engine. A download
# that differs from the recipe's hash must stop here, not ship silently.
printf '%s  dl/%s\n' "$ENGINE_SHA256" "$ENGINE_ZIP_NAME" | sha256sum -c - ||
	die "the engine archive does not match PKG_HASH; re-download it or fix the recipe"

# Cached SDKs retain package files from earlier versions. Clear only this
# project's APKs before compiling so the current run owns every collected APK.
APK_DIR="bin/packages/${ARCH}/base"
rm -f "${APK_DIR}"/airconnect-engine-*.apk \
	"${APK_DIR}"/airconnect-manager-*.apk \
	"${APK_DIR}"/luci-app-airconnect-manager-*.apk \
	"${APK_DIR}"/luci-i18n-airconnect-manager-zh-cn-*.apk

# --- configure -------------------------------------------------------------

log 'configuring'
# CONFIG_LIBCURL_OPENSSL=y selects the TLS backend. Without it curl's configure
# fails with "TLS not detected" and the whole manager build stops on a dependency
# that is not the manager's fault.
cat >> .config <<EOF
CONFIG_PACKAGE_airconnect-engine=m
CONFIG_PACKAGE_airconnect-manager=m
CONFIG_PACKAGE_luci-app-airconnect-manager=m
CONFIG_PACKAGE_luci-i18n-airconnect-manager-zh-cn=m
CONFIG_LIBCURL_OPENSSL=y
EOF

# libopenssl's optional afalg and devcrypto engines each make libopenssl depend
# on kernel/linux/compile, which with the SDK's CONFIG_ALL_KMODS=y cross-builds
# the target's entire kernel module set -- the OOM recorded in
# docs/VERIFICATION.zh-CN.md. Nothing here uses either engine, so turn them off
# in the form Kconfig writes them, so `make defconfig` keeps them off instead of
# re-enabling a default.
for symbol in CONFIG_PACKAGE_libopenssl-afalg CONFIG_PACKAGE_libopenssl-devcrypto; do
	if grep -q "^${symbol}=" .config; then
		sed "s|^${symbol}=.*|# ${symbol} is not set|" .config > .config.tmp
		mv .config.tmp .config
	elif ! grep -q "^# ${symbol} is not set$" .config; then
		printf '# %s is not set\n' "${symbol}" >> .config
	fi
done

make defconfig

# A symbol that does not survive defconfig means the SDK cannot see the package
# (usually a missing feed or an unresolved DEPENDS). Failing here names the
# symbol instead of letting the build stop later at "No rule to make target".
dropped=''
for symbol in CONFIG_PACKAGE_airconnect-engine=m \
	CONFIG_PACKAGE_airconnect-manager=m \
	CONFIG_PACKAGE_luci-app-airconnect-manager=m \
	CONFIG_PACKAGE_luci-i18n-airconnect-manager-zh-cn=m; do
	grep -qx "${symbol}" .config || dropped="${dropped} ${symbol}"
done
grep -qx 'CONFIG_LIBCURL_OPENSSL=y' .config || dropped="${dropped} CONFIG_LIBCURL_OPENSSL=y"
if [ -n "${dropped}" ]; then
	die "make defconfig dropped required symbol(s):${dropped} -- the SDK cannot see those packages; check the feeds"
fi

# --- build -----------------------------------------------------------------

# One package per make invocation: a failure then names the package, instead of
# stopping the whole run with a message about whichever target happened to be
# building. V=s so a real error is visible rather than a summary line.
#
# Each line is written out rather than generated by a loop: the order matters
# (the manager DEPENDS on the engine, the LuCI package on the manager, and the
# generated translation package on the LuCI package), and a reader -- or a check
# that compares this against the workflow -- should see the same four invocations
# that release.yml makes.
log 'make package/airconnect-engine/compile'
make package/airconnect-engine/compile V=s

log 'make package/airconnect-manager/compile'
make package/airconnect-manager/compile V=s

log 'make package/luci-app-airconnect-manager/compile'
make package/luci-app-airconnect-manager/compile V=s

log 'make package/luci-i18n-airconnect-manager-zh-cn/compile'
make package/luci-i18n-airconnect-manager-zh-cn/compile V=s

# --- collect ---------------------------------------------------------------

APK_DIR="bin/packages/${ARCH}/base"
log 'collecting the packages'

# The output directory may survive a previous build. Remove only this
# project's APKs; dependency packages remain in the SDK for subsequent builds.
mkdir -p "$OUTPUT"
rm -f "$OUTPUT"/airconnect-engine-*.apk \
	"$OUTPUT"/airconnect-manager-*.apk \
	"$OUTPUT"/luci-app-airconnect-manager-*.apk \
	"$OUTPUT"/luci-i18n-airconnect-manager-zh-cn-*.apk
found=0
for apk in \
	"${APK_DIR}"/airconnect-*.apk \
	"${APK_DIR}"/luci-app-airconnect-manager-*.apk \
	"${APK_DIR}"/luci-i18n-airconnect-manager-zh-cn-*.apk; do
	[ -e "$apk" ] || continue
	found=$((found + 1))
	cp "$apk" "$OUTPUT/"
done
[ "$found" -eq 4 ] || die "expected four APKs, found ${found} in ${APK_DIR}"

ls -la "$OUTPUT"/*.apk

# A package that apk itself cannot read is not a package. apk-tools is present on
# any Linux host that has an apk-based system, and on others it can be installed;
# when it is missing the check is skipped rather than failing the build.
if command -v apk >/dev/null 2>&1; then
	log 'checking the package contents'
	for apk in "$OUTPUT"/*.apk; do
		apk manifest --allow-untrusted "$apk" >/dev/null ||
			die "$(basename "$apk") cannot be read by apk"
	done
	echo "all packages are readable by apk"
else
	echo "apk not installed; skipping the readability check"
	echo "(on Debian/Ubuntu: sudo apt install apk-tools)"
fi

log 'done'
printf '\nPackages are in %s\n' "$OUTPUT"
printf '\nTo install on the router:\n'
printf '  scp %s/*.apk istoreos:/tmp/\n' "$OUTPUT"
printf '  ssh istoreos "apk add --allow-untrusted /tmp/airconnect-engine-*.apk \\\n'
printf '                     /tmp/airconnect-manager-*.apk \\\n'
printf '                     /tmp/luci-app-airconnect-manager-*.apk \\\n'
printf '                     /tmp/luci-i18n-airconnect-manager-zh-cn-*.apk"\n'

if [ "$KEEP" != 1 ]; then
	printf '\nThe SDK is still at %s\n' "$SDK_DIR"
	printf 'Pass --clean to remove it, or delete it by hand to reclaim the space.\n'
fi
