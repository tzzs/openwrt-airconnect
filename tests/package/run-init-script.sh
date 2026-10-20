#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 tzzs
#
# Behavioural host test for the packaged procd init script.
#
# It sources the real init script and replaces only its outside world: the UCI
# helpers, procd's wrappers, logger and the runtime.uc renderer. Every assertion
# inspects what the init script asked procd to do, so a regression in instance
# registration, the -Z/-x flags, the publish-after-validate contract or
# interface sanitising fails here without OpenWrt.
#
# Usage: sh tests/package/run-init-script.sh
# Exit status: 0 when every case passes, 1 otherwise.

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "${here}/../.." && pwd)
initscript="${root}/packages/airconnect-manager/files/etc/init.d/airconnect-manager"

passed=0
failed=0

pass() {
	passed=$((passed + 1))
	printf 'ok   %s\n' "$1"
}

fail() {
	failed=$((failed + 1))
	printf 'FAIL %s\n' "$1"
}

# Build a throwaway sandbox with fake engine binaries and a configurable
# renderer. Renderer modes:
#   ok      both XML files are rendered
#   fail    the renderer rejects the configuration and writes nothing
#   empty   the renderer succeeds but writes no XML
#   absent  runtime.uc is not installed at all (today's T2-not-landed state)
#   noexec  runtime.uc exists without the executable bit
make_sandbox() {
	sandbox=$(mktemp -d "${TMPDIR:-/tmp}/airconnect-init.XXXXXX") || exit 1
	mkdir -p "${sandbox}/usr/libexec/airconnect" "${sandbox}/usr/share/airconnect-manager" \
		"${sandbox}/var/run" "${sandbox}/etc/config"
	printf '%s\n' "$1" >"${sandbox}/render-mode.txt"

	for engine in airupnp aircast; do
		printf '#!/bin/sh\nexit 0\n' >"${sandbox}/usr/libexec/airconnect/${engine}"
		chmod 0755 "${sandbox}/usr/libexec/airconnect/${engine}"
	done

	if [ "$1" != "absent" ]; then
		cat >"${sandbox}/usr/share/airconnect-manager/runtime.uc" <<-'RENDERER'
			#!/bin/sh
			# Fake renderer: stands in for T2's runtime.uc.
			case "$(cat "${FAKE_MODE_FILE}" 2>/dev/null)" in
				fail)
					echo 'render rejected' >&2
					exit 1
					;;
				empty)
					exit 0
					;;
			esac
			mkdir -p "${FAKE_RUNTIME_DIR}"
			printf '<airupnp/>\n' >"${FAKE_RUNTIME_DIR}/airupnp.xml"
			printf '<aircast/>\n' >"${FAKE_RUNTIME_DIR}/aircast.xml"
			exit 0
		RENDERER
		if [ "$1" = "noexec" ]; then
			chmod 0644 "${sandbox}/usr/share/airconnect-manager/runtime.uc"
		else
			chmod 0755 "${sandbox}/usr/share/airconnect-manager/runtime.uc"
		fi
	fi
	printf '%s' "${sandbox}"
}

cleanup() {
	[ -n "${sandbox:-}" ] && rm -rf "${sandbox}"
}

# Seed a "previous run": a rejected configuration must leave these files, and
# the engines using them, untouched.
seed_runtime_xml() {
	mkdir -p "${sandbox}/var/etc/airconnect-manager"
	printf '<airupnp>previous</airupnp>\n' >"${sandbox}/var/etc/airconnect-manager/airupnp.xml"
	printf '<aircast>previous</aircast>\n' >"${sandbox}/var/etc/airconnect-manager/aircast.xml"
}

# Source the init script in a subshell with the stubs installed, then run one
# action. Everything the script reports goes to ${sandbox}/calls.txt.
run_action() {
	action="$1"
	(
		export FAKE_RUNTIME_DIR="${sandbox}/var/etc/airconnect-manager"
		export FAKE_MODE_FILE="${sandbox}/render-mode.txt"
		export AIRCONNECT_MANAGER_ROOT="${sandbox}"
		calls="${sandbox}/calls.txt"
		: >"${calls}"

		# --- stubs for the OpenWrt environment -------------------------------
		record() { printf '%s\n' "$*" >>"${calls}"; }

		logger() { record "logger $*"; }
		config_load() { record "config_load $*"; }
		config_get_bool() {
			eval "$1=\${CFG_$(printf '%s' "$3" | tr 'a-z' 'A-Z'):-0}"
		}
		config_get() {
			eval "$1=\${CFG_$(printf '%s' "$3" | tr 'a-z' 'A-Z'):-$4}"
		}
		procd_open_instance() { record "instance $1"; }
		procd_set_param() { record "param $*"; }
		procd_close_instance() { record "close"; }
		procd_add_reload_trigger() { record "trigger $*"; }
		# rc.common's rc_procd wraps the callback in procd_open_service and
		# procd_close_service, so the callback must really run here.
		rc_procd() { record "rc_procd $*"; "$@"; }

		# --- the subject under test ------------------------------------------
		. "${initscript}"

		# Fatal paths exit instead of returning, so the status is recorded by
		# the parent after this subshell ends, not from inside it.
		"${action}"
	) 2>>"${sandbox}/renderer.log"
	# The init script legitimately exits nonzero; that is the value under test.
	printf 'status %s\n' "$?" >>"${sandbox}/calls.txt"
}

# --- assertions -------------------------------------------------------------

expect_status() {
	if grep -qx "status $2" "${sandbox}/calls.txt"; then
		pass "$1: exit status $2"
	else
		fail "$1: expected exit status $2, got '$(grep '^status ' "${sandbox}/calls.txt" | tail -1)'"
	fi
}

expect_instances() {
	actual=$(grep '^instance ' "${sandbox}/calls.txt" | sed 's/^instance //' | tr '\n' ' ')
	actual=${actual% }
	if [ "${actual}" = "$2" ]; then
		pass "$1: registered instances '${actual}'"
	else
		fail "$1: expected instances '$2', got '${actual}'"
	fi
}

expect_no_instances() {
	expect_instances "$1" ""
}

expect_param_contains() {
	if grep -q -- "param $2" "${sandbox}/calls.txt"; then
		pass "$1: param $2"
	else
		fail "$1: missing 'param $2'"
	fi
}

expect_no_match() {
	if grep -q -- "$2" "${sandbox}/calls.txt"; then
		fail "$1: unexpected '$(grep -- "$2" "${sandbox}/calls.txt" | head -1)'"
	else
		pass "$1: nothing matching '$2'"
	fi
}

expect_log() {
	if grep -q -- "^logger .*${2}" "${sandbox}/calls.txt"; then
		pass "$1: logged '$2'"
	else
		fail "$1: expected a log line matching '$2'"
	fi
}

expect_no_error_log() {
	if grep -q '^logger .*daemon\.err' "${sandbox}/calls.txt"; then
		fail "$1: logged an error: $(grep '^logger .*daemon\.err' "${sandbox}/calls.txt" | head -1)"
	else
		pass "$1: no error logged"
	fi
}

set_config() {
	CFG_ENABLED="$1"
	CFG_AIRUPNP="$2"
	CFG_AIRCAST="$3"
	CFG_INTERFACE="${4:-br-lan}"
	export CFG_ENABLED CFG_AIRUPNP CFG_AIRCAST CFG_INTERFACE
}

trap cleanup EXIT INT TERM

# --- case 1: disabled right after installation ------------------------------
sandbox=$(make_sandbox ok)
set_config 0 1 0
run_action start_service
expect_status 'disabled service' 0
expect_no_instances 'disabled service'
expect_no_error_log 'disabled service'
if [ -e "${sandbox}/var/etc/airconnect-manager/airupnp.xml" ]; then
	fail 'disabled service: must not render runtime XML'
else
	pass 'disabled service: no runtime XML rendered'
fi
cleanup

# --- case 2: only the UPnP engine -------------------------------------------
sandbox=$(make_sandbox ok)
set_config 1 1 0
run_action start_service
expect_status 'upnp only' 0
expect_instances 'upnp only' 'airupnp'
expect_param_contains 'upnp only' "command ${sandbox}/usr/libexec/airconnect/airupnp -Z -x ${sandbox}/var/etc/airconnect-manager/airupnp.xml"
expect_param_contains 'upnp only' 'respawn 3600 5 5'
expect_param_contains 'upnp only' "file ${sandbox}/var/etc/airconnect-manager/airupnp.xml"
expect_param_contains 'upnp only' 'stdout 1'
expect_param_contains 'upnp only' 'stderr 1'
expect_param_contains 'upnp only' "pidfile ${sandbox}/var/run/airconnect-airupnp.pid"
expect_no_match 'upnp only' ' -z '
expect_no_match 'upnp only' ' -b '
expect_no_match 'upnp only' 'aircast'
expect_no_error_log 'upnp only'
if [ "$(stat -c '%a' "${sandbox}/var/etc/airconnect-manager" 2>/dev/null || stat -f '%Lp' "${sandbox}/var/etc/airconnect-manager")" = '750' ]; then
	pass 'upnp only: runtime directory is 0750'
else
	fail 'upnp only: runtime directory is not 0750'
fi
cleanup

# --- case 3: both engines ---------------------------------------------------
sandbox=$(make_sandbox ok)
set_config 1 1 1
run_action start_service
expect_status 'both engines' 0
expect_instances 'both engines' 'airupnp aircast'
expect_param_contains 'both engines' "command ${sandbox}/usr/libexec/airconnect/airupnp -Z -x ${sandbox}/var/etc/airconnect-manager/airupnp.xml"
expect_param_contains 'both engines' "command ${sandbox}/usr/libexec/airconnect/aircast -Z -x ${sandbox}/var/etc/airconnect-manager/aircast.xml"
expect_no_error_log 'both engines'
cleanup

# --- case 3b: only the Cast engine ------------------------------------------
sandbox=$(make_sandbox ok)
set_config 1 0 1
run_action start_service
expect_status 'cast only' 0
expect_instances 'cast only' 'aircast'
expect_no_error_log 'cast only'
cleanup

# --- case 4: renderer not installed (T2 has not landed) --------------------
sandbox=$(make_sandbox absent)
set_config 1 1 0
run_action start_service
expect_status 'renderer absent' 1
expect_no_instances 'renderer absent'
expect_log 'renderer absent' 'missing or not executable'
cleanup

# --- case 5: renderer present but not executable ---------------------------
sandbox=$(make_sandbox noexec)
set_config 1 1 0
run_action start_service
expect_status 'renderer not executable' 1
expect_no_instances 'renderer not executable'
expect_log 'renderer not executable' 'missing or not executable'
cleanup

# --- case 6: renderer rejects the configuration, no fallback available -----
sandbox=$(make_sandbox fail)
set_config 1 1 0
run_action start_service
expect_status 'render rejected' 1
expect_no_instances 'render rejected'
expect_log 'render rejected' 'keeping the previous generated files'
cleanup

# --- case 6b: rejected render keeps engines on the last valid XML ----------
# The single most important guarantee: a broken edit must not stop a working
# engine. Because the script exits before publishing, procd keeps the instance
# that is still running on the previous XML.
sandbox=$(make_sandbox fail)
seed_runtime_xml
set_config 1 1 0
run_action start_service
expect_status 'render rejected with previous XML' 1
expect_no_instances 'render rejected with previous XML: publishes nothing'
expect_log 'render rejected with previous XML' 'keeping the previous generated files'
if grep -q previous "${sandbox}/var/etc/airconnect-manager/airupnp.xml"; then
	pass 'render rejected with previous XML: the previous file is untouched'
else
	fail 'render rejected with previous XML: the previous file was modified'
fi
cleanup

# --- case 6c: renderer succeeds but writes no XML for a selected engine ----
sandbox=$(make_sandbox empty)
set_config 1 1 0
run_action start_service
expect_status 'no XML rendered' 1
expect_no_instances 'no XML rendered'
expect_log 'no XML rendered' 'without configuration'
cleanup

# --- case 7: engine selected but its binary is missing ---------------------
sandbox=$(make_sandbox ok)
set_config 1 1 0
rm -f "${sandbox}/usr/libexec/airconnect/airupnp"
run_action start_service
expect_status 'engine binary missing' 1
expect_no_instances 'engine binary missing'
expect_log 'engine binary missing' 'not installed'
cleanup

# --- case 7b: a missing engine blocks the whole publish --------------------
# Starting only half the requested engines would silently halve the service, so
# the instance list is all-or-nothing.
sandbox=$(make_sandbox ok)
set_config 1 1 1
rm -f "${sandbox}/usr/libexec/airconnect/aircast"
run_action start_service
expect_status 'one engine missing' 1
expect_no_instances 'one engine missing'
expect_log 'one engine missing' 'engine aircast is not installed'
cleanup

# --- case 8: enabled without any engine ------------------------------------
sandbox=$(make_sandbox ok)
set_config 1 0 0
run_action start_service
expect_status 'no engine selected' 0
expect_no_instances 'no engine selected'
expect_log 'no engine selected' 'no engine is selected'
cleanup

# --- case 9: hostile interface values never reach a command or a path ------
for hostile in 'br-lan;reboot' '$(id)' 'br-lan`id`' '../etc/passwd' 'eth0/1' '' 'aaaaaaaaaaaaaaaa' '.' '..' 'br lan'; do
	sandbox=$(make_sandbox ok)
	set_config 1 1 0 "${hostile}"
	run_action start_service
	expect_instances "interface '${hostile}'" 'airupnp'
	expect_no_match "interface '${hostile}'" 'reboot'
	expect_no_match "interface '${hostile}'" 'id`'
	expect_no_match "interface '${hostile}'" 'passwd'
	expect_no_match "interface '${hostile}'" 'eth0/1'
	expect_no_match "interface '${hostile}'" 'aaaaaaaaaaaaaaaa'
	expect_no_match "interface '${hostile}'" 'br lan'
	cleanup
done

# --- case 9b: a valid interface is accepted without a binding warning -----
# The "interface is not present" warning depends on /sys/class/net, which only
# exists on Linux, so this case only asserts that the token is not rewritten.
sandbox=$(make_sandbox ok)
set_config 1 1 0 'br-lan'
run_action start_service
expect_status 'valid interface' 0
expect_instances 'valid interface' 'airupnp'
expect_no_match 'valid interface' 'not a bare interface name'
if [ -e /sys/class/net/br-lan ]; then
	expect_no_match 'valid interface' 'is not present'
else
	printf 'skip - /sys/class/net is unavailable, binding warning not checked\n'
fi
cleanup

# --- case 9c: the interface allowlist matches config.uc exactly ---------------
# A value the shell accepts and the backend rejects would silently rewrite the
# configured interface to the default, so what this script rewrites has to be
# exactly the set config.uc refuses. The real function is exercised through a
# subshell that sources the init script, so no copy of the rule can drift.
init_valid_interface() {
	(
		# shellcheck disable=SC2034  # used by the sourced init script
		AIRCONNECT_MANAGER_ROOT="${sandbox}"
		. "${initscript}"
		if valid_interface "$1"; then exit 0; else exit 1; fi
	)
}

for good in 'br-lan' 'wlan0' 'eth0.100' 'demo_01'; do
	if init_valid_interface "${good}"; then
		pass "allowlist accepts '${good}'"
	else
		fail "allowlist rejected '${good}'"
	fi
done
for bad in 'eth0:1' '-bad' '.' '..' '' 'aaaaaaaaaaaaaaaa' 'br lan' 'br/lan'; do
	if init_valid_interface "${bad}"; then
		fail "allowlist accepted '${bad}'"
	else
		pass "allowlist rejects '${bad}'"
	fi
done
sandbox=$(make_sandbox ok)
set_config 1 1 0 'eth0:1'
run_action start_service
# Rewritten to the default, so the engine still starts; what matters is that the
# script said so instead of passing ':' through to the backend.
expect_instances "interface 'eth0:1'" 'airupnp'
expect_log "interface 'eth0:1'" 'not a bare interface name'
cleanup

# --- case 10: reload publishes the set through rc_procd --------------------
sandbox=$(make_sandbox ok)
set_config 1 1 0
run_action reload_service
expect_status 'reload with good render' 0
if grep -qx 'rc_procd start_service' "${sandbox}/calls.txt"; then
	pass 'reload with good render: publishes through rc_procd'
else
	fail 'reload with good render: did not call rc_procd start_service'
fi
expect_instances 'reload with good render' 'airupnp'
if [ -s "${sandbox}/var/etc/airconnect-manager/airupnp.xml" ]; then
	pass 'reload with good render: rendered airupnp.xml'
else
	fail 'reload with good render: airupnp.xml is missing'
fi
cleanup

# --- case 10b: reload after a rejected render publishes nothing ------------
# rc_procd is entered, but start_service exits before registering an instance.
# Publishing an empty set here would stop the engine still using the old XML.
sandbox=$(make_sandbox fail)
seed_runtime_xml
set_config 1 1 0
run_action reload_service
expect_status 'reload with failed render' 1
expect_no_instances 'reload with failed render: publishes nothing'
cleanup

# --- case 11: the init script never writes the persistent config -----------
sandbox=$(make_sandbox ok)
set_config 1 1 1
run_action start_service
if [ -z "$(ls -A "${sandbox}/etc/config")" ]; then
	pass 'init script does not create or modify /etc/config entries'
else
	fail "init script touched the config directory: $(ls -A "${sandbox}/etc/config")"
fi
cleanup

# --- case 12: stop_service leaves termination to procd ---------------------
sandbox=$(make_sandbox ok)
set_config 1 1 1
run_action stop_service
expect_status 'stop service' 0
expect_no_instances 'stop service'
expect_no_match 'stop service' 'procd_kill'
cleanup

# --- case 13: service_triggers registers the reload trigger ---------------
sandbox=$(make_sandbox ok)
run_action service_triggers
if grep -qx 'trigger airconnect-manager' "${sandbox}/calls.txt"; then
	pass 'service_triggers registers the airconnect-manager reload trigger'
else
	fail "service_triggers did not register the reload trigger"
fi
cleanup

printf '\n%d checks, %d failures\n' "$((passed + failed))" "${failed}"
[ "${failed}" -eq 0 ] || exit 1
exit 0
