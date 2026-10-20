#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 tzzs
#
# Host tests for scripts/migrate-legacy.sh.
#
# The script under test runs on the router under BusyBox ash, so it is invoked
# here with plain `sh` and a sandbox root. Every absolute path the script uses
# is redirected into a throwaway tree; the real /etc, /usr/bin and docker are
# never touched. The external commands it depends on (`uci`, `docker`, the two
# init scripts) are shims in the sandbox, so the assertions inspect what the
# script asked for instead of what the host happens to have.
#
# Usage: bash tests/migration/run.sh
# Exit status: 0 when every check passes, 1 otherwise.

set -u
set -o pipefail

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "${here}/../.." && pwd)
script="${root}/scripts/migrate-legacy.sh"

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

check() { # check <description> <condition-result>
	if [ "$2" -eq 0 ]; then ok "$1"; else no "$1"; fi
}

work=$(mktemp -d "${TMPDIR:-/tmp}/airconnect-migration.XXXXXX") || {
	printf 'cannot create a temporary directory\n' >&2
	exit 1
}
# Invoked indirectly through the trap below.
# shellcheck disable=SC2329
cleanup() {
	rm -rf "${work}"
}
trap cleanup EXIT INT TERM

# --- helpers ---------------------------------------------------------------

file_mode() {
	fm=$(stat -c '%a' "$1" 2>/dev/null) || fm=''
	[ -n "${fm}" ] || fm=$(stat -f '%Lp' "$1" 2>/dev/null) || fm=''
	printf '%s' "${fm}"
}

# A recursive listing of relative path, mode and content digest. Two identical
# listings mean the tree was not modified.
tree_state() {
	(
		cd "$1" || exit 1
		find . -type f | LC_ALL=C sort | while IFS= read -r f; do
			printf '%s %s %s\n' "$f" "$(file_mode "$f")" \
				"$(shasum < "$f" | awk '{print $1}')"
		done
	)
}

digest() {
	shasum < "$1" | awk '{print $1}'
}

make_init() { # make_init <path> <name>
	cat > "$1" <<EOF
#!/bin/sh
# Fake init script for the migration test. Call logs go outside the sandbox
# root, so an assertion about "the tree did not change" is not confused by the
# test's own instrumentation.
root=\${AIRCONNECT_MIGRATE_ROOT:?}
state="\$root/var/state"
log=\${AIRCONNECT_MIGRATE_TEST_LOG:-\$root/var/state}
mkdir -p "\$state" "\$log"
printf '%s %s\n' "$2" "\${1:-}" >> "\$log/init-calls.log"
case "\${1:-}" in
	enabled) [ -f "\$state/$2.enabled" ] && exit 0; exit 1 ;;
	running) [ -f "\$state/$2.running" ] && exit 0; exit 1 ;;
	start) : > "\$state/$2.running"; : > "\$state/$2.enabled"; exit 0 ;;
	stop) rm -f "\$state/$2.running"; exit 0 ;;
	enable) : > "\$state/$2.enabled"; exit 0 ;;
	disable) rm -f "\$state/$2.enabled"; exit 0 ;;
	restart|reload) : > "\$state/$2.running"; exit 0 ;;
esac
exit 1
EOF
	chmod 0755 "$1"
}

make_uci_shim() {
	cat > "$1" <<'EOF'
#!/bin/sh
# Fake `uci` for the migration test: answers `-q get` and `-q show` for the
# legacy package from the sandbox copy of the file, and nothing else.
root=${AIRCONNECT_MIGRATE_ROOT:-}
cfg="$root/etc/config/airconnect"
if [ "${1:-}" = "-q" ]; then
	shift
fi
cmd=${1:-}
[ $# -gt 0 ] && shift

option_value() {
	sed -n "s/^[[:space:]]*option[[:space:]][[:space:]]*$1[[:space:]][[:space:]]*'\(.*\)'[[:space:]]*\$/\1/p" "$cfg" | head -n 1
}

case "$cmd" in
	get)
		key=${1:-}
		pkg=${key%%.*}
		rest=${key#*.}
		sec=${rest%%.*}
		opt=${rest#*.}
		[ "$pkg" = airconnect ] || exit 1
		[ "$sec" = main ] || exit 1
		[ -f "$cfg" ] || exit 1
		value=$(option_value "$opt")
		[ -n "$value" ] || exit 1
		printf '%s\n' "$value"
		exit 0
		;;
	show)
		[ -f "$cfg" ] || exit 1
		sed -n "s/^[[:space:]]*option[[:space:]][[:space:]]*\([A-Za-z0-9_]*\)[[:space:]][[:space:]]*'\(.*\)'[[:space:]]*\$/${1:-airconnect}.main.\1='\2'/p" "$cfg"
		exit 0
		;;
esac
exit 1
EOF
	chmod 0755 "$1"
}

make_docker_shim() {
	cat > "$1" <<'EOF'
#!/bin/sh
# Fake `docker` for the migration test. `stop` marks a container stopped but
# keeps it, exactly like the real command: the test asserts it is never removed.
root=${AIRCONNECT_MIGRATE_ROOT:?}
state="$root/var/state"
log=${AIRCONNECT_MIGRATE_TEST_LOG:-$state}
mkdir -p "$state" "$log"
printf '%s\n' "${1:-}" >> "$log/docker-calls.log"
list="$state/containers"

case "${1:-}" in
	ps)
		shift
		all=0
		format=''
		while [ $# -gt 0 ]; do
			case "$1" in
				-a) all=1 ;;
				--format) shift; format=${1:-} ;;
			esac
			shift
		done
		[ -f "$list" ] || exit 0
		if [ "$format" = '{{.Names}}' ]; then
			awk -v all="$all" 'all == 1 || $3 == "running" { print $1 }' "$list"
		elif [ "$all" = 1 ]; then
			awk '{ print $1 "|" $2 }' "$list"
		else
			awk '$3 == "running" { print $1 "|" $2 }' "$list"
		fi
		exit 0
		;;
	stop)
		name=${2:-}
		awk -v n="$name" '$1 == n && $3 == "running" { found = 1 } END { exit found ? 0 : 1 }' "$list" || exit 1
		awk -v n="$name" 'BEGIN { OFS = " " } $1 == n { $3 = "stopped" } { print }' "$list" > "$list.tmp"
		mv "$list.tmp" "$list"
		exit 0
		;;
	start)
		name=${2:-}
		awk -v n="$name" '$1 == n { found = 1 } END { exit found ? 0 : 1 }' "$list" || exit 1
		awk -v n="$name" 'BEGIN { OFS = " " } $1 == n { $3 = "running" } { print }' "$list" > "$list.tmp"
		mv "$list.tmp" "$list"
		exit 0
		;;
esac
exit 1
EOF
	chmod 0755 "$1"
}

# --- sandbox ---------------------------------------------------------------

# The legacy configuration deliberately uses the alternate key spellings the
# old package allowed, plus a speaker name and an address that must never be
# copied into a device section. All values are synthetic (RFC 5737 address,
# uuid:demo-* UDN).
write_legacy_config() {
	cat > "$1" <<'EOF'
config airconnect 'main'
	option enabled '1'
	option iface 'br-lan'
	option upnp '1'
	option cast '1'
	option max_volume '30'
	option udn 'uuid:demo-speaker-0001'
	option name 'Demo Speaker'
	option address '192.0.2.10'
EOF
}

make_sandbox() { # make_sandbox <name>
	SB="${work}/$1"
	mkdir -p "${SB}/etc/config" "${SB}/etc/init.d" "${SB}/usr/bin" "${SB}/bin" "${SB}/var/state"
	write_legacy_config "${SB}/etc/config/airconnect"
	cp "${root}/packages/airconnect-manager/files/etc/config/airconnect-manager" \
		"${SB}/etc/config/airconnect-manager"
	make_init "${SB}/etc/init.d/airconnect" 'airconnect'
	make_init "${SB}/etc/init.d/airconnect-manager" 'airconnect-manager'
	make_uci_shim "${SB}/bin/uci"
	make_docker_shim "${SB}/bin/docker"
	# The legacy service starts out enabled at boot and running.
	: > "${SB}/var/state/airconnect.enabled"
	: > "${SB}/var/state/airconnect.running"
	# One legacy container plus an unrelated one that must be left alone.
	cat > "${SB}/var/state/containers" <<'EOF'
airconnect-legacy demo/airconnect:1.12.4 running
unrelated-web demo/web:1.0 running
EOF
}

# Run the script with the sandbox environment. Extra arguments are passed on.
# Shim call logs are written under ${work}/logs so that a checksum of the
# sandbox tree only reflects what the script under test did.
run_script() { # run_script <sandbox> [args...]
	RS_SB="$1"
	shift
	RS_LOG="${work}/logs/${RS_SB##*/}"
	mkdir -p "${RS_LOG}"
	(
		cd "${root}" || exit 1
		AIRCONNECT_MIGRATE_ROOT="${RS_SB}" \
			AIRCONNECT_MIGRATE_TEST_LOG="${RS_LOG}" \
			PATH="${RS_SB}/bin:${PATH}" \
			sh "${script}" "$@"
	) 2>&1
}

# The shim call log for the sandbox used by the last run_script call.
shim_log() { # shim_log <sandbox> <file>
	printf '%s/%s/%s' "${work}/logs" "${1##*/}" "$2"
}

# --- (0) static checks -----------------------------------------------------

section 'static checks'
if sh -n "${script}"; then
	ok 'sh -n scripts/migrate-legacy.sh'
else
	no 'sh -n scripts/migrate-legacy.sh' 'syntax error'
fi
if command -v dash >/dev/null 2>&1; then
	if dash -n "${script}"; then
		ok 'dash -n scripts/migrate-legacy.sh (POSIX parser)'
	else
		no 'dash -n scripts/migrate-legacy.sh (POSIX parser)' 'syntax error'
	fi
else
	printf 'skip - dash is not installed\n'
fi
if command -v busybox >/dev/null 2>&1; then
	if busybox ash -n "${script}"; then
		ok 'busybox ash -n scripts/migrate-legacy.sh'
	else
		no 'busybox ash -n scripts/migrate-legacy.sh' 'syntax error'
	fi
else
	printf 'skip - busybox is not installed\n'
fi
if head -1 "${script}" | grep -qx '#!/bin/sh'; then
	ok 'the script uses a POSIX #!/bin/sh shebang'
else
	no 'the script uses a POSIX #!/bin/sh shebang' 'wrong shebang'
fi
for forbidden in 'eval ' 'rm -rf' 'docker rm' 'opkg remove' 'apk del' '[[ ' 'sed -i'; do
	if grep -Fq -- "${forbidden}" "${script}"; then
		no "the script contains no '${forbidden}'" 'forbidden construct'
	else
		ok "the script contains no '${forbidden}'"
	fi
done
if grep -Eq '^set -u$' "${script}"; then
	ok 'the script sets -u'
else
	no 'the script sets -u' 'unset variables must be an error'
fi

# --- (1) default invocation modifies nothing -------------------------------

section 'default invocation (no flag) modifies nothing'
make_sandbox default
before=$(tree_state "${SB}")
output=$(run_script "${SB}")
status=$?
after=$(tree_state "${SB}")
check 'default invocation exits 0' "${status}"
if printf '%s' "${output}" | grep -q 'dry run: no files were changed'; then
	ok 'default invocation reports that nothing was changed'
else
	no 'default invocation reports that nothing was changed' "$(printf '%s' "${output}" | tail -3)"
fi
if [ "${before}" = "${after}" ]; then
	ok 'default invocation leaves the tree byte-identical'
else
	no 'default invocation leaves the tree byte-identical' "$(diff <(printf '%s\n' "${before}") <(printf '%s\n' "${after}") | head -5)"
fi
if printf '%s' "${output}" | grep -q 'airconnect.main.enabled=1 -> airconnect-manager.main.enabled=1'; then
	ok 'the default mode still prints the mapping'
else
	no 'the default mode still prints the mapping' 'no mapping line'
fi
if printf '%s' "${output}" | grep -q 'legacy: docker container .airconnect-legacy.'; then
	ok 'the default mode detects the Docker container'
else
	no 'the default mode detects the Docker container' 'no container line'
fi
if [ -f "${SB}/var/state/airconnect.running" ]; then
	ok 'the default mode does not stop the legacy service'
else
	no 'the default mode does not stop the legacy service' 'the running marker was removed'
fi
if grep -qx 'stop' "$(shim_log "${SB}" docker-calls.log)" 2>/dev/null; then
	no 'the default mode does not stop a container' 'docker stop was called'
else
	ok 'the default mode does not stop a container'
fi

# --- (2) --dry-run prints the mapping and modifies nothing -----------------

section '--dry-run prints the mapping and modifies nothing'
make_sandbox dryrun
before=$(tree_state "${SB}")
output=$(run_script "${SB}" --dry-run)
status=$?
after=$(tree_state "${SB}")
check '--dry-run exits 0' "${status}"
if [ "${before}" = "${after}" ]; then
	ok '--dry-run leaves the tree byte-identical'
else
	no '--dry-run leaves the tree byte-identical' 'the tree changed'
fi
for expected in \
	'airconnect.main.enabled=1 -> airconnect-manager.main.enabled=1' \
	'airconnect.main.iface=br-lan -> airconnect-manager.main.interface=br-lan' \
	'airconnect.main.upnp=1 -> airconnect-manager.main.airupnp=1' \
	'airconnect.main.cast=1 -> airconnect-manager.main.aircast=1' \
	'airconnect.main.max_volume=30 -> airconnect-manager.device_legacy.max_volume=30'
do
	if printf '%s' "${output}" | grep -Fq -- "${expected}"; then
		ok "mapping line: ${expected}"
	else
		no "mapping line: ${expected}" 'missing'
	fi
done
if printf '%s' "${output}" | grep -q 'dry run: no files were changed'; then
	ok '--dry-run says it changed nothing'
else
	no '--dry-run says it changed nothing' 'missing final line'
fi
if [ -d "${SB}/etc/airconnect-manager-backup" ]; then
	no '--dry-run creates no backup directory' 'a backup directory exists'
else
	ok '--dry-run creates no backup directory'
fi

section '--dry-run reports the mode --apply would use'
make_sandbox drymode
chmod 0640 "${SB}/etc/config/airconnect-manager"
output=$(run_script "${SB}" --dry-run)
status=$?
check 'the dry-run mode fixture exits 0' "${status}"
if printf '%s' "${output}" | grep -q 'write .*airconnect-manager with the values above (mode 640)'; then
	ok '--dry-run names the existing file mode'
else
	no '--dry-run names the existing file mode' "$(printf '%s' "${output}" | grep 'with the values above')"
fi
output=$(run_script "${SB}" --apply)
status=$?
check 'the dry-run mode fixture applies' "${status}"
mode=$(file_mode "${SB}/etc/config/airconnect-manager")
if [ "${mode}" = '640' ]; then
	ok '--apply keeps the existing file mode instead of inventing one'
else
	no '--apply keeps the existing file mode instead of inventing one' "mode is ${mode}"
fi
output=$(run_script "${SB}" --rollback)
status=$?
check 'the dry-run mode fixture rolls back' "${status}"
mode=$(file_mode "${SB}/etc/config/airconnect-manager")
if [ "${mode}" = '640' ]; then
	ok '--rollback restores the original file mode'
else
	no '--rollback restores the original file mode' "mode is ${mode}"
fi

# --- (2b) skipped values are reported, never guessed ----------------------

section 'invalid legacy values are skipped, not guessed'
make_sandbox skipvals
cat > "${SB}/etc/config/airconnect" <<'EOF'
config airconnect 'main'
	option enabled '1'
	option binding 'br-lan'
	option upnp '1'
	option aircast '0'
	option max_volume '999'
	option udn 'not-a-udn'
EOF
before=$(tree_state "${SB}")
output=$(run_script "${SB}" --dry-run)
status=$?
after=$(tree_state "${SB}")
check 'the skip fixture exits 0' "${status}"
if [ "${before}" = "${after}" ]; then
	ok 'the skip fixture is not modified'
else
	no 'the skip fixture is not modified' 'the tree changed'
fi
for expected in \
	'airconnect.main.binding=br-lan -> airconnect-manager.main.interface=br-lan' \
	'airconnect.main.max_volume=999 -> skipped (expected an integer 1..100)' \
	'airconnect.main.udn=not-a-udn -> skipped (not a uuid: UDN of at most 255 bytes)'
do
	if printf '%s' "${output}" | grep -Fq -- "${expected}"; then
		ok "skip line: ${expected}"
	else
		no "skip line: ${expected}" 'missing'
	fi
done
if printf '%s' "${output}" | grep -q 'main.max_volume=100 (no UDN found'; then
	no 'an invalid volume does not become the global limit' 'it was mapped anyway'
else
	ok 'an invalid volume does not become the global limit'
fi

# --- (2c) a legacy file without a UDN -------------------------------------

section 'a volume limit without a UDN becomes the global limit'
make_sandbox noudn
cat > "${SB}/etc/config/airconnect" <<'EOF'
config airconnect 'main'
	option enabled '1'
	option upnp '1'
	option max_volume '40'
	option name 'Demo Speaker'
	option address '192.0.2.11'
EOF
packaged_mode=$(file_mode "${root}/packages/airconnect-manager/files/etc/config/airconnect-manager")
output=$(run_script "${SB}" --apply)
status=$?
check 'the no-UDN --apply exits 0' "${status}"
if grep -Fq "option max_volume '40'" "${SB}/etc/config/airconnect-manager" &&
	! grep -Fq "option max_volume '100'" "${SB}/etc/config/airconnect-manager"; then
	ok 'the limit lands in main.max_volume'
else
	no 'the limit lands in main.max_volume' "$(cat "${SB}/etc/config/airconnect-manager")"
fi
if grep -Fq 'config device' "${SB}/etc/config/airconnect-manager"; then
	no 'no device section is invented without a UDN' 'a device section was written'
else
	ok 'no device section is invented without a UDN'
fi
if printf '%s' "${output}" | grep -q 'no UDN found; per-device attribution needs a scan'; then
	ok 'the report says per-device attribution needs a scan'
else
	no 'the report says per-device attribution needs a scan' 'missing'
fi
if grep -Fq '192.0.2.11' "${SB}/etc/config/airconnect-manager" ||
	grep -Fq 'Demo Speaker' "${SB}/etc/config/airconnect-manager"; then
	no 'the address and name are never used as a device identity' 'they appear in the new file'
else
	ok 'the address and name are never used as a device identity'
fi
mode=$(file_mode "${SB}/etc/config/airconnect-manager")
if [ "${mode}" = "${packaged_mode}" ]; then
	ok 'the generated configuration keeps the packaged conffile mode'
else
	no 'the generated configuration keeps the packaged conffile mode' "mode is ${mode}"
fi

# --- (2d) a minimal legacy file (most keys absent) ------------------------

section 'a legacy file with almost every key absent'
make_sandbox minimal
cat > "${SB}/etc/config/airconnect" <<'EOF'
config airconnect 'main'
	option upnp '1'
EOF
before=$(tree_state "${SB}")
output=$(run_script "${SB}" --dry-run)
status=$?
after=$(tree_state "${SB}")
check 'the minimal fixture exits 0' "${status}"
if [ "${before}" = "${after}" ]; then
	ok 'the minimal fixture is not modified by --dry-run'
else
	no 'the minimal fixture is not modified by --dry-run' 'the tree changed'
fi
for expected in \
	'airconnect.main.enabled=(absent) -> airconnect-manager.main.enabled=1 (the legacy service is enabled at boot or running)' \
	'airconnect.main.interface=(absent) -> airconnect-manager.main.interface=br-lan (default)' \
	'airconnect.main.aircast=(absent) -> airconnect-manager.main.aircast=0 (default)' \
	'airconnect.main.max_volume=(absent) -> airconnect-manager.main.max_volume=100 (default)'
do
	if printf '%s' "${output}" | grep -Fq -- "${expected}"; then
		ok "absent-key line: ${expected}"
	else
		no "absent-key line: ${expected}" 'missing'
	fi
done

# --- (2e) a disabled legacy service stays disabled ------------------------

section 'a disabled legacy service is not silently enabled'
make_sandbox disabled
rm -f "${SB}/var/state/airconnect.enabled" "${SB}/var/state/airconnect.running"
cat > "${SB}/etc/config/airconnect" <<'EOF'
config airconnect 'main'
	option upnp '1'
EOF
output=$(run_script "${SB}" --apply)
status=$?
check 'the disabled-legacy --apply exits 0' "${status}"
if grep -Fq "option enabled '0'" "${SB}/etc/config/airconnect-manager"; then
	ok 'the migrated service is disabled, matching the legacy service'
else
	no 'the migrated service is disabled, matching the legacy service' "$(cat "${SB}/etc/config/airconnect-manager")"
fi
if printf '%s' "${output}" | grep -q 'the legacy service is not enabled and not running'; then
	ok 'the report explains why enabled is 0'
else
	no 'the report explains why enabled is 0' 'missing'
fi
if grep -qx 'airconnect-manager start' "$(shim_log "${SB}" init-calls.log)" 2>/dev/null; then
	no 'a disabled migration never starts the new service' 'the manager was started'
else
	ok 'a disabled migration never starts the new service'
fi

# --- (2f) the Docker-only and old-binary-only cases ----------------------

section 'a Docker-only installation is detected without a legacy UCI file'
make_sandbox dockeronly
rm -f "${SB}/etc/config/airconnect" "${SB}/etc/init.d/airconnect"
rm -f "${SB}/var/state/airconnect.enabled" "${SB}/var/state/airconnect.running"
dockeronly_target_before=$(digest "${SB}/etc/config/airconnect-manager")
output=$(run_script "${SB}" --apply)
status=$?
check 'the Docker-only --apply exits 0' "${status}"
if printf '%s' "${output}" | grep -q 'docker container .airconnect-legacy.'; then
	ok 'the Docker-only case reports the container'
else
	no 'the Docker-only case reports the container' 'missing'
fi
if grep -q 'airconnect-legacy demo/airconnect:1.12.4 stopped' "${SB}/var/state/containers"; then
	ok 'the Docker-only case stops the container and keeps it'
else
	no 'the Docker-only case stops the container and keeps it' "$(cat "${SB}/var/state/containers")"
fi
if [ -d "${SB}/etc/airconnect-manager-backup" ]; then
	ok 'the Docker-only case still writes a backup record'
else
	no 'the Docker-only case still writes a backup record' 'no backup directory'
fi
if [ "$(digest "${SB}/etc/config/airconnect-manager")" = "${dockeronly_target_before:-$(digest "${root}/packages/airconnect-manager/files/etc/config/airconnect-manager")}" ]; then
	ok 'the Docker-only case leaves the manager configuration unchanged'
else
	no 'the Docker-only case leaves the manager configuration unchanged' 'the file changed'
fi
output=$(run_script "${SB}" --rollback)
status=$?
check 'the Docker-only --rollback exits 0' "${status}"
if grep -q 'airconnect-legacy demo/airconnect:1.12.4 running' "${SB}/var/state/containers"; then
	ok 'the Docker-only --rollback starts the container again'
else
	no 'the Docker-only --rollback starts the container again' "$(cat "${SB}/var/state/containers")"
fi

section 'an old /usr/bin layout without a UCI file is reported, never removed'
make_sandbox oldbins
rm -f "${SB}/etc/config/airconnect" "${SB}/etc/init.d/airconnect"
# Isolate the third detection source: no container either.
rm -f "${SB}/var/state/containers"
: > "${SB}/usr/bin/airupnp"
before_binary=$(digest "${SB}/usr/bin/airupnp")
output=$(run_script "${SB}" --apply)
status=$?
if [ "${status}" -ne 0 ]; then
	ok 'an old-binary-only --apply exits nonzero'
else
	no 'an old-binary-only --apply exits nonzero' 'it succeeded'
fi
if printf '%s' "${output}" | grep -q 'this script never removes packages'; then
	ok 'the refusal explains that packages are removed manually'
else
	no 'the refusal explains that packages are removed manually' "$(printf '%s' "${output}" | tail -2)"
fi
if [ -f "${SB}/usr/bin/airupnp" ] && [ "$(digest "${SB}/usr/bin/airupnp")" = "${before_binary}" ]; then
	ok 'the old binary is left untouched'
else
	no 'the old binary is left untouched' 'it was removed or modified'
fi

# --- (3) --apply ----------------------------------------------------------

section '--apply writes the mapped configuration and stops the legacy instance'
make_sandbox apply
legacy_before=$(digest "${SB}/etc/config/airconnect")
target_before=$(digest "${SB}/etc/config/airconnect-manager")
output=$(run_script "${SB}" --apply)
status=$?
check '--apply exits 0' "${status}"

expected_config="$(cat <<'EOF'
enabled=1
interface=br-lan
airupnp=1
aircast=1
codec=flac
latency=1000:2000
max_volume=100
media_volume=0.5
log_level=warn
EOF
)"
actual_config=$(
	awk '
		BEGIN { inside = 0 }
		/^[[:space:]]*#/ { next }
		/^[[:space:]]*$/ { next }
		/^config main/ { inside = 1; next }
		/^config/ { inside = 0; next }
		inside && /^[[:space:]]*option[[:space:]]/ {
			line = $0
			sub(/^[[:space:]]*option[[:space:]]+/, "", line)
			name = line
			sub(/[[:space:]].*$/, "", name)
			value = line
			sub(/^[^[:space:]]+[[:space:]]+/, "", value)
			gsub(/'"'"'/, "", value)
			printf "%s=%s\n", name, value
		}
	' "${SB}/etc/config/airconnect-manager"
)
if [ "${actual_config}" = "${expected_config}" ]; then
	ok 'the new main section carries exactly the mapped options'
else
	no 'the new main section carries exactly the mapped options' \
		"$(printf '%s' "${actual_config}" | tr '\n' ' ')"
fi

device_section=$(
	awk '
		/^config device/ { inside = 1; next }
		inside && /^config/ { inside = 0 }
		inside && /^[[:space:]]*option/ { print }
	' "${SB}/etc/config/airconnect-manager"
)
if printf '%s\n' "${device_section}" | grep -Fq "option udn 'uuid:demo-speaker-0001'"; then
	ok 'the device section is keyed by the legacy UDN'
else
	no 'the device section is keyed by the legacy UDN' "${device_section}"
fi
if printf '%s\n' "${device_section}" | grep -Fq "option max_volume '30'"; then
	ok 'the legacy volume limit becomes the device max_volume'
else
	no 'the legacy volume limit becomes the device max_volume' "${device_section}"
fi
if printf '%s\n' "${device_section}" | grep -Eq "option (name|address)"; then
	no 'no speaker name or address is written to the device section' "${device_section}"
else
	ok 'no speaker name or address is written to the device section'
fi
if grep -Fq '192.0.2.10' "${SB}/etc/config/airconnect-manager"; then
	no 'the legacy address is not copied anywhere' 'the address appears in the new file'
else
	ok 'the legacy address is not copied anywhere'
fi
if grep -Fq 'Demo Speaker' "${SB}/etc/config/airconnect-manager"; then
	no 'the legacy speaker name is not copied anywhere' 'the name appears in the new file'
else
	ok 'the legacy speaker name is not copied anywhere'
fi

backup_dirs=$(find "${SB}/etc/airconnect-manager-backup" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
if [ "${backup_dirs}" = '1' ]; then
	ok '--apply creates exactly one backup directory'
else
	no '--apply creates exactly one backup directory' "found ${backup_dirs}"
fi
backup_dir=$(find "${SB}/etc/airconnect-manager-backup" -mindepth 1 -maxdepth 1 -type d)
if [ -f "${backup_dir}/manifest.txt" ]; then
	ok 'the backup has a manifest.txt'
else
	no 'the backup has a manifest.txt' 'missing'
fi
if [ -f "${backup_dir}/etc/config/airconnect" ] &&
	[ "$(digest "${backup_dir}/etc/config/airconnect")" = "${legacy_before}" ]; then
	ok 'the backup holds the original legacy configuration byte for byte'
else
	no 'the backup holds the original legacy configuration byte for byte' 'missing or different'
fi
if [ -f "${backup_dir}/etc/config/airconnect-manager" ] &&
	[ "$(digest "${backup_dir}/etc/config/airconnect-manager")" = "${target_before}" ]; then
	ok 'the backup holds the previous airconnect-manager configuration'
else
	no 'the backup holds the previous airconnect-manager configuration' 'missing or different'
fi
if grep -Eq '^file=etc/config/airconnect mode=[0-7]{3,4}$' "${backup_dir}/manifest.txt" &&
	grep -Eq '^file=etc/config/airconnect-manager mode=[0-7]{3,4}$' "${backup_dir}/manifest.txt"; then
	ok 'the manifest lists both originals with their modes'
else
	no 'the manifest lists both originals with their modes' "$(cat "${backup_dir}/manifest.txt")"
fi
if grep -Fq 'docker_container=airconnect-legacy' "${backup_dir}/manifest.txt"; then
	ok 'the manifest records the stopped container for rollback'
else
	no 'the manifest records the stopped container for rollback' 'missing docker_container line'
fi
if [ "$(digest "${SB}/etc/config/airconnect")" = "${legacy_before}" ]; then
	ok 'the legacy configuration file is not modified'
else
	no 'the legacy configuration file is not modified' 'the legacy file changed'
fi
if [ -f "${SB}/var/state/airconnect.running" ]; then
	no 'the legacy service is stopped' 'the running marker still exists'
else
	ok 'the legacy service is stopped'
fi
if [ -f "${SB}/var/state/airconnect.enabled" ]; then
	no 'the legacy service is disabled at boot' 'the enabled marker still exists'
else
	ok 'the legacy service is disabled at boot'
fi
if grep -qx 'airconnect stop' "$(shim_log "${SB}" init-calls.log)" 2>/dev/null; then
	ok 'the legacy init script was asked to stop'
else
	no 'the legacy init script was asked to stop' 'no stop call'
fi
if grep -qx 'airconnect-manager start' "$(shim_log "${SB}" init-calls.log)" 2>/dev/null; then
	no 'the new service is never started by --apply' 'the manager was started'
else
	ok 'the new service is never started by --apply'
fi
if grep -Eq '^(rm|rmi|kill|prune)$' "$(shim_log "${SB}" docker-calls.log)" 2>/dev/null; then
	no 'no destructive docker subcommand is used' "$(cat "$(shim_log "${SB}" docker-calls.log)")"
else
	ok 'no destructive docker subcommand is used'
fi
if grep -q 'airconnect-legacy demo/airconnect:1.12.4 stopped' "${SB}/var/state/containers"; then
	ok 'the legacy container is stopped but still present'
else
	no 'the legacy container is stopped but still present' "$(cat "${SB}/var/state/containers")"
fi
if grep -q 'unrelated-web demo/web:1.0 running' "${SB}/var/state/containers"; then
	ok 'an unrelated container is left alone'
else
	no 'an unrelated container is left alone' "$(cat "${SB}/var/state/containers")"
fi
if [ -x "${SB}/etc/init.d/airconnect" ]; then
	ok 'the old init script is not removed'
else
	no 'the old init script is not removed' 'it disappeared'
fi
apply_backup_dir="${backup_dir}"

# --- (3b) the generated file is accepted by the real validator ------------

section 'the generated file validates and renders through config.uc'
ucode_bin=''
if [ -n "${UCODE:-}" ] && [ -x "${UCODE}" ]; then
	ucode_bin="${UCODE}"
elif [ -x "${HOME:-}/.local/opt/ucode-host/bin/ucode" ]; then
	ucode_bin="${HOME}/.local/opt/ucode-host/bin/ucode"
elif command -v ucode >/dev/null 2>&1; then
	ucode_bin=$(command -v ucode)
fi
if [ -z "${ucode_bin}" ]; then
	printf 'skip - no ucode interpreter, so the generated file is not cross-checked\n'
else
	ucode_lib="${HOME:-}/.local/opt/ucode-host/lib/ucode"
	if [ -d "${ucode_lib}" ]; then
		validator_output=$("${ucode_bin}" -L "${ucode_lib}" "${here}/validate.uc" \
			"${SB}/etc/config/airconnect-manager" 2>&1)
	else
		validator_output=$("${ucode_bin}" "${here}/validate.uc" \
			"${SB}/etc/config/airconnect-manager" 2>&1)
	fi
	status=$?
	if [ "${status}" -eq 0 ]; then
		ok 'the generated file passes normalizeConfig'
	else
		no 'the generated file passes normalizeConfig' "${validator_output}"
	fi
	if printf '%s' "${validator_output}" | grep -q 'upnp=1 cast=1 interface=br-lan devices=1'; then
		ok 'the validator sees the mapped values'
	else
		no 'the validator sees the mapped values' "${validator_output}"
	fi
	if printf '%s' "${validator_output}" | grep -q 'device: engine=upnp udn=uuid:demo-speaker-0001 max_volume=30'; then
		ok 'the validator sees the migrated device override'
	else
		no 'the validator sees the migrated device override' "${validator_output}"
	fi
	if printf '%s' "${validator_output}" | grep -q '^upnp: rendered ' &&
		printf '%s' "${validator_output}" | grep -q '^cast: rendered '; then
		ok 'both enabled engines render XML from the generated file'
	else
		no 'both enabled engines render XML from the generated file' "${validator_output}"
	fi
fi

# --- (4) --rollback restores the original bytes ---------------------------

section '--rollback restores the original bytes exactly'
output=$(run_script "${SB}" --rollback)
status=$?
check '--rollback exits 0' "${status}"
if [ "$(digest "${SB}/etc/config/airconnect")" = "${legacy_before}" ]; then
	ok 'the legacy configuration is restored byte for byte'
else
	no 'the legacy configuration is restored byte for byte' 'different bytes'
fi
if [ "$(digest "${SB}/etc/config/airconnect-manager")" = "${target_before}" ]; then
	ok 'the airconnect-manager configuration is restored byte for byte'
else
	no 'the airconnect-manager configuration is restored byte for byte' 'different bytes'
fi
if [ -f "${SB}/var/state/airconnect.enabled" ] && [ -f "${SB}/var/state/airconnect.running" ]; then
	ok 'the legacy service is enabled and running again'
else
	no 'the legacy service is enabled and running again' 'state markers missing'
fi
if [ -f "${apply_backup_dir}/rolled-back" ]; then
	ok 'the backup is marked rolled back'
else
	no 'the backup is marked rolled back' 'no rolled-back marker'
fi
if [ -d "${apply_backup_dir}" ]; then
	ok 'the backup directory is kept for audit'
else
	no 'the backup directory is kept for audit' 'it was deleted'
fi
output=$(run_script "${SB}" --rollback)
status=$?
check 'a second --rollback exits 0' "${status}"
if printf '%s' "${output}" | grep -q 'nothing to roll back'; then
	ok 'a second --rollback is a no-op'
else
	no 'a second --rollback is a no-op' "$(printf '%s' "${output}" | tail -2)"
fi
if [ "$(digest "${SB}/etc/config/airconnect")" = "${legacy_before}" ]; then
	ok 'a second --rollback changes nothing'
else
	no 'a second --rollback changes nothing' 'the file changed'
fi

# --- (5) a second --apply refuses -----------------------------------------

section 'a second --apply without --rollback refuses'
make_sandbox twice
output=$(run_script "${SB}" --apply)
status=$?
check 'the first --apply exits 0' "${status}"
first_config=$(digest "${SB}/etc/config/airconnect-manager")
output=$(run_script "${SB}" --apply)
status=$?
if [ "${status}" -ne 0 ]; then
	ok 'the second --apply exits nonzero'
else
	no 'the second --apply exits nonzero' 'it succeeded'
fi
if printf '%s' "${output}" | grep -q 'a previous --apply is still in effect'; then
	ok 'the second --apply explains why it refuses'
else
	no 'the second --apply explains why it refuses' "$(printf '%s' "${output}" | tail -2)"
fi
if [ "$(digest "${SB}/etc/config/airconnect-manager")" = "${first_config}" ]; then
	ok 'the second --apply leaves the migrated configuration untouched'
else
	no 'the second --apply leaves the migrated configuration untouched' 'the file changed'
fi
backup_dirs=$(find "${SB}/etc/airconnect-manager-backup" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
if [ "${backup_dirs}" = '1' ]; then
	ok 'the refused second --apply creates no second backup'
else
	no 'the refused second --apply creates no second backup' "found ${backup_dirs}"
fi
if [ -f "${SB}/var/state/airconnect.running" ]; then
	no 'the refused second --apply does not restart the legacy service' 'it is running'
else
	ok 'the refused second --apply does not restart the legacy service'
fi

# --- (6) an existing backup directory is never overwritten -----------------

section 'an existing backup directory is never overwritten'
make_sandbox collide
cat > "${SB}/bin/date" <<'EOF'
#!/bin/sh
# Fixed clock so two runs in the same test land on the same backup name.
printf '20260101T000000Z\n'
EOF
chmod 0755 "${SB}/bin/date"
output=$(run_script "${SB}" --apply)
status=$?
check 'the first --apply with a fixed clock exits 0' "${status}"
output=$(run_script "${SB}" --rollback)
status=$?
check 'the rollback with a fixed clock exits 0' "${status}"
sentinel="${SB}/etc/airconnect-manager-backup/20260101T000000Z/sentinel"
: > "${sentinel}"
output=$(run_script "${SB}" --apply)
status=$?
if [ "${status}" -ne 0 ]; then
	ok 'a colliding --apply exits nonzero'
else
	no 'a colliding --apply exits nonzero' 'it succeeded'
fi
if printf '%s' "${output}" | grep -q 'refusing to overwrite the existing backup directory'; then
	ok 'a colliding --apply says it refuses to overwrite the backup'
else
	no 'a colliding --apply says it refuses to overwrite the backup' "$(printf '%s' "${output}" | tail -2)"
fi
if [ -f "${sentinel}" ]; then
	ok 'the existing backup directory is untouched'
else
	no 'the existing backup directory is untouched' 'the sentinel was removed'
fi

# --- (7) --force-stop-new -------------------------------------------------

section 'a running new service is a hard stop unless --force-stop-new'
make_sandbox running
: > "${SB}/var/state/airconnect-manager.running"
output=$(run_script "${SB}" --apply)
status=$?
if [ "${status}" -ne 0 ]; then
	ok '--apply refuses while the new service runs'
else
	no '--apply refuses while the new service runs' 'it succeeded'
fi
if printf '%s' "${output}" | grep -q 'two AirPlay broadcasters'; then
	ok 'the refusal explains the double-broadcast risk'
else
	no 'the refusal explains the double-broadcast risk' "$(printf '%s' "${output}" | tail -2)"
fi
if [ -d "${SB}/etc/airconnect-manager-backup" ]; then
	no 'a refused --apply writes no backup' 'a backup directory exists'
else
	ok 'a refused --apply writes no backup'
fi
output=$(run_script "${SB}" --apply --force-stop-new)
status=$?
check '--apply --force-stop-new exits 0' "${status}"
if [ -f "${SB}/var/state/airconnect-manager.running" ]; then
	no '--force-stop-new stops the new service' 'it is still running'
else
	ok '--force-stop-new stops the new service'
fi

# --- (8) refuses to run without root and without a sandbox -----------------

section 'refuses to run as non-root on the real filesystem'
if [ "$(id -u)" -eq 0 ]; then
	printf 'skip - the test itself runs as root, so the guard cannot be observed\n'
else
	output=$(
		cd "${root}" || exit 1
		env -u AIRCONNECT_MIGRATE_ROOT sh "${script}" --dry-run 2>&1
	)
	status=$?
	if [ "${status}" -ne 0 ]; then
		ok 'a non-root run without a sandbox exits nonzero'
	else
		no 'a non-root run without a sandbox exits nonzero' 'it succeeded'
	fi
	if printf '%s' "${output}" | grep -q 'must run as root'; then
		ok 'a non-root run explains that it needs root'
	else
		no 'a non-root run explains that it needs root' "${output}"
	fi
fi

# --- (9) unknown arguments ------------------------------------------------

section 'argument handling'
make_sandbox args
before=$(tree_state "${SB}")
output=$(run_script "${SB}" --apply --rollback)
status=$?
if [ "${status}" -eq 2 ]; then
	ok 'two conflicting modes exit 2'
else
	no 'two conflicting modes exit 2' "exit ${status}"
fi
output=$(run_script "${SB}" --nonsense)
status=$?
if [ "${status}" -eq 2 ]; then
	ok 'an unknown flag exits 2'
else
	no 'an unknown flag exits 2' "exit ${status}"
fi
after=$(tree_state "${SB}")
if [ "${before}" = "${after}" ]; then
	ok 'a rejected argument list changes nothing'
else
	no 'a rejected argument list changes nothing' 'the tree changed'
fi
output=$(run_script "${SB}" --help)
status=$?
check '--help exits 0' "${status}"

# --- summary ---------------------------------------------------------------

printf '\nmigration: %d passed, %d failed\n' "${passed}" "${failed}"
[ "${failed}" -eq 0 ] || exit 1
exit 0
