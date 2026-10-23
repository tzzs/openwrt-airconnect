#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 tzzs
#
# Static and host-runnable checks for the rpcd backend.
#
# The plugin needs ubus and uci, which a host does not have. It therefore cannot
# be executed here the way rpcd executes it, and the checks below cover what can
# be proven without a router:
#
#   1. the plugin compiles (ucode -c) and the compile is silent;
#   2. its top-level return is a signature object with the documented object and
#      the five methods, with the documented argument type hints;
#   3. it is loaded through loadfile() with uci/ubus stubs on the module path, so
#      every method is actually called and returns a plain object even when the
#      configuration cannot be read - the "never NO_DATA" requirement;
#   4. validate() runs the real config.uc, including the render-time rejection;
#   5. the plugin file contains no shell interpolation of request values and no
#      destructive command against a detected legacy instance;
#   6. tests/state/plugin.uc drives the real plugin against a sandbox root with
#      fake uci/ubus modules: cache, staleness, logs, conflicts, action, scan.
#
# Host only: this script uses bash. The packaged files themselves are ucode.
#
# Usage: bash tests/state/check-plugin.sh
# Exit status: 0 when every check passes, 1 otherwise.

set -u
set -o pipefail

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "${here}/../.." && pwd)
plugin="${root}/packages/airconnect-manager/files/usr/share/rpcd/ucode/airconnect-manager"
state="${root}/packages/airconnect-manager/files/usr/share/airconnect-manager/state.uc"

UCODE="${UCODE:-${HOME}/.local/opt/ucode-host/bin/ucode}"
UCODE_LIB="${UCODE_LIB:-${HOME}/.local/opt/ucode-host/lib/ucode}"

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

if [ ! -x "${UCODE}" ]; then
	printf 'check-plugin: ucode interpreter not found at %s\n' "${UCODE}" >&2
	printf 'Set UCODE=/path/to/ucode when it lives elsewhere.\n' >&2
	exit 1
fi

sandbox=$(mktemp -d "${TMPDIR:-/tmp}/airconnect-plugin.XXXXXX") || exit 1
trap 'rm -rf "${sandbox}"' EXIT

# --- 1. the plugin compiles, silently ---------------------------------------
section 'plugin compiles'
if [ ! -f "${plugin}" ]; then
	no 'plugin exists' "missing ${plugin}"
	printf '\ncheck-plugin: %d passed, %d failed\n' "${passed}" "${failed}"
	exit 1
fi
ok 'plugin exists'

# The literal invocation from the task spec, run with the sandbox as the working
# directory so the bytecode `ucode -c` writes by default never lands in the repo.
compile_out=$(cd "${sandbox}" && "${UCODE}" -L "${UCODE_LIB}" -c "${plugin}" 2>&1)
compile_rc=$?
if [ "${compile_rc}" -eq 0 ]; then
	ok 'ucode -c exits 0'
else
	no 'ucode -c exits 0' "exit ${compile_rc}: ${compile_out}"
fi
if [ -z "${compile_out}" ]; then
	ok 'ucode -c prints nothing'
else
	no 'ucode -c prints nothing' "${compile_out}"
fi
if [ "${compile_rc}" -ne 0 ]; then
	printf '\ncheck-plugin: %d passed, %d failed\n' "${passed}" "${failed}"
	exit 1
fi

# The plugin's imports must resolve on the host too; a broken relative path is
# invisible to `-c` on the router but fatal at rpcd start-up.
if "${UCODE}" -L "${UCODE_LIB}" -cmodule -o "${sandbox}/state.out" "${state}" >/dev/null 2>&1; then
	ok 'state.uc compiles as a module'
else
	no 'state.uc compiles as a module' 'ucode -cmodule failed'
fi

# --- 2. the signature object ------------------------------------------------
section 'rpcd signature'
cat > "${sandbox}/signature.uc" <<'UC'
// Prints a machine-readable description of the signature object so the shell
// assertions below do not have to parse ucode values by hand.
let signature = loadfile(ARGV[0])();
if (type(signature) != 'object' || signature == null) {
	print('SIGNATURE_NOT_OBJECT\n');
	exit(1);
}
let names = sort(keys(signature));
printf('OBJECTS %s\n', join(',', names));
for (let name in names) {
	let methods = signature[name];
	if (type(methods) != 'object' || methods == null) {
		printf('METHODS %s NOT_OBJECT\n', name);
		continue;
	}
	printf('METHODS %s %s\n', name, join(',', sort(keys(methods))));
	for (let method in sort(keys(methods))) {
		let definition = methods[method];
		if (type(definition) != 'object' || definition == null) {
			printf('DEF %s.%s NOT_OBJECT\n', name, method);
			continue;
		}
		if (type(definition.call) != 'function')
			printf('DEF %s.%s NO_CALL\n', name, method);
		let args = exists(definition, 'args') ? definition.args : null;
		if (args == null) {
			printf('ARGS %s.%s -\n', name, method);
			continue;
		}
		if (type(args) != 'object') {
			printf('ARGS %s.%s NOT_OBJECT\n', name, method);
			continue;
		}
		let hints = [];
		for (let argument in sort(keys(args)))
			push(hints, argument + ':' + type(args[argument]));
		printf('ARGS %s.%s %s\n', name, method, join(',', hints));
	}
}
UC

signature_out=$("${UCODE}" -L "${UCODE_LIB}" "${sandbox}/signature.uc" "${plugin}" 2>&1)
signature_rc=$?
if [ "${signature_rc}" -eq 0 ]; then
	ok 'the top-level return is a signature object'
else
	no 'the top-level return is a signature object' "${signature_out}"
fi

objects=$(printf '%s\n' "${signature_out}" | sed -n 's/^OBJECTS //p')
if [ "${objects}" = 'airconnect.manager' ]; then
	ok 'the plugin registers exactly airconnect.manager'
else
	no 'the plugin registers exactly airconnect.manager' "got '${objects}'"
fi

methods=$(printf '%s\n' "${signature_out}" | sed -n 's/^METHODS airconnect\.manager //p')
if [ "${methods}" = 'action,logs,scan,status,validate' ]; then
	ok 'the five documented methods are registered'
else
	no 'the five documented methods are registered' "got '${methods}'"
fi

if printf '%s\n' "${signature_out}" | grep -q 'NO_CALL'; then
	no 'every method has a call function' "$(printf '%s\n' "${signature_out}" | grep 'NO_CALL' | tr '\n' ' ')"
else
	ok 'every method has a call function'
fi
if printf '%s\n' "${signature_out}" | grep -q 'NOT_OBJECT'; then
	no 'every method definition is an object' "$(printf '%s\n' "${signature_out}" | grep 'NOT_OBJECT' | tr '\n' ' ')"
else
	ok 'every method definition is an object'
fi

args_validate=$(printf '%s\n' "${signature_out}" | sed -n 's/^ARGS airconnect\.manager\.validate //p')
args_action=$(printf '%s\n' "${signature_out}" | sed -n 's/^ARGS airconnect\.manager\.action //p')
if [ "${args_validate}" = 'config:object' ]; then
	ok 'validate takes one object argument named config'
else
	no 'validate takes one object argument named config' "got '${args_validate}'"
fi
if [ "${args_action}" = 'action:string' ]; then
	ok 'action takes one string argument named action'
else
	no 'action takes one string argument named action' "got '${args_action}'"
fi
for method in status logs scan; do
	args=$(printf '%s\n' "${signature_out}" | sed -n "s/^ARGS airconnect\\.manager\\.${method} //p")
	if [ "${args}" = '-' ]; then
		ok "${method} takes no arguments"
	else
		no "${method} takes no arguments" "got '${args}'"
	fi
done

# --- 3. every method returns a plain object without uci/ubus ---------------
# This is the important one: rpcd discards a non-object return and LuCI then
# sees NO_DATA. A host without uci/ubus is the worst case, and the page must
# still render.
section 'methods return objects without uci and ubus'
cat > "${sandbox}/call.uc" <<'UC'
let signature = loadfile(ARGV[0])();
let object = signature['airconnect.manager'];
let calls = [
	[ 'status', function() { return object.status.call({ args: {} }); } ],
	[ 'logs', function() { return object.logs.call({ args: {} }); } ],
	[ 'scan', function() { return object.scan.call({ args: {} }); } ],
	[ 'validate', function() { return object.validate.call({ args: { config: { main: { enabled: '1' }, devices: [] } } }); } ],
	[ 'action', function() { return object.action.call({ args: { action: 'stop' } }); } ]
];
let failures = 0;
for (let entry in calls) {
	let name = entry[0], reply = null, error = null;
	try {
		reply = entry[1]();
	}
	catch (exception) {
		error = exception.message ?? sprintf('%J', exception);
	}
	if (error != null) {
		printf('CALL %s THREW %s\n', name, error);
		failures++;
	}
	else if (type(reply) != 'object' || reply == null) {
		printf('CALL %s NOT_OBJECT %s\n', name, type(reply));
		failures++;
	}
	else {
		printf('CALL %s OBJECT %s\n', name, join(',', sort(keys(reply))));
	}
}
exit(failures ? 1 : 0);
UC

call_out=$("${UCODE}" -L "${UCODE_LIB}" "${sandbox}/call.uc" "${plugin}" 2>&1)
call_rc=$?
if [ "${call_rc}" -eq 0 ]; then
	ok 'all five methods return a plain object'
else
	no 'all five methods return a plain object' "${call_out}"
fi

status_keys=$(printf '%s\n' "${call_out}" | sed -n 's/^CALL status OBJECT //p')
# The four states are separate sections on purpose: `services` carries running and
# broadcasting per engine, `scan` carries discovery, `broadcast` carries the mDNS
# observation timestamp, and `playback` is the constant unknown.
expected_status='broadcast,conflicts,devices,enabled,interface,playback,scan,services,version'
if [ "${status_keys}" = "${expected_status}" ]; then
	ok 'status has the documented top-level shape'
else
	no 'status has the documented top-level shape' "got '${status_keys}'"
fi
logs_keys=$(printf '%s\n' "${call_out}" | sed -n 's/^CALL logs OBJECT //p')
if [ "${logs_keys}" = 'lines,truncated' ]; then
	ok 'logs has lines and truncated'
else
	no 'logs has lines and truncated' "got '${logs_keys}'"
fi
scan_keys=$(printf '%s\n' "${call_out}" | sed -n 's/^CALL scan OBJECT //p')
if [ "${scan_keys}" = 'error,ok' ]; then
	ok 'scan reports ok:false with an error when UCI is unreadable'
else
	no 'scan reports ok:false with an error when UCI is unreadable' "got '${scan_keys}'"
fi
validate_keys=$(printf '%s\n' "${call_out}" | sed -n 's/^CALL validate OBJECT //p')
if [ "${validate_keys}" = 'errors,ok' ]; then
	ok 'validate has ok and errors'
else
	no 'validate has ok and errors' "got '${validate_keys}'"
fi

# --- 4. validate() reuses config.uc, including render-time rejection --------
section 'validate reuses config.uc'
cat > "${sandbox}/validate.uc" <<'UC'
let signature = loadfile(ARGV[0])();
let validate = signature['airconnect.manager'].validate.call;
function check(label, config, wantOk, wantText) {
	let reply = validate({ args: { config: config } });
	if (type(reply) != 'object' || reply == null) {
		printf('BAD %s: not an object\n', label);
		return false;
	}
	if (reply.ok !== wantOk) {
		printf('BAD %s: ok=%J errors=%J\n', label, reply.ok, reply.errors);
		return false;
	}
	if (type(reply.errors) != 'array') {
		printf('BAD %s: errors is not an array\n', label);
		return false;
	}
	if (wantText != null) {
		let found = false;
		for (let message in reply.errors)
			if (index(message, wantText) >= 0)
				found = true;
		if (!found) {
			printf('BAD %s: %J does not mention %s\n', label, reply.errors, wantText);
			return false;
		}
	}
	printf('OK %s\n', label);
	return true;
}
let failures = 0;
// A valid UI payload.
if (!check('valid', { main: { enabled: '1', airupnp: '1', aircast: '0' }, devices: [] }, true, null)) failures++;
// A field error, reported with its path exactly as config.uc writes it.
if (!check('max_volume', { main: { max_volume: '0' } }, false, 'main.max_volume:')) failures++;
if (!check('interface', { main: { interface: 'not an interface' } }, false, 'main.interface:')) failures++;
// The advanced fields go through the same path, so a bad value is reported with
// its own path rather than reaching apply time.
if (!check('http_length', { main: { http_length: '4096' } }, false, 'main.http_length:')) failures++;
if (!check('upnp_max', { main: { upnp_max: '10' } }, false, 'main.upnp_max:')) failures++;
if (!check('artwork-scheme', { main: { artwork: 'ftp://example.com/a.png' } }, false, 'main.artwork:')) failures++;
if (!check('artwork-control', { main: { artwork: 'http://example.com/a b.png' } }, false, 'main.artwork:')) failures++;
if (!check('metadata', { main: { metadata: 'yes' } }, false, 'main.metadata:')) failures++;
if (!check('device-http_length', { devices: [{ engine: 'upnp', udn: 'uuid:demo-upnp', http_length: '1' }] }, false, 'devices[0].http_length:')) failures++;
if (!check('device-stop_receiver', { devices: [{ engine: 'cast', udn: 'uuid:demo-cast', stop_receiver: '2' }] }, false, 'devices[0].stop_receiver:')) failures++;
// The advanced defaults are valid for both engines, so a payload that only sets
// them must not be rejected.
if (!check('advanced-defaults', { main: { enabled: '1', airupnp: '1', aircast: '1',
		metadata: '1', artwork: 'https://example.com/a.png', flush: '1', drift: '0',
		http_length: '-1', upnp_max: '1', stop_receiver: '0' }, devices: [] }, true, null)) failures++;
// Both engines enabled with a codec both accept: validate must render both
// without inventing an error.
if (!check('both-engines', { main: { enabled: '1', airupnp: '1', aircast: '1', codec: 'flac' },
		devices: [{ engine: 'upnp', udn: 'uuid:demo-upnp' }, { engine: 'cast', udn: 'uuid:demo-cast' }] }, true, null)) failures++;
// A Cast device with pcm is rejected by normalizeConfig itself, before any
// rendering happens.
if (!check('cast-pcm-device', { main: { enabled: '1', aircast: '1' },
		devices: [{ engine: 'cast', udn: 'uuid:demo-cast', codec: 'pcm' }] }, false, 'devices[0].codec:')) failures++;
// The canonical default payload the LuCI view sends after a fresh install.
if (!check('defaults', { main: { enabled: '0', interface: 'br-lan', airupnp: '1', aircast: '0', codec: 'flac',
		latency: '1000:2000', max_volume: '100', media_volume: '0.5', log_level: 'warn',
		metadata: '1', artwork: '', flush: '1', drift: '0', http_length: '-1', upnp_max: '1',
		stop_receiver: '0' }, devices: [] }, true, null)) failures++;
// A configuration that predates the advanced options must still validate: the
// shipped file from an older install simply lacks these keys.
if (!check('pre-advanced-config', { main: { enabled: '0', interface: 'br-lan', airupnp: '1',
		aircast: '0', codec: 'flac', latency: '1000:2000', max_volume: '100',
		media_volume: '0.5', log_level: 'warn' }, devices: [] }, true, null)) failures++;
// A non-object payload must be a validation error, not an exception.
if (!check('non-object', 'nonsense', false, 'config:')) failures++;
exit(failures ? 1 : 0);
UC

validate_out=$("${UCODE}" -L "${UCODE_LIB}" "${sandbox}/validate.uc" "${plugin}" 2>&1)
validate_rc=$?
if [ "${validate_rc}" -eq 0 ]; then
	ok 'validate accepts good input and rejects bad input with a path'
else
	no 'validate accepts good input and rejects bad input with a path' "${validate_out}"
fi
if printf '%s\n' "${validate_out}" | grep -q '^OK both-engines$'; then
	ok 'validate renders every enabled engine without a spurious error'
else
	no 'validate renders every enabled engine without a spurious error' "${validate_out}"
fi
if printf '%s\n' "${validate_out}" | grep -q '^BAD '; then
	no 'no validate case failed' "$(printf '%s\n' "${validate_out}" | grep '^BAD ' | tr '\n' ' ')"
else
	ok 'no validate case failed'
fi

# --- 5. static safety of the packaged plugin -------------------------------
section 'plugin safety'
# The action command must be selected from a fixed table, never built from the
# request. A request-derived value reaching fs.popen() is the defect this guards.
if grep -q 'ACTION_COMMANDS\[action_name\]' "${plugin}"; then
	ok 'the action command is looked up in a fixed table'
else
	no 'the action command is looked up in a fixed table' 'expected ACTION_COMMANDS[action_name]'
fi
if grep -Eq 'ACTION_COMMANDS\[[^]]*\] *=' "${plugin}"; then
	no 'the action command table is never written at runtime' 'found an assignment into ACTION_COMMANDS'
else
	ok 'the action command table is never written at runtime'
fi
if grep -Eq '(popen|system)\([^)]*(action_name|request\.|args\.)' "${plugin}"; then
	no 'no request value reaches a shell command' 'found a request value in a popen/system call'
else
	ok 'no request value reaches a shell command'
fi
if grep -Eq '(popen|system)\([^)]*(udn|original_name|address|device)' "${plugin}"; then
	no 'no discovery value reaches a shell command' 'found a device field in a popen/system call'
else
	ok 'no discovery value reaches a shell command'
fi
for destructive in 'killall' 'kill ' 'pkill' 'rm -rf' 'uci delete' 'uci set' 'uci commit'; do
	if grep -qF "${destructive}" "${plugin}"; then
		no "the plugin never runs '${destructive}'" 'conflict detection is presence only'
	else
		ok "the plugin never runs '${destructive}'"
	fi
done
if grep -q 'Presence only' "${plugin}"; then
	ok 'conflict detection is documented as presence only'
else
	no 'conflict detection is documented as presence only' 'missing the presence-only comment'
fi
if grep -Eq "popen\('[^']*\+ *(action|args|request)" "${plugin}"; then
	no 'popen commands are literals' 'found a concatenated popen command'
else
	ok 'popen commands are literals or fixed paths'
fi
# The worker is the only long-running child and it must not be a resident
# process: it is started with `&` and exits when discovery finishes.
if grep -q 'scan-worker' "${plugin}"; then
	ok 'the discovery worker is the same script started with a fixed argument'
else
	no 'the discovery worker is the same script started with a fixed argument' 'no scan-worker entry'
fi
if grep -q 'exit(runScanWorker())' "${plugin}"; then
	ok 'the worker branch exits before the signature is returned'
else
	no 'the worker branch exits before the signature is returned' 'the worker could register objects'
fi
# uci and ubus are optional at load time, so the plugin still loads (and status
# still answers) when a module is missing.
if grep -Eq "^[[:space:]]*import .* from '(uci|ubus)'" "${plugin}"; then
	no 'uci and ubus are required at runtime, not at compile time' 'found a static import'
else
	ok 'uci and ubus are required at runtime, not at compile time'
fi
if grep -q "require('uci')" "${plugin}" && grep -q "require('ubus')" "${plugin}"; then
	ok 'both uci and ubus are loaded through require()'
else
	no 'both uci and ubus are loaded through require()' 'missing a require()'
fi
# state.uc must stay pure: the plugin is the only place that does I/O.
if grep -Eq "import .* from '(uci|ubus|fs|socket)'" "${state}"; then
	no 'state.uc imports no runtime modules' 'state.uc must stay pure'
else
	ok 'state.uc imports no runtime modules'
fi
# The target's ucode (20230711, as shipped by iStoreOS 25.12.5) rejects
# `export function`; only `const f = function() {}` plus an `export { }` list
# compiles there. Accept either form so the assertion tracks "the helpers are
# exported", not one particular spelling of it.
if grep -q 'export function' "${state}" || grep -q '^export {' "${state}"; then
	ok 'state.uc exports the pure helpers'
else
	no 'state.uc exports the pure helpers' 'no exports found'
fi

# --- 6. the plugin's I/O paths, against a sandbox root ---------------------
# tests/state/plugin.uc loads the plugin with AIRCONNECT_MANAGER_ROOT pointing at
# a temporary directory and fake uci/ubus modules on the module search path, so
# cache handling, staleness, log tailing, conflicts and the action/scan refusals
# are exercised for real. Nothing here talks to ubusd, netifd, procd or the LAN.
section 'plugin I/O against a sandbox root'
stubdir="${sandbox}/stubs"
rootdir="${sandbox}/root"
mkdir -p "${stubdir}" "${rootdir}"
plugin_out=$(
	UCODE="${UCODE}" \
	UCODE_LIB="${UCODE_LIB}" \
	AIRCONNECT_MANAGER_ROOT="${rootdir}" \
	AIRCONNECT_MANAGER_STUBS="${stubdir}" \
	"${UCODE}" -L "${stubdir}" -L "${UCODE_LIB}" "${here}/plugin.uc" 2>&1
)
plugin_rc=$?
if [ "${plugin_rc}" -eq 0 ]; then
	ok 'the plugin I/O suite passes'
else
	no 'the plugin I/O suite passes' "$(printf '%s\n' "${plugin_out}" | grep '^not ok' | head -5 | tr '\n' ' ')"
fi
plugin_total=$(printf '%s\n' "${plugin_out}" | sed -n 's/^\([0-9]*\) passed; \([0-9]*\) failed$/\1 \2/p')
plugin_ok=$(printf '%s' "${plugin_total}" | cut -d' ' -f1)
plugin_bad=$(printf '%s' "${plugin_total}" | cut -d' ' -f2)
if [ -n "${plugin_total}" ] && [ "${plugin_bad:-1}" -eq 0 ] && [ "${plugin_ok:-0}" -gt 0 ]; then
	ok "the plugin I/O suite reports ${plugin_ok} passing cases and no failures"
else
	no 'the plugin I/O suite reports a summary' "got '${plugin_total:-none}'"
fi

printf '\ncheck-plugin: %d passed, %d failed\n' "${passed}" "${failed}"
[ "${failed}" -eq 0 ] || exit 1
exit 0
