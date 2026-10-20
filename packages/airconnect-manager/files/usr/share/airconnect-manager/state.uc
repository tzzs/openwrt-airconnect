// SPDX-License-Identifier: MIT
// state.uc - pure shaping of manager state for the rpcd backend.
//
// Every function here is a function of its arguments: no UCI, no ubus, no
// filesystem, and no clock reads except the injected `now`. The rpcd plugin
// (files/usr/share/rpcd/ucode/airconnect-manager) does the I/O and calls these
// functions, which lets tests/state/run.uc drive the same code on a host that
// has neither ubus nor uci.

// The reply bound. A hostile or broken cache must not be able to grow the ubus
// message without limit, and the LuCI page renders one card per entry.
const MAX_DEVICES = 64;
const MAX_ERRORS = 20;
const MAX_ERROR_BYTES = 512;
const MAX_LINE_BYTES = 512;
// A discovery snapshot is shown for a day. Older data is not "last seen"; it is
// history, and presenting it as current state would be a lie.
const CACHE_MAX_AGE = 86400;
// Tolerate a small clock step backwards without discarding a fresh snapshot.
const CACHE_FUTURE_SKEW = 300;
// /bin/ps output is read with a 64 KiB cap; the parser applies the same bound
// so a caller cannot bypass it.
const PS_TEXT_LIMIT = 65536;
const ENGINE_NAMES = ['airupnp', 'aircast'];

function messageOf(value) {
	if (type(value) == 'string')
		return value;
	if (type(value) == 'object' && value != null && type(value.message) == 'string')
		return value.message;
	if (value == null)
		return '';
	return sprintf('%J', value);
}

// A control byte in a display string is either corruption or an attempt to
// confuse the consumer. Reject the value instead of silently rewriting it, so a
// caller can never see a sanitized name that is not what the device advertised.
function hasControl(value) {
	for (let i = 0; i < length(value); i++) {
		let c = ord(value, i);
		if (c == 0 || c == 0x7f || (c < 0x20 && c != 0x09))
			return true;
	}
	return false;
}

function stringOrNull(value, maxBytes) {
	if (type(value) != 'string' || value == '' || length(value) > maxBytes || hasControl(value))
		return null;
	return value;
}

function integerOrNull(value) {
	return type(value) == 'int' && value >= 0 ? value : null;
}

function truthy(value) {
	// config.uc accepts exactly these spellings, so status agrees with the
	// validator instead of inventing a second notion of "enabled".
	return value === true || value === 1 || value === '1';
}

function triState(value) {
	return value === true ? true : value === false ? false : null;
}

function engineOf(value) {
	return value === 'upnp' || value === 'cast' ? value : null;
}

// The interface is shown to the user as a fact, so it is held to the same rule
// config.uc applies: a bare Linux interface token of 1..15 ASCII bytes. Anything
// else is reported as unknown instead of being echoed back as if it were valid.
function interfaceOrNull(value) {
	if (type(value) != 'string' || length(value) > 15 || value == '.' || value == '..')
		return null;
	let m = match(value, /^[A-Za-z0-9_][A-Za-z0-9_.-]*$/);
	return m != null && length(m[0]) == length(value) ? value : null;
}

function deviceKey(engine, udn) {
	// Neither half can contain a newline: stringOrNull rejects control bytes.
	return engine + '\n' + udn;
}

// Canonical device shape consumed by the LuCI view. Absent facts stay null; a
// model, manufacturer or address is never inferred.
function normalizeDevice(source) {
	if (type(source) != 'object' || source == null)
		return null;
	let engine = engineOf(source.engine);
	if (engine == null)
		return null;
	let udn = stringOrNull(source.udn, 255);
	if (udn == null)
		return null;
	return {
		engine: engine,
		udn: udn,
		original_name: stringOrNull(source.original_name, 255),
		name: stringOrNull(source.name, 63),
		model: stringOrNull(source.model, 128),
		manufacturer: stringOrNull(source.manufacturer, 128),
		address: stringOrNull(source.address, 45),
		last_seen: integerOrNull(source.last_seen),
		online: source.online === true,
		configured: source.configured === true
	};
}

function configuredEntries(uciDevices) {
	let entries = {}, order = [];
	for (let entry in uciDevices ?? []) {
		if (type(entry) != 'object' || entry == null)
			continue;
		let engine = engineOf(entry.engine);
		let udn = stringOrNull(entry.udn, 255);
		if (engine == null || udn == null)
			continue;
		let key = deviceKey(engine, udn);
		if (exists(entries, key))
			continue;
		entries[key] = stringOrNull(entry.name, 63);
		push(order, key);
	}
	return { entries: entries, order: order };
}

// Discovered devices first, then configured speakers that discovery did not
// see. A configured speaker stays visible (online:false) because it is the
// user's own inventory, not a discovery result.
export function mergeConfigured(discovered, uciDevices) {
	let configured = configuredEntries(uciDevices);
	let result = [], seen = {};
	for (let device in discovered ?? []) {
		if (length(result) >= MAX_DEVICES)
			break;
		let normalized = normalizeDevice(device);
		if (normalized == null)
			continue;
		let key = deviceKey(normalized.engine, normalized.udn);
		if (exists(seen, key))
			continue;
		seen[key] = true;
		// Being in a fresh snapshot is what "online" means here: the device
		// answered the last scan. It is not copied from the cache entry, because a
		// hand-edited or older cache must not be able to report a discovered
		// speaker as offline. `last_seen` still comes from the entry.
		normalized.online = true;
		normalized.configured = exists(configured.entries, key);
		if (normalized.configured)
			normalized.name = configured.entries[key];
		push(result, normalized);
	}
	for (let key in configured.order) {
		if (length(result) >= MAX_DEVICES)
			break;
		if (exists(seen, key))
			continue;
		seen[key] = true;
		let parts = split(key, '\n');
		push(result, {
			engine: parts[0],
			udn: parts[1],
			original_name: null,
			name: configured.entries[key],
			model: null,
			manufacturer: null,
			address: null,
			last_seen: null,
			online: false,
			configured: true
		});
	}
	return result;
}

// A snapshot older than a day, or stamped in the future by more than a small
// clock step, is not current state: report no scan and no devices.
export function freshCache(cached, now) {
	now = now ?? time();
	let empty = { scanned_at: null, devices: [] };
	if (type(cached) != 'object' || cached == null)
		return empty;
	let stamp = integerOrNull(cached.scanned_at);
	if (stamp == null || stamp <= 0)
		return empty;
	let age = now - stamp;
	if (age > CACHE_MAX_AGE || age < -CACHE_FUTURE_SKEW)
		return empty;
	return {
		scanned_at: stamp,
		devices: type(cached.devices) == 'array' ? cached.devices : []
	};
}

// The single status reply. `now`, `scanRunning` and `scanError` are injected as
// well so the caller keeps the clock and the scan lock out of this module.
export function buildStatus(options) {
	options = options ?? {};
	let main = type(options.uciMain) == 'object' && options.uciMain != null ? options.uciMain : {};
	let state = type(options.serviceState) == 'object' && options.serviceState != null ? options.serviceState : {};
	let cached = freshCache(options.cached, options.now);
	let conflicts = [];
	for (let conflict in options.conflicts ?? [])
		if (type(conflict) == 'string' && conflict != '')
			push(conflicts, conflict);
	return {
		enabled: truthy(main.enabled),
		interface: interfaceOrNull(main.interface),
		version: stringOrNull(options.version, 64),
		services: {
			upnp: { enabled: truthy(main.airupnp), running: triState(state.upnp) },
			cast: { enabled: truthy(main.aircast), running: triState(state.cast) }
		},
		scan: {
			running: options.scanRunning === true,
			last_scan: cached.scanned_at,
			error: stringOrNull(options.scanError, 512)
		},
		conflicts: conflicts,
		devices: mergeConfigured(cached.devices, options.devices)
	};
}

// BusyBox `ps w` prints "PID USER VSZ STAT COMMAND"; procps prints
// "PID USER TIME COMMAND" and toybox "PID USER VSZ STAT COMMAND" as well. Every
// one of them has a USER column right after the pid, and the command follows a
// run of VSZ/TIME/STAT metric columns. Locating the command by shape instead of
// searching the line for "airupnp" is what keeps `grep airupnp` from looking
// like a running engine.
function metricColumn(token) {
	return match(token, /^[0-9]{1,10}$/) ||
		match(token, /^[0-9]{1,4}:[0-9]{1,2}$/) ||
		match(token, /^[RSDZTW][A-Za-z<>+*]*$/);
}

// `rest` starts at the USER column.
function executableToken(rest) {
	let tokens = split(trim(rest), /[ \t]+/);
	if (length(tokens) < 2 || tokens[0] == '')
		return null;
	let index = 1;
	if (metricColumn(tokens[index])) {
		while (index < length(tokens) && metricColumn(tokens[index]))
			index++;
	}
	return index < length(tokens) ? tokens[index] : null;
}

function basename(path) {
	let slash = rindex(path, '/');
	return slash < 0 ? path : substr(path, slash + 1);
}

// parsePsOutput(text, ownPids) returns [{ pid, name }] for every engine process
// that is not one of ours. It only reports presence: nothing here may signal,
// stop or delete a process.
export function parsePsOutput(text, ownPids) {
	let found = [];
	if (type(text) != 'string' || text == '')
		return found;
	if (length(text) > PS_TEXT_LIMIT)
		text = substr(text, 0, PS_TEXT_LIMIT);
	let own = {};
	for (let pid in ownPids ?? []) {
		let value = type(pid) == 'int' ? pid : (type(pid) == 'string' ? int(trim(pid)) : null);
		if (type(value) == 'int' && value > 0)
			own[value] = true;
	}
	for (let line in split(text, '\n')) {
		let head = match(line, /^[ \t]*([0-9]{1,10})[ \t]+([^ \t]+)[ \t]+/);
		if (!head)
			continue;
		let pid = int(head[1]);
		if (exists(own, pid))
			continue;
		let command = executableToken(substr(line, length(head[0])));
		if (command == null)
			continue;
		let name = basename(command);
		if (index(ENGINE_NAMES, name) < 0)
			continue;
		push(found, { pid: pid, name: name });
	}
	return found;
}

function cleanLine(value) {
	let out = '';
	for (let i = 0; i < length(value); i++) {
		let c = ord(value, i);
		// Carriage returns come from CRLF logs; other control bytes are either
		// corruption or an attempt to forge terminal output in the page.
		if (c == 0x0d || c == 0 || c == 0x7f || (c < 0x20 && c != 0x09))
			continue;
		out += chr(c);
	}
	return length(out) > MAX_LINE_BYTES ? substr(out, 0, MAX_LINE_BYTES) : out;
}

// stripControl is the same cleaning for a single value (an error message, a
// command's output) rather than a log line. It keeps tabs and drops every other
// control byte, including CR, because the result is shown in the page and never
// re-emitted as a file.
export function stripControl(value, maxBytes) {
	if (type(value) != 'string')
		return '';
	maxBytes = integerOrNull(maxBytes) ?? MAX_LINE_BYTES;
	let out = '';
	for (let i = 0; i < length(value) && length(out) < maxBytes; i++) {
		let c = ord(value, i);
		if (c == 0 || c == 0x7f || (c < 0x20 && c != 0x09))
			continue;
		out += chr(c);
	}
	return out;
}

// tailLines(text, maxLines, maxBytes) keeps the newest lines, strips control
// bytes, and respects both caps. `truncated` is true when anything was dropped.
export function tailLines(text, maxLines, maxBytes) {
	let result = { lines: [], truncated: false };
	if (type(text) != 'string' || text == '')
		return result;
	maxLines = integerOrNull(maxLines) ?? 200;
	maxBytes = integerOrNull(maxBytes) ?? PS_TEXT_LIMIT;
	if (maxLines < 1 || maxBytes < 1) {
		result.truncated = true;
		return result;
	}
	let lines = split(text, '\n');
	// A trailing newline terminates the last line; it does not start an empty one.
	if (length(lines) && lines[length(lines) - 1] == '')
		pop(lines);
	let kept = [], bytes = 0;
	for (let i = length(lines) - 1; i >= 0; i--) {
		if (length(kept) >= maxLines) {
			result.truncated = true;
			break;
		}
		if (length(lines[i]) > MAX_LINE_BYTES)
			result.truncated = true;
		let line = cleanLine(lines[i]);
		let cost = length(line) + (length(kept) ? 1 : 0);
		if (length(kept) && bytes + cost > maxBytes) {
			result.truncated = true;
			break;
		}
		if (!length(kept) && cost > maxBytes) {
			line = substr(line, 0, maxBytes);
			cost = length(line);
			result.truncated = true;
		}
		push(kept, line);
		bytes += cost;
	}
	result.lines = reverse(kept);
	return result;
}

// Whether procd reports the state the requested action was supposed to reach.
// Returns true/false when the answer is known and null when it cannot be
// verified (ubus unavailable, or an engine whose state is unknown), so a caller
// never turns "no answer" into a success claim.
//
// The expected state mirrors the init script exactly: with the service disabled
// or no engine selected, start/restart publishes nothing, so nothing may run.
export function actionSatisfied(action, serviceState, uciMain) {
	let state = type(serviceState) == 'object' && serviceState != null ? serviceState : {};
	if (state.upnp !== true && state.upnp !== false)
		return null;
	if (state.cast !== true && state.cast !== false)
		return null;
	let running = { upnp: state.upnp === true, cast: state.cast === true };
	if (action == 'stop')
		return !running.upnp && !running.cast;
	if (action != 'start' && action != 'restart')
		return null;
	let main = type(uciMain) == 'object' && uciMain != null ? uciMain : {};
	let expected = [];
	if (truthy(main.enabled)) {
		if (truthy(main.airupnp))
			push(expected, 'upnp');
		if (truthy(main.aircast))
			push(expected, 'cast');
	}
	for (let engine in ['upnp', 'cast']) {
		let wanted = index(expected, engine) >= 0;
		if (running[engine] != wanted)
			return false;
	}
	return true;
}

// clampErrors bounds what validate() can send back: a configuration with many
// bad fields must not turn into an unbounded ubus reply.
export function clampErrors(list) {
	let result = [];
	if (type(list) != 'array')
		return result;
	for (let item in list) {
		if (length(result) >= MAX_ERRORS)
			break;
		let message = messageOf(item);
		if (message == '')
			continue;
		if (length(message) > MAX_ERROR_BYTES)
			message = substr(message, 0, MAX_ERROR_BYTES);
		push(result, message);
	}
	return result;
}
