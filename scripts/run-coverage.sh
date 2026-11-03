#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Run frontend core behavior suites under V8 coverage and enforce 80% per file.

set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "${here}/.." && pwd)
workdir=$(mktemp -d "${TMPDIR:-/tmp}/airconnect-coverage.XXXXXX")
trap 'rm -rf "${workdir}"' EXIT INT TERM

cd "${root}"
for suite in \
	tests/luci/run.mjs \
	tests/luci/diagnostics.mjs \
	tests/luci/core-logic.mjs \
	tests/parity/check-frontend.mjs \
	tests/performance/poll-contract.mjs; do
	printf '\n==> %s\n' "${suite}"
	NODE_V8_COVERAGE="${workdir}" node "${suite}"
done

node scripts/check-coverage.mjs "${workdir}"
