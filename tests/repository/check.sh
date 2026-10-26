#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 tzzs
#
# Static checks for the GitHub Pages APK repository publication.
#
# Usage: bash tests/repository/check.sh
# Exit status: 0 when every assertion passes, 1 otherwise.

set -u
set -o pipefail

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "${here}/../.." && pwd)
workflow="${root}/.github/workflows/release.yml"

passed=0
failed=0

ok() { passed=$((passed + 1)); printf 'ok   - %s\n' "$1"; }
no() { failed=$((failed + 1)); printf 'FAIL - %s\n       %s\n' "$1" "${2:-}"; }

for package in airconnect-engine airconnect-manager luci-app-airconnect-manager; do
	if grep -q "${package}" "${workflow}"; then
		ok "repository publication includes ${package}"
	else
		no "repository publication includes ${package}" 'package is absent from the Pages publication path'
	fi
done

if grep -q 'pages/${{ matrix.arch }}/base' "${workflow}" &&
	grep -q 'bin/packages/${{ matrix.arch }}/base' "${workflow}"; then
	ok 'repository publication uses the matrix architecture/feed layout'
else
	no 'repository publication uses the matrix architecture/feed layout' 'architecture path is hard-coded'
fi

if grep -q 'mkndx' "${workflow}" && grep -q -- '--output.*packages.adb' "${workflow}"; then
	ok 'workflow generates an APK v3 repository index'
else
	no 'workflow generates an APK v3 repository index' 'missing apk mkndx packages.adb output'
fi

if grep -q 'packages.adb' "${workflow}" && grep -q 'test -s.*packages.adb' "${workflow}"; then
	ok 'workflow publishes packages.adb'
else
	no 'workflow publishes packages.adb' 'index is not generated and checked'
fi

if grep -q 'pages/${{ matrix.arch }}/.nojekyll' "${workflow}"; then
	ok 'workflow disables Jekyll processing for the APK repository'
else
	no 'workflow disables Jekyll processing for the APK repository' 'missing .nojekyll marker'
fi

if grep -q 'actions/deploy-pages@v4' "${workflow}" &&
	grep -q 'actions/upload-pages-artifact@v3' "${workflow}" &&
	grep -q 'actions/download-artifact@v4' "${workflow}"; then
	ok 'workflow deploys the repository through GitHub Pages'
else
	no 'workflow deploys the repository through GitHub Pages' 'missing Pages artifact/deploy actions'
fi

if grep -q 'pages: write' "${workflow}" && grep -q 'id-token: write' "${workflow}" &&
	grep -q 'upload-pages-artifact@v3' "${workflow}"; then
	ok 'workflow declares Pages deployment permissions'
else
	no 'workflow declares Pages deployment permissions' 'missing pages/id-token write permissions'
fi

if grep -q 'luci-i18n-airconnect-manager-zh-cn' "${workflow}" ||
	grep -q 'luci-i18n-airconnect-manager' "${workflow}"; then
	ok 'repository publication includes the Chinese translation package'
else
	no 'repository publication includes the Chinese translation package' 'translation package is not collected'
fi

# The current workflow does not sign the repository index. The installation
# documentation must therefore show the explicit test-repository trust override.
doc="${root}/docs/RELEASE.zh-CN.md"
if grep -q '未签名测试仓库' "$doc" && grep -q 'apk --allow-untrusted update' "$doc"; then
	ok 'documentation marks the Pages repository unsigned and uses the trust override'
else
	no 'documentation marks the Pages repository unsigned and uses the trust override' \
		'missing unsigned-repository warning or apk update override'
fi

printf '\nrepository: %d passed, %d failed\n' "${passed}" "${failed}"
[ "${failed}" -eq 0 ]
