#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 tzzs
#
# build-sdk.sh - compile the three packages with an OpenWrt SDK.
#
# HOST/LINUX TOOL, NOT A ROUTER SCRIPT. The OpenWrt SDK is a Linux x86_64
# toolchain and this script drives `make` inside it. It never runs on the
# router and nothing it does ships in a package. The scripts under
# packages/*/files/ are the router-side ones and are POSIX sh; this file is
# deliberately bash because it only ever runs on the build host.
#
#   bash scripts/build-sdk.sh --sdk /path/to/openwrt-sdk-...
#   bash scripts/build-sdk.sh --sdk /path/to/sdk --packages "airconnect-engine"
#
# What it does, in order:
#   1. validates the SDK directory and, if feeds are missing, installs them from
#      the already-downloaded feeds/ tree (no network fetch of the AirConnect
#      archive, ever);
#   2. refuses to run while another build is active in the same SDK directory,
#      because two concurrent builds corrupt the same staging_dir;
#   3. copies packages/<name> into <sdk>/package/<name>;
#   4. pins the required CONFIG_* symbols in <sdk>/.config and runs
#      `make defconfig`, then verifies the symbols survived;
#   5. runs `make package/<name>/compile V=s` for each requested package and
#      stops at the first failure, keeping the full log;
#   6. prints every resulting APK path with its size and exits non-zero if any
#      requested package produced no APK.
#
# The AirConnect release archive is NOT downloaded here. It must already be in
# <sdk>/dl/AirConnect-<version>.zip with the PKG_HASH recorded in
# packages/airconnect-engine/Makefile. `--help` prints the command to fetch it.

set -u
set -o pipefail

PROGRAM='build-sdk.sh'

DEFAULT_PACKAGES='airconnect-engine airconnect-manager luci-app-airconnect-manager'

CONFIG_SYMBOLS='CONFIG_PACKAGE_airconnect-engine=m
CONFIG_PACKAGE_airconnect-manager=m
CONFIG_PACKAGE_luci-app-airconnect-manager=m
CONFIG_PACKAGE_libopenssl=y
CONFIG_LIBCURL_OPENSSL=y'

CONFIG_UNSYMBOLS='CONFIG_PACKAGE_libopenssl-afalg
CONFIG_PACKAGE_libopenssl-devcrypto'

REQUIRED_FEEDS='packages luci base'

usage() {
	cat <<EOF
usage: bash scripts/build-sdk.sh --sdk <path> [--packages "<list>"] [--jobs N]

Compiles the AirConnect packages with an OpenWrt SDK. Host/Linux tool: it runs
inside the SDK toolchain directory, never on the router.

  --sdk <path>        required. The extracted SDK directory, e.g.
                      /tmp/openwrt-sdk-25.12.6-armsr-armv8_gcc-14.3.0_musl.Linux-x86_64
  --packages "<list>" space separated package names to build. Default:
                      "${DEFAULT_PACKAGES}"
  --jobs N            passed to make as -jN (default: the SDK default)
  --keep-openssl-engines
                      build libopenssl's optional afalg and devcrypto engines.
                      Off by default: each one makes libopenssl depend on
                      kernel/linux/compile, which with the SDK's CONFIG_ALL_KMODS
                      cross-builds the target's whole kernel module set. Nothing
                      in this project uses either engine.
  --help, -h          show this message

Requires an already-prepared SDK:
  * the packages, luci and base feeds present. When they are not yet installed
    into <sdk>/package/feeds/, this script runs \`./scripts/feeds install -a\`
    from the local feeds/ tree (offline; it does not clone anything).
  * the AirConnect release archive in <sdk>/dl/. It is never downloaded here:
      curl -L -o <sdk>/dl/AirConnect-1.12.4.zip \\
        https://github.com/philippe44/AirConnect/releases/download/1.12.4/AirConnect-1.12.4.zip
      sha256sum <sdk>/dl/AirConnect-1.12.4.zip   # must equal PKG_HASH in the recipe
    The build itself verifies the digest, so a wrong or truncated file fails in
    Build/Prepare rather than producing a package.

Exit status: 0 when every requested package produced an APK, 1 on a build
failure, 2 on a usage or SDK/feed problem.
EOF
}

say() {
	printf '%s: %s\n' "$PROGRAM" "$*"
}

warn() {
	printf '%s: warning: %s\n' "$PROGRAM" "$*" >&2
}

fail() {
	printf '%s: %s\n' "$PROGRAM" "$*" >&2
	exit "${2:-1}"
}

usage_fail() {
	printf '%s: %s\n\n' "$PROGRAM" "$*" >&2
	usage >&2
	exit 2
}

sdk=''
packages="$DEFAULT_PACKAGES"
jobs=''
keep_openssl_engines=0

while [ "$#" -gt 0 ]; do
	case "$1" in
		--sdk)
			[ "$#" -ge 2 ] || usage_fail '--sdk needs a value'
			sdk="$2"
			shift 2
			;;
		--sdk=*)
			sdk="${1#--sdk=}"
			shift
			;;
		--packages)
			[ "$#" -ge 2 ] || usage_fail '--packages needs a value'
			packages="$2"
			shift 2
			;;
		--packages=*)
			packages="${1#--packages=}"
			shift
			;;
		--jobs)
			[ "$#" -ge 2 ] || usage_fail '--jobs needs a value'
			jobs="$2"
			shift 2
			;;
		--jobs=*)
			jobs="${1#--jobs=}"
			shift
			;;
		--help|-h)
			usage
			exit 0
			;;
		--keep-openssl-engines)
			keep_openssl_engines=1
			shift
			;;
		*)
			usage_fail "unknown argument: $1"
			;;
	esac
done

[ -n "$sdk" ] || usage_fail '--sdk is required'

if [ -n "$jobs" ]; then
	case "$jobs" in
		*[!0-9]*|'') usage_fail "--jobs must be a positive integer, got: $jobs" ;;
	esac
fi

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) || fail 'cannot resolve script directory' 2
root=$(CDPATH='' cd -- "${here}/.." && pwd) || fail 'cannot resolve repository root' 2

[ -d "${root}/packages" ] || fail "${root}/packages does not exist" 2

if [ ! -d "$sdk" ]; then
	fail "--sdk directory does not exist: $sdk" 2
fi
sdk=$(CDPATH='' cd -- "$sdk" && pwd) || fail "cannot enter $sdk" 2

for probe in rules.mk Makefile include/package.mk scripts/feeds; do
	if [ ! -e "${sdk}/${probe}" ]; then
		fail "$sdk does not look like an OpenWrt SDK (missing ${probe})" 2
	fi
done

if [ ! -f "${sdk}/.config" ]; then
	fail "$sdk/.config is missing; run \`make defconfig\` in the SDK once first" 2
fi

for tool in make; do
	command -v "$tool" >/dev/null 2>&1 || fail "$tool not found on PATH" 2
done

if command -v pgrep >/dev/null 2>&1 && [ -d /proc ]; then
	for pid in $(pgrep -x make 2>/dev/null || true); do
		cwd=$(readlink "/proc/${pid}/cwd" 2>/dev/null || true)
		[ "$cwd" = "$sdk" ] || continue
		fail "another build is already running in $sdk (make pid $pid); wait for it before starting a second one" 2
	done
fi

missing_feeds=''
for feed in $REQUIRED_FEEDS; do
	if [ ! -d "${sdk}/package/feeds/${feed}" ]; then
		missing_feeds="${missing_feeds} ${feed}"
	fi
done

if [ -n "$missing_feeds" ]; then
	for feed in $missing_feeds; do
		if [ ! -d "${sdk}/feeds/${feed}" ]; then
			fail "feed '$feed' is not in ${sdk}/feeds; run \`./scripts/feeds update -a\` in the SDK (needs network) first" 2
		fi
	done
	say "installing feeds into package/feeds/:${missing_feeds}"
	if ! ( cd "$sdk" && ./scripts/feeds install -a ) >/dev/null 2>&1; then
		fail "failed to install the feeds into ${sdk}/package/feeds" 2
	fi
	for feed in $missing_feeds; do
		[ -d "${sdk}/package/feeds/${feed}" ] ||
			fail "feed '$feed' still not installed after scripts/feeds install -a" 2
	done
fi

case " ${packages} " in
	*" airconnect-engine "*)
		version=$(sed -n 's/^PKG_VERSION:=//p' "${root}/packages/airconnect-engine/Makefile" | head -n 1)
		hash=$(sed -n 's/^PKG_HASH:=//p' "${root}/packages/airconnect-engine/Makefile" | head -n 1)
		archive="${sdk}/dl/AirConnect-${version}.zip"
		if [ ! -f "$archive" ]; then
			cat >&2 <<EOF
${PROGRAM}: missing release archive: $archive

The archive is never downloaded by this script. Fetch it once:
  curl -L -o '${archive}' \\
    https://github.com/philippe44/AirConnect/releases/download/${version}/AirConnect-${version}.zip
  sha256sum '${archive}'
Expected SHA256 (PKG_HASH): ${hash}
EOF
			exit 2
		fi
		say "release archive present: $(basename -- "$archive")"
		;;
esac

copy_package() {
	name="$1"
	if [ ! -d "${root}/packages/${name}" ]; then
		fail "no such package in the repository: packages/${name}" 2
	fi
	rm -rf "${sdk:?}/package/${name}"
	mkdir -p "${sdk}/package"
	(
		cd "${root}/packages" || exit 1
		COPYFILE_DISABLE=1 bsdtar -cf - --exclude '._*' "${name}" 2>/dev/null ||
			COPYFILE_DISABLE=1 tar -cf - --exclude '._*' "${name}"
	) | (
		cd "${sdk}/package" || exit 1
		tar xf -
	) || fail "failed to copy packages/${name} into ${sdk}/package" 2
	find "${sdk}/package/${name}" -name '._*' -type f -delete 2>/dev/null || true
	say "copied packages/${name} -> ${sdk}/package/${name}"
}

for name in $packages; do
	copy_package "$name"
done

changed=0
while IFS= read -r line; do
	[ -n "$line" ] || continue
	symbol=${line%%=*}
	value=${line#*=}
	if grep -qx "${symbol}=${value}" "${sdk}/.config"; then
		continue
	fi
	set_config "$symbol" "$value"
	changed=$((changed + 1))
done <<EOF
${CONFIG_SYMBOLS}
EOF

if [ "$keep_openssl_engines" -eq 0 ]; then
	while IFS= read -r symbol; do
		[ -n "$symbol" ] || continue
		if grep -qx "# ${symbol} is not set" "${sdk}/.config"; then
			continue
		fi
		unset_config "$symbol"
		changed=$((changed + 1))
	done <<EOF
${CONFIG_UNSYMBOLS}
EOF
fi

if [ "$changed" -gt 0 ]; then
	say "pinned $changed CONFIG symbol(s) in ${sdk}/.config"
fi

say 'running make defconfig'
if ! ( cd "$sdk" && make defconfig ) >"${TMPDIR:-/tmp}/build-sdk-defconfig.$$.log" 2>&1; then
	tail -n 20 "${TMPDIR:-/tmp}/build-sdk-defconfig.$$.log" >&2
	fail 'make defconfig failed' 2
fi
rm -f "${TMPDIR:-/tmp}/build-sdk-defconfig.$$.log"

dropped=''
for name in $packages; do
	if ! grep -qx "CONFIG_PACKAGE_${name}=m" "${sdk}/.config"; then
		dropped="${dropped} CONFIG_PACKAGE_${name}=m"
	fi
done
if ! grep -qx 'CONFIG_LIBCURL_OPENSSL=y' "${sdk}/.config"; then
	dropped="${dropped} CONFIG_LIBCURL_OPENSSL=y"
fi
if [ -n "$dropped" ]; then
	cat >&2 <<EOF
${PROGRAM}: make defconfig dropped required symbol(s):${dropped}

This means the SDK cannot see the package: either its feed is not installed or
its DEPENDS do not resolve. Check with:
  cd '${sdk}' && ./scripts/feeds install -a && make defconfig
  cd '${sdk}' && make package/<name>/compile V=s
EOF
	exit 2
fi

arch_packages=$(sed -n 's/^CONFIG_TARGET_ARCH_PACKAGES="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "${sdk}/.config" | head -n 1)
[ -n "$arch_packages" ] || arch_packages=$(sed -n 's/^CONFIG_ARCH_PACKAGES="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "${sdk}/.config" | head -n 1)
[ -n "$arch_packages" ] || arch_packages=''

logdir=$(mktemp -d "${TMPDIR:-/tmp}/airconnect-sdk-build.XXXXXX") || fail 'cannot create a log directory' 2
say "build logs: $logdir"

make_args=''
if [ -n "$jobs" ]; then
	make_args="-j${jobs}"
fi

curl_packages=''
case " ${packages} " in
	*" airconnect-manager "*|*" luci-app-airconnect-manager "*)
		curl_packages=1
		;;
esac

build_one() {
	name="$1"
	log="${logdir}/${name}.log"
	say "compiling ${name} (log: ${log})"
	job_args="$make_args"
	if [ -n "$curl_packages" ] && [ -z "$jobs" ] && [ "$name" != 'airconnect-engine' ]; then
		job_args='-j1'
		printf '%s: note: building %s serially (-j1) to stay inside the VM memory limit\n' \
			"$PROGRAM" "$name" >&2
	fi
	# shellcheck disable=SC2086  # job_args is intentionally word split
	if ( cd "$sdk" && make ${job_args} "package/${name}/compile" V=s ) >"$log" 2>&1; then
		return 0
	fi
	# The real error is usually far above the tail: OpenWrt prints the failing
	# command, then a long chain of recursive make context.
	printf '\n%s: build failed: %s\n' "$PROGRAM" "$name" >&2
	printf '%s: full log: %s\n\n' "$PROGRAM" "$log" >&2
	printf -- '--- error lines ---\n' >&2
	grep -nE '(\*\*\*|ERROR|Error [0-9]|error:|failed to build)' "$log" | tail -n 30 >&2 ||
		printf '(no error line matched)\n' >&2
	printf -- '--- last 30 lines ---\n' >&2
	tail -n 30 "$log" >&2
	return 1
}

failed=''
no_apk=''
report=''

for name in $packages; do
	if ! build_one "$name"; then
		failed="$name"
		break
	fi
	apk=$(find_apk "$name")
	if [ -z "$apk" ]; then
		no_apk="${no_apk} ${name}"
		report="${report}NOAPK ${name}
"
		continue
	fi
	size=$(wc -c < "$apk" | tr -d ' ')
	report="${report}${name}|${apk}|${size}
"
done

printf '\n'
if [ -n "$failed" ]; then
	printf '%s: stopped at the first failure: %s\n' "$PROGRAM" "$failed" >&2
	if [ -n "$report" ]; then
		printf 'APKs produced before the failure:\n'
		printf '%s' "$report" | while IFS='|' read -r pkg path bytes; do
			[ -n "$pkg" ] || continue
			printf '  %-32s %s (%s bytes)\n' "$pkg" "$path" "$bytes"
		done
	fi
	exit 1
fi

printf 'APKs:\n'
printf '%s' "$report" | while IFS='|' read -r pkg path bytes; do
	[ -n "$pkg" ] || continue
	if [ -z "$path" ]; then
		printf '  %-32s MISSING (no APK was produced)\n' "$pkg"
		continue
	fi
	printf '  %-32s %s (%s bytes)\n' "$pkg" "$path" "$bytes"
done

if [ -n "$no_apk" ]; then
	printf '\n%s: no APK produced for:%s\n' "$PROGRAM" "$no_apk" >&2
	exit 1
fi

printf '\n%s: all %d package(s) built\n' "$PROGRAM" "$(printf '%s\n' "$packages" | wc -w | tr -d ' ')"
printf '%s: inspect a payload with:\n' "$PROGRAM"
printf "  %s/staging_dir/host/bin/apk extract --allow-untrusted --destination /tmp/chk <apk>\n" "$sdk"
rm -rf "$logdir"
exit 0
