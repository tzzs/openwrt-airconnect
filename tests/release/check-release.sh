#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Static checks on the release pipeline.
#
# These catch the mistakes that are invisible until a release fails: a workflow
# that references a step that does not exist, a version file that disagrees with
# the Makefile it is supposed to bump, or a config that points at the wrong
# action. None of it needs network or a runner.
#
# Run from any directory; paths resolve against the repository root.

set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"

pass=0
fail=0

ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL - %s\n       %s\n' "$1" "${2:-}"; }

section() { printf '\n%s\n' "$1"; }

# ---------------------------------------------------------------------------
section 'the workflow files parse and declare what they claim'

for f in .github/workflows/test.yml .github/workflows/release.yml; do
	if [ -f "$f" ]; then
		ok "$f exists"
	else
		no "$f exists" 'missing'
	fi
done

# A YAML parse error would only surface when the workflow runs, which is the
# worst time to find out. python3 is a host tool; this never runs on the router.
if python3 -c 'import yaml' 2>/dev/null; then
	for f in .github/workflows/test.yml .github/workflows/release.yml; do
		if python3 -c "
import sys, yaml
d = yaml.safe_load(open('$f'))
assert 'jobs' in d, 'no jobs'
" 2>/dev/null; then
			ok "$f is valid YAML with jobs"
		else
			no "$f is valid YAML with jobs" "$(python3 -c "import yaml; yaml.safe_load(open('$f'))" 2>&1 | head -1)"
		fi
	done
else
	printf 'skip - pyyaml unavailable, not parsing YAML\n'
fi

# release.yml must declare both jobs it documents in docs/RELEASE.zh-CN.md.
if grep -q '^  release-please:' .github/workflows/release.yml; then
	ok 'release.yml declares the release-please job'
else
	no 'release.yml declares the release-please job' 'missing'
fi
if grep -q '^  build:' .github/workflows/release.yml; then
	ok 'release.yml declares the build job'
else
	no 'release.yml declares the build job' 'missing'
fi

# ---------------------------------------------------------------------------
section 'release.yml wiring'

# The build job must not run unless a release was actually created, otherwise
# every push to main would spend minutes compiling nothing.
if grep -q 'if: needs.release-please.outputs.release_created' .github/workflows/release.yml; then
	ok 'build only runs when release-please created a release'
else
	no 'build only runs when release-please created a release' 'guard missing'
fi

# release-please must not run on a PR branch: it would open a release PR from a
# release PR.
if grep -q "github.ref == 'refs/heads/main'" .github/workflows/release.yml; then
	ok 'release-please only runs on main'
else
	no 'release-please only runs on main' 'branch guard missing'
fi

# Actions are pinned by major version. A floating ref means a third-party change
# can alter the release pipeline without a commit here.
for action in 'actions/checkout@v4' 'actions/cache@v4' 'googleapis/release-please-action@v4'; do
	if grep -q "uses: $action" .github/workflows/release.yml; then
		ok "$action is pinned by major version"
	else
		no "$action is pinned by major version" 'not referenced'
	fi
done

# The pinned ucode tag predates the GCC used by ubuntu-latest. Its const
# qualifier warnings are harmless for this host-only interpreter build, but
# must not be promoted to errors; the project test suites still fail normally.
# LD_LIBRARY_PATH must stay step-scoped: a job-wide workspace loader path would
# be inherited by every action and shell step in the job.
if grep -q -- '-DCMAKE_C_FLAGS=-Wno-error=discarded-qualifiers' .github/workflows/test.yml &&
	grep -q 'key: ucode-.*-3' .github/workflows/test.yml &&
	grep -q 'UCODE_REF: [0-9a-f]\{40\}' .github/workflows/test.yml &&
	python3 - <<'PY'
import sys
from pathlib import Path
lines = Path('.github/workflows/test.yml').read_text().split('\n')
# A job-level env block sits at 4 spaces under `jobs.<id>`; step env at 8+.
for index, line in enumerate(lines):
    if line.startswith('    env:'):
        for follow in lines[index + 1:]:
            if not follow.startswith('      ') or follow.strip() == '':
                break
            if follow.strip().startswith('LD_LIBRARY_PATH:'):
                sys.exit(1)  # a job-wide loader path is inherited by every step
PY
then
	ok 'host workflow keeps the ucode loader path step-scoped'
else
	no 'host workflow keeps the ucode loader path step-scoped' \
		'missing CMake override, stale cache key, or a job-wide LD_LIBRARY_PATH'
fi

# Test fixtures run on the target interpreter too (the state suites load them
# through the plugin). iStoreOS 25.12.5's libucode.so.20230711 rejects
# `export function`, so a fixture written that way hides a real device failure
# behind a newer host interpreter.
if grep -rq '^export function' tests/; then
	no 'test fixtures use the target-compatible export syntax' \
		"$(grep -rl '^export function' tests/ | tr '\n' ' ')"
else
	ok 'test fixtures use the target-compatible export syntax'
fi

# Keep workflow defaults read-only; write and OIDC permissions belong only to
# the jobs that need them.
if python3 - <<'PY'
from pathlib import Path
text = Path('.github/workflows/release.yml').read_text()
start = text.index('permissions:\n')
end = text.index('\njobs:', start)
block = text[start:end]
assert '  contents: read' in block
assert 'write' not in block
assert 'id-token:' not in block
PY
then
	ok 'release.yml keeps workflow permissions read-only'
else
	no 'release.yml keeps workflow permissions read-only' 'workflow grants broad write or OIDC permissions'
fi

# release-please opens a release PR and updates the release tag, so only that job
# gets repository and pull-request write permission.
if python3 - <<'PY'
from pathlib import Path
text = Path('.github/workflows/release.yml').read_text()
start = text.index('  release-please:\n')
end = text.index('\n  # -------------------------------------------------------------------------\n  # build', start)
block = text[start:end]
assert '    permissions:\n' in block
assert '      contents: write' in block
assert '      pull-requests: write' in block
PY
then
	ok 'release-please has its narrow write permissions'
else
	no 'release-please has its narrow write permissions' 'missing job-scoped contents/pull-requests permissions'
fi

# The build job must be read-only: it produces artifacts but has no repository,
# Pages, or OIDC write permission.
if python3 - <<'PY'
from pathlib import Path
text = Path('.github/workflows/release.yml').read_text()
start = text.index('  build:\n')
end = text.index('\n  upload-release:\n', start)
block = text[start:end]
assert '    permissions:\n' in block
assert '      contents: read' in block
assert 'contents: write' not in block
assert 'pages:' not in block
assert 'id-token:' not in block
PY
then
	ok 'build has read-only permissions'
else
	no 'build has read-only permissions' 'build has repository, Pages, or OIDC write access'
fi

# Release upload is isolated in its own contents-write job.
if python3 - <<'PY'
from pathlib import Path
text = Path('.github/workflows/release.yml').read_text()
start = text.index('  upload-release:\n')
end = text.index('\n  # The Pages site is the package repository.', start)
block = text[start:end]
assert '      contents: write' in block
assert 'actions/download-artifact@v4' in block
assert 'gh release upload' in block
PY
then
	ok 'upload-release isolates GitHub Release write access'
else
	no 'upload-release isolates GitHub Release write access' 'missing dedicated contents-write upload job'
fi

# The Pages job is the only job that needs deployment and OIDC permissions.
if python3 - <<'PY'
from pathlib import Path
text = Path('.github/workflows/release.yml').read_text()
start = text.index('  deploy-pages:\n')
block = text[start:]
assert '    permissions:\n' in block
assert '      pages: write' in block
assert '      id-token: write' in block
assert 'contents: write' not in block
assert 'pull-requests: write' not in block
PY
then
	ok 'deploy-pages has only Pages and OIDC write permissions'
else
	no 'deploy-pages has only Pages and OIDC write permissions' 'deployment job permissions are too broad'
fi

# The upload step must use the built-in token, not a custom secret: a fork has
# no such secret and would fail on the last step of a successful build.
if grep -q 'secrets.GITHUB_TOKEN' .github/workflows/release.yml; then
	if grep -qvE 'GITHUB_TOKEN' .github/workflows/release.yml ||
		! grep -qE 'secrets\.[A-Z_]+' <(grep -v 'GITHUB_TOKEN' .github/workflows/release.yml); then
		ok 'release.yml uses no secret other than GITHUB_TOKEN'
	else
		no 'release.yml uses no secret other than GITHUB_TOKEN' \
			"$(grep -oE 'secrets\.[A-Z_]+' .github/workflows/release.yml | grep -v GITHUB_TOKEN | sort -u | tr '\n' ' ')"
	fi
else
	no 'release.yml uses no secret other than GITHUB_TOKEN' 'GITHUB_TOKEN not referenced'
fi

# ---------------------------------------------------------------------------
section 'the upstream archive is verified before it is used'

# The 95 MB archive is the entire payload of airconnect-engine. A download that
# silently differs must fail the build, not ship different binaries.
HASH=$(sed -n 's/^PKG_HASH:=//p' packages/airconnect-engine/Makefile | tr -d ' \t')
if [ -n "$HASH" ]; then
	ok 'the engine recipe declares PKG_HASH'
else
	no 'the engine recipe declares PKG_HASH' 'not found'
fi
if grep -q "$HASH" .github/workflows/release.yml; then
	ok 'release.yml verifies the archive against the recipe hash'
else
	no 'release.yml verifies the archive against the recipe hash' 'hash absent from the workflow'
fi

# The workflow must fail when the digest does not match, not just print it.
if grep -q 'sha256sum -c -' .github/workflows/release.yml; then
	ok 'release.yml enforces the digest check'
else
	no 'release.yml enforces the digest check' 'no sha256sum -c'
fi

# ---------------------------------------------------------------------------
section 'release-please configuration'

for f in release-please-config.json .release-please-manifest.json; do
	if python3 -c "import json,sys; json.load(open('$f'))" 2>/dev/null; then
		ok "$f is valid JSON"
	else
		no "$f is valid JSON" 'parse error'
	fi
done

# release.yml passes --config-file/--manifest-file to the action; the files it
# names must be the ones that exist.
if grep -q 'config-file: release-please-config.json' .github/workflows/release.yml; then
	ok 'the action is pointed at release-please-config.json'
else
	no 'the action is pointed at release-please-config.json' 'not referenced'
fi
if grep -q 'manifest-file: .release-please-manifest.json' .github/workflows/release.yml; then
	ok 'the action is pointed at .release-please-manifest.json'
else
	no 'the action is pointed at .release-please-manifest.json' 'not referenced'
fi

# The config must list the manifest's root as a package, or release-please has
# nothing to version.
if python3 -c "
import json
cfg = json.load(open('release-please-config.json'))
pkgs = cfg.get('packages', {})
assert '.' in pkgs, 'root package not declared'
" 2>/dev/null; then
	ok 'the config declares the root package'
else
	no 'the config declares the root package' 'no \".\" in packages'
fi

# ---------------------------------------------------------------------------
section 'the version files agree'

# release-please bumps package.json and the Makefiles. If the manifest, the
# Makefile and package.json disagree, the next release PR is wrong before it is
# even opened.
manifest_version=$(python3 -c "
import json
print(json.load(open('.release-please-manifest.json'))['.'])
" 2>/dev/null || echo '')
pkg_version=$(python3 -c "
import json
print(json.load(open('package.json'))['version'])
" 2>/dev/null || echo '')
mgr_version=$(sed -n 's/^PKG_VERSION:=//p' packages/airconnect-manager/Makefile | tr -d ' \t' | head -1)
luci_version=$(sed -n 's/^PKG_VERSION:=//p' packages/luci-app-airconnect-manager/Makefile | tr -d ' \t' | head -1)

if [ "$manifest_version" = "$pkg_version" ] && [ -n "$manifest_version" ]; then
	ok 'manifest and package.json agree on $manifest_version'
else
	no 'manifest and package.json agree' \
		"manifest=${manifest_version} package.json=${pkg_version}"
fi

# The LuCI package depends on the backend, so their versions must match or an
# upgrade can install a mismatched pair.
if [ "$mgr_version" = "$luci_version" ] && [ -n "$mgr_version" ]; then
	ok 'manager and luci PKG_VERSION agree on $mgr_version'
else
	no 'manager and luci PKG_VERSION agree' \
		"manager=${mgr_version} luci=${luci_version}"
fi

if [ "$mgr_version" = "$pkg_version" ] && [ -n "$mgr_version" ]; then
	ok 'manager PKG_VERSION matches the repo version'
else
	no 'manager PKG_VERSION matches the repo version' \
		"makefile=${mgr_version} package.json=${pkg_version}"
fi

# airconnect-engine tracks upstream, not the repo. It must NOT be swept along by
# a repo version bump.
eng_version=$(sed -n 's/^PKG_VERSION:=//p' packages/airconnect-engine/Makefile | tr -d ' \t' | head -1)
if [ "$eng_version" != "$pkg_version" ]; then
	ok "airconnect-engine keeps the upstream version $eng_version"
else
	no 'airconnect-engine keeps the upstream version' \
		"engine PKG_VERSION=$eng_version equals the repo version"
fi

# ---------------------------------------------------------------------------
section 'the build targets are explicit'

# A matrix leg that builds for an untested target would publish a package
# nobody has run. The workflow documents which legs are live.
if grep -q 'target: armsr-armv8' .github/workflows/release.yml; then
	ok 'release.yml builds armsr-armv8'
else
	no 'release.yml builds armsr-armv8' 'missing'
fi

# x86_64 must stay commented out until it has been verified on hardware; an
# uncommented leg here is the mistake this check exists to catch.
if grep -qE '^\s*- target: x86-64' .github/workflows/release.yml; then
	no 'the x86_64 leg is still a documented placeholder' \
		'an active x86_64 leg exists; verify it on hardware first'
else
	ok 'the x86_64 leg is still a documented placeholder'
fi

# The SDK version must be a real release, never SNAPSHOT: a SNAPSHOT build is
# not compatible with the stable release it claims to target.
if grep -qE 'sdk_version: .*SNAPSHOT' .github/workflows/release.yml; then
	no 'the SDK version is not SNAPSHOT' 'found a SNAPSHOT sdk_version'
else
	ok 'the SDK version is not SNAPSHOT'
fi

# The SDK cache key must include the version, or a stale SDK silently produces
# packages for the wrong release.
if grep -q 'key: sdk-${{ matrix.target }}-${{ matrix.sdk_version }}' .github/workflows/release.yml; then
	ok 'the SDK cache key includes the version'
else
	no 'the SDK cache key includes the version' 'key does not name the version'
fi

# ---------------------------------------------------------------------------
section 'the build checks its own output'

# An empty dist/ would otherwise look like a successful release.
if grep -q 'test .*find.*dist.*-name' .github/workflows/release.yml &&
	grep -q ' -eq 4' .github/workflows/release.yml; then
	ok 'release.yml fails unless all four APKs were produced'
else
	no 'release.yml fails unless all four APKs were produced' 'no exact package-count guard'
fi

# The Actions cache retains the SDK's package output between release versions.
# Clear this project's old APKs before compiling so collection is version-local.
configure_block=$(sed -n '/name: Configure/,/name: Build/p' .github/workflows/release.yml)
if printf '%s\n' "$configure_block" | grep -q 'rm -f' &&
	printf '%s\n' "$configure_block" | grep -q 'airconnect-engine-.*apk' &&
	printf '%s\n' "$configure_block" | grep -q 'airconnect-manager-.*apk' &&
	printf '%s\n' "$configure_block" | grep -q 'luci-app-airconnect-manager-.*apk' &&
	printf '%s\n' "$configure_block" | grep -q 'luci-i18n-airconnect-manager-zh-cn-.*apk'; then
	ok 'release.yml clears cached project APKs before building'
else
	no 'release.yml clears cached project APKs before building' 'old SDK APKs can be collected'
fi

# Package inspection must use the SDK's apk-tools 3 binary. GitHub-hosted runners
# do not guarantee a system apk binary, and the SDK binary understands OpenWrt's
# APK v3 metadata.
if grep -q 'apk manifest' .github/workflows/release.yml &&
	grep -q 'SDK_HOST.*staging_dir/host/bin/apk' .github/workflows/release.yml; then
	no 'release.yml uses the SDK apk for manifest checks' 'package checks call a bare apk command'
else
	ok 'release.yml uses the SDK apk for manifest checks'
fi

# The manager package's three load-bearing files, asserted from the built APK.
for path in etc/init.d/airconnect-manager \
	usr/share/rpcd/ucode/airconnect-manager \
	etc/config/airconnect-manager; do
	if grep -q "$path" .github/workflows/release.yml; then
		ok "release.yml asserts $path is in the manager APK"
	else
		no "release.yml asserts $path is in the manager APK" 'not checked'
	fi
done

# The engine package's payload and its licence notices.
for path in usr/libexec/airconnect/airupnp \
	usr/libexec/airconnect/aircast \
	usr/share/airconnect/THIRD-PARTY-NOTICES; do
	if grep -q "$path" .github/workflows/release.yml; then
		ok "release.yml asserts $path is in the engine APK"
	else
		no "release.yml asserts $path is in the engine APK" 'not checked'
	fi
done

# ---------------------------------------------------------------------------
section 'the documented release process matches the workflow'

doc=docs/RELEASE.zh-CN.md
if [ -f "$doc" ]; then
	ok "$doc exists"
else
	no "$doc exists" 'missing'
fi

# The doc names the release-please action; if the workflow moves to a different
# action the doc must say so.
if [ -f "$doc" ]; then
	for action in 'release-please' 'build'; do
		if grep -q "$action" "$doc"; then
			ok "$doc mentions $action"
		else
			no "$doc mentions $action" 'absent from the doc'
		fi
	done
	# The doc must state that x86_64 is not built yet, matching the workflow.
	if grep -q 'x86' "$doc" && grep -qE '尚未启用|未启用|没有.*验证' "$doc"; then
		ok "$doc records that x86_64 is not built yet"
	else
		no "$doc records that x86_64 is not built yet" 'missing the caveat'
	fi
	# The doc must not promise a build path that does not exist. A hand-built
	# APK was attempted and measured to be unusable: apk-tools 3.x opens its v3
	# container with an ADBd signature block whose length is not a plain 32-bit
	# integer, and the payload is not gzip. The script was removed, so a stale
	# reference here would send someone down a dead end.
	if grep -q 'build-apk.sh' "$doc"; then
		no "$doc does not reference the removed build-apk.sh" \
			'that script was deleted; the doc still points at it'
	else
		ok "$doc does not reference the removed build-apk.sh"
	fi
	if [ -f scripts/build-apk.sh ]; then
		no 'the unusable on-device APK builder is gone' \
			'scripts/build-apk.sh still exists and produces packages apk rejects'
	else
		ok 'the unusable on-device APK builder is gone'
	fi
fi

# The LuCI translation package is generated by feeds/luci/luci.mk from the
# luci-app package's po/ directory. It has no packages/luci-i18n-* source tree,
# so the generic SDK helper must not try to copy it as an ordinary package.
if grep -q "luci-i18n-airconnect-manager-zh-cn" scripts/build-sdk.sh &&
	grep -q 'generated.*luci-i18n\|luci-i18n.*generated' scripts/build-sdk.sh; then
	ok 'build-sdk handles the generated Chinese translation package'
else
	no 'build-sdk handles the generated Chinese translation package' \
		'it would try to copy a source directory that does not exist'
fi

# ---------------------------------------------------------------------------
section 'the local build script matches the workflow'

# scripts/build-local.sh is the manual counterpart of the workflow's build job.
# If they drift, a package that builds locally can still fail in CI (or vice
# versa), and the difference is invisible until one of them runs.
local_script=scripts/build-local.sh
if [ -f "$local_script" ]; then
	ok "$local_script exists"
else
	no "$local_script exists" 'missing'
fi

if [ -f "$local_script" ]; then
	# Same SDK version as the workflow's matrix.
	wf_sdk=$(sed -n "s/^[[:space:]]*sdk_version: '\([0-9.]*\)'.*/\1/p" \
		.github/workflows/release.yml | head -1)
	ls_sdk=$(sed -n "s/^SDK_VERSION='\([0-9.]*\)'.*/\1/p" "$local_script" | head -1)
	if [ -n "$wf_sdk" ] && [ "$wf_sdk" = "$ls_sdk" ]; then
		ok "both build $wf_sdk"
	else
		no 'the local script and the workflow build the same SDK' \
			"workflow=${wf_sdk} local=${ls_sdk}"
	fi

	# Same upstream hash. A script that verifies a different hash would accept
	# an archive the recipe rejects.
	recipe_hash=$(sed -n 's/^PKG_HASH:=//p' packages/airconnect-engine/Makefile | tr -d ' \t')
	if grep -q "$recipe_hash" "$local_script"; then
		ok 'the local script verifies the recipe hash'
	else
		no 'the local script verifies the recipe hash' 'hash absent'
	fi

	# Same TLS backend selection, or the local build fails where CI succeeds.
	if grep -q 'CONFIG_LIBCURL_OPENSSL=y' "$local_script" &&
		grep -q 'CONFIG_LIBCURL_OPENSSL=y' .github/workflows/release.yml; then
		ok 'both select the curl TLS backend'
	else
		no 'both select the curl TLS backend' 'CONFIG_LIBCURL_OPENSSL differs'
	fi

	# It must build each package separately, so a failure names one package.
	for pkg in airconnect-engine airconnect-manager luci-app-airconnect-manager luci-i18n-airconnect-manager-zh-cn; do
		if grep -q "package/${pkg}/compile" "$local_script"; then
			ok "the local script builds $pkg on its own"
		else
			no "the local script builds $pkg on its own" 'not built separately'
		fi
	done

	# It must refuse to report success when nothing was produced.
	if grep -q 'expected four APKs' "$local_script" &&
		grep -q ' -eq 4' "$local_script"; then
		ok 'the local script fails unless all four APKs were produced'
	else
		no 'the local script fails unless all four APKs were produced' 'no exact package-count guard'
	fi

	# Cached SDKs retain old package files. The local build must remove this
	# project's APKs before compiling, or a later version is mixed with them.
	clear_block=$(sed -n '/Cached SDKs retain package files/,/# --- configure/p' "$local_script")
	if printf '%s\n' "$clear_block" | grep -q 'rm -f' &&
		printf '%s\n' "$clear_block" | grep -q 'airconnect-engine-.*apk' &&
		printf '%s\n' "$clear_block" | grep -q 'airconnect-manager-.*apk' &&
		printf '%s\n' "$clear_block" | grep -q 'luci-app-airconnect-manager-.*apk' &&
		printf '%s\n' "$clear_block" | grep -q 'luci-i18n-airconnect-manager-zh-cn-.*apk'; then
		ok 'the local script clears cached project APKs before building'
	else
		no 'the local script clears cached project APKs before building' 'old SDK APKs can be collected'
	fi
	if grep -q 'rm -f.*OUTPUT.*airconnect-engine-.*apk' "$local_script" ||
		grep -q 'rm -f.*"\$OUTPUT".*airconnect-engine-.*apk' "$local_script"; then
		ok 'the local script clears old project APKs from output'
	else
		no 'the local script clears old project APKs from output' 'old output APKs remain visible'
	fi

	# The reusable SDK script must apply the same stale-output protection.
	build_sdk=scripts/build-sdk.sh
	if grep -q 'find.*bin/packages' "$build_sdk" &&
		grep -q '\-delete' "$build_sdk"; then
		ok 'build-sdk clears cached APKs before each requested build'
	else
		no 'build-sdk clears cached APKs before each requested build' 'stale SDK APKs can be reported'
	fi
	if grep -q 'translation_parent=.*luci-app-airconnect-manager' "$build_sdk" &&
		grep -q 'copy_package "\$translation_parent"' "$build_sdk"; then
		ok 'build-sdk copies the LuCI parent for a standalone translation build'
	else
		no 'build-sdk copies the LuCI parent for a standalone translation build' 'generated translation has no PO source'
	fi

	# libopenssl's afalg and devcrypto engines pull in kernel/linux/compile,
	# which with CONFIG_ALL_KMODS=y cross-builds every kernel module for the
	# target. Both scripts must turn them off, exactly like scripts/build-sdk.sh,
	# or the build OOMs on a dependency that has nothing to do with this project.
	for symbol in CONFIG_PACKAGE_libopenssl-afalg CONFIG_PACKAGE_libopenssl-devcrypto; do
		if grep -q "$symbol" "$local_script" &&
			grep -q "$symbol" .github/workflows/release.yml; then
			ok "both build scripts unset $symbol"
		else
			no "both build scripts unset $symbol" 'one of them can build every kernel module'
		fi
	done

	# The package copy must refresh mtimes. The scanner skips a Makefile that is
	# not newer than its last scan stamp, and the CI cache restores tmp/ with
	# that stamp -- with `cp -a` a package silently disappears from defconfig.
	if grep -Eq '^[[:space:]]*cp -a ' "$local_script" ||
		sed -n '/Link the packages into the SDK/,/Fetch the upstream/p' .github/workflows/release.yml |
			grep -Eq '^[[:space:]]*cp -a '; then
		no 'the package copy refreshes mtimes' 'cp -a keeps the checkout mtime; the scanner then skips the package'
	else
		ok 'the package copy refreshes mtimes'
	fi

	# A dropped CONFIG_PACKAGE_* symbol must fail the run by name, not surface
	# later as "no APK" or "No rule to make target".
	if grep -q 'dropped required symbol' "$local_script" &&
		grep -q 'dropped required symbol' .github/workflows/release.yml; then
		ok 'both build scripts fail on a dropped CONFIG symbol'
	else
		no 'both build scripts fail on a dropped CONFIG symbol' 'silent drop is still possible'
	fi

	# It must be shellcheck-clean bash, or a typo only shows up mid-build.
	if command -v shellcheck >/dev/null 2>&1; then
		if shellcheck -S warning "$local_script" >/dev/null 2>&1; then
			ok 'the local script passes shellcheck'
		else
			no 'the local script passes shellcheck' \
				"$(shellcheck -S warning "$local_script" 2>&1 | head -3 | tr '\n' ' ')"
		fi
	else
		printf 'skip - shellcheck unavailable, not linting the local build script\n'
	fi

	# bash -n is always available and catches the syntax errors that matter.
	if bash -n "$local_script" 2>/dev/null; then
		ok 'the local script is syntactically valid bash'
	else
		no 'the local script is syntactically valid bash' \
			"$(bash -n "$local_script" 2>&1 | head -1)"
	fi
fi

# ---------------------------------------------------------------------------
printf '\ncheck-release: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
