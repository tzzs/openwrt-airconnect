#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 tzzs
# Static checks for the LuCI translation package.

set -u
set -o pipefail
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "${here}/../.." && pwd)
app="${root}/packages/luci-app-airconnect-manager"
view="${app}/htdocs/luci-static/resources/view/airconnect-manager/overview.js"
pot="${app}/po/templates/airconnect-manager.pot"
po="${app}/po/zh_Hans/airconnect-manager.po"
passed=0
failed=0
ok() { passed=$((passed + 1)); printf 'ok   - %s\n' "$1"; }
no() { failed=$((failed + 1)); printf 'FAIL - %s\n       %s\n' "$1" "${2:-}"; }

if [ -f "${pot}" ]; then ok 'translation template exists'; else no 'translation template exists' 'missing POT'; fi
if [ -f "${po}" ]; then ok 'Simplified Chinese translation exists'; else no 'Simplified Chinese translation exists' 'missing PO'; fi
if [ -f "${pot}" ] && msgfmt --check --check-header -o /dev/null "${pot}" 2>/dev/null; then ok 'translation template is valid gettext syntax'; elif [ -f "${pot}" ]; then no 'translation template is valid gettext syntax' 'msgfmt rejected POT'; fi
if [ -f "${po}" ] && msgfmt --check --check-header -o /dev/null "${po}" 2>/dev/null; then ok 'Simplified Chinese translation is valid gettext syntax'; elif [ -f "${po}" ]; then no 'Simplified Chinese translation is valid gettext syntax' 'msgfmt rejected PO'; fi

if [ -f "${po}" ]; then
	if grep -q 'Language: zh_Hans' "${po}"; then ok 'translation declares zh_Hans'; else no 'translation declares zh_Hans' 'missing Language header'; fi
	if python3 - "${po}" <<'PY'
import ast
import sys
entries = []
msgid = msgstr = None
field = None
for line in open(sys.argv[1], encoding='utf-8'):
    if line.startswith('msgid '):
        if msgid is not None: entries.append((msgid, msgstr))
        msgid = ast.literal_eval(line[6:].strip()); msgstr = None; field = 'msgid'
    elif line.startswith('msgstr '):
        msgstr = ast.literal_eval(line[7:].strip()); field = 'msgstr'
    elif line.startswith('"') and field:
        value = ast.literal_eval(line.strip())
        if field == 'msgid': msgid += value
        else: msgstr += value
    elif not line.startswith('"'):
        field = None
if msgid is not None: entries.append((msgid, msgstr))
if any(item and not value for item, value in entries): sys.exit(1)
PY
	then ok 'translation has no untranslated non-header entries'; else no 'translation has no untranslated non-header entries' 'an entry has empty msgstr'; fi
fi

frontend="${app}/frontend/src"
if [ -d "${frontend}" ] && [ -f "${pot}" ]; then
	# The page text now lives in the React sources (lib/*.js, components/*.jsx)
	# and the thin LuCI loader. Together they must be covered by the POT.
	if python3 - "${frontend}" "${view}" "${pot}" <<'PY'
import ast
import os
import re
import sys
frontend, view, pot = sys.argv[1:]
pattern = re.compile(r"_\(\s*'((?:\\.|[^'\\])*)'\s*\)")
strings = set()
for base, dirs, files in os.walk(frontend):
    for name in files:
        if not name.endswith(('.js', '.jsx')):
            continue
        path = os.path.join(base, name)
        for value in pattern.findall(open(path, encoding='utf-8').read()):
            strings.add(ast.literal_eval("'" + value + "'"))
strings |= {ast.literal_eval("'" + value + "'") for value in pattern.findall(open(view, encoding='utf-8').read())}
ids = set()
current = None
field = None
for line in open(pot, encoding='utf-8'):
    if line.startswith('msgid '):
        current = ast.literal_eval(line[6:].strip()); field = 'msgid'; ids.add(current)
    elif line.startswith('msgstr '):
        current = None; field = 'msgstr'
    elif line.startswith('"') and field == 'msgid' and current is not None:
        current += ast.literal_eval(line.strip()); ids.add(current)
    elif not line.startswith('"'):
        field = None
missing = sorted(strings - ids)
if missing:
    print('missing from POT:', ', '.join(missing[:5]), file=sys.stderr); sys.exit(1)
print('all %d _() strings across the frontend are present in the POT' % len(strings))
PY
	then ok 'POT covers every _() string in the frontend'; else no 'POT covers every _() string in the frontend' 'source strings missing'; fi
fi

printf '\ni18n: %d passed, %d failed\n' "${passed}" "${failed}"
[ "${failed}" -eq 0 ]
