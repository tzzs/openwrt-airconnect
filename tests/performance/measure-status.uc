// SPDX-License-Identifier: MIT
// Status and logs reply-size measurement.
//
//   bash tests/performance/measure-status.sh
//
// This drives the REAL rpcd plugin (loadfile of
// packages/airconnect-manager/files/usr/share/rpcd/ucode/airconnect-manager)
// against the same sandbox root and fake `uci`/`ubus` modules that
// tests/state/plugin.uc uses - the fakes are shared, not re-implemented, so this
// suite cannot pass against a more forgiving backend than the state suite.
//
// The measured quantity is the size of the JSON rpcd would put on the wire for
// one reply: `length(sprintf('%J', reply))`. That is the byte count the poll
// described in docs/PERFORMANCE.zh-CN.md pays every 10 seconds, so it is the
// number the budget is about. It is not the HTTP payload (rpcd/LuCI add
// envelope and headers around it), and it is not the string length in
// characters: ucode's length() counts bytes.
//
// What this suite proves
// ----------------------
//   * the reply size for 1, 8, 32 and 64 devices, measured not estimated;
//   * the 64-device cap actually holds at 128 candidates (the constant in
//     state.uc is not just a comment), and the reply does not grow past it;
//   * the logs reply at its documented caps (200 lines, 64 KiB of text) and that
//     the caps are enforced on a log file that exceeds both;
//   * what JSON escaping does to that bounded text - the real worst case for the
//     `logs` reply, and the reason its budget is generous;
//   * how many subprocesses one status/logs call spawns, which is the only part
//     of the router-side cost a host can observe.
//
// What it does NOT prove: router CPU, the RPC round trip, ubus blob overhead,
// browser parse time, or the size of a reply from a real router's procd/netifd.
//
// Exit status: 0 when every budget holds, 1 when a budget is exceeded or an
// assertion fails, 2 when the run is broken (missing environment).

import * as fs from 'fs';
import { install as installStubs, configure as configureStubs } from '../state/stubs.uc';

// --- environment ------------------------------------------------------------

const STUBS = getenv('AIRCONNECT_MANAGER_STUBS');
const ROOT = getenv('AIRCONNECT_MANAGER_ROOT');
if (STUBS == null || STUBS == '')
	die('AIRCONNECT_MANAGER_STUBS is not set; run this through tests/performance/measure-status.sh');
if (ROOT == null || ROOT == '')
	die('AIRCONNECT_MANAGER_ROOT is not set; run this through tests/performance/measure-status.sh');

const HERE = fs.dirname(sourcepath());
const PLUGIN = HERE + '/../../packages/airconnect-manager/files/usr/share/rpcd/ucode/airconnect-manager';
const STATE_DIR = ROOT + '/var/lib/airconnect-manager';
const LOG_FILE = ROOT + '/var/log/airconnect-manager.log';

let passed = 0;
let failed = 0;

function assert(condition, message) {
	if (!condition)
		die(message || 'assertion failed');
}

function test(label, callback) {
	try {
		callback();
		passed++;
		print('ok ', passed + failed, ' - ', label, '\n');
	}
	catch (error) {
		failed++;
		print('not ok ', passed + failed, ' - ', label, ': ', error.message, '\n');
	}
}

function removeTree(path) {
	let info = fs.lstat(path);
	if (info == null)
		return;
	if (info.type == 'directory') {
		for (let name in fs.lsdir(path) ?? [])
			removeTree(path + '/' + name);
		fs.rmdir(path);
	}
	else
		fs.unlink(path);
}

function mkdirp(path) {
	let parts = split(path, '/'), current = '';
	for (let part in parts) {
		if (part == '')
			continue;
		current += '/' + part;
		if (fs.stat(current) == null)
			fs.mkdir(current, 0750);
	}
}

function writeFile(path, data) {
	mkdirp(substr(path, 0, rindex(path, '/')));
	fs.writefile(path, data);
}

function repeated(value, count) {
	let out = '';
	for (let i = 0; i < count; i++)
		out += value;
	return out;
}

// --- fixtures ---------------------------------------------------------------
// Sizes are the maxima the backend's own string limits allow (state.uc:
// stringOrNull(udn, 255), stringOrNull(udn) on the device, 63 for the AirPlay
// name, 128 for model/manufacturer, 45 for an address). Measuring at the limits
// rather than with short demo strings is the difference between a number that
// survives a real LAN and one that does not.

function udn(index) {
	// "uuid:" + 36 hex characters, the longest legal UUID string, so the byte
	// count is the worst case a real discovered speaker can present.
	return 'uuid:' + substr(sprintf('%08x', index), 0, 8) + '-0000-4000-8000-' +
		repeated('a', 11) + sprintf('%x', index % 16);
}

function longName(index) {
	// 63 bytes, the cap state.uc applies to an AirPlay name.
	return substr('Example living room speaker number ' + index + ' ', 0, 63);
}

function longText(prefix, index) {
	// 128 bytes, the cap for model and manufacturer.
	return substr(repeated(prefix + ' ', 32), 0, 128);
}

function discoveredDevice(index) {
	return {
		engine: index % 2 ? 'upnp' : 'cast',
		udn: udn(index),
		original_name: longName(index),
		model: longText('Model', index),
		manufacturer: longText('Manufacturer', index),
		address: '192.0.2.' + (1 + (index % 254)),
		last_seen: 1700000000 - index,
		online: true
	};
}

function configuredDevice(index) {
	let device = { '.name': 'cfg' + index, '.type': 'device', engine: index % 2 ? 'upnp' : 'cast', udn: udn(index) };
	if (index % 3 != 0)
		device.name = longName(index);
	return device;
}

// A fresh plugin instance. loadfile() re-executes the file, so the plugin's own
// per-process state (the cached ubus connection, the runtime API) is rebuilt and
// one test cannot leak into the next.
function plugin() {
	return loadfile(PLUGIN)()['airconnect.manager'];
}

function newSandbox() {
	removeTree(ROOT);
	mkdirp(ROOT);
	installStubs(STUBS);
	// The plugin shells out to `ps w` on every status call to detect a foreign
	// engine (detectConflicts). Installing a fake one in the sandbox keeps that
	// path exercised without depending on the host's process table, and lets the
	// spawn count below be measured instead of assumed. It reports no engine, so
	// the reply sizes below are the ordinary no-conflict case; instrumentPs()
	// replaces it with one that records its own invocations.
	writeFile(ROOT + '/bin/ps', '#!/bin/sh\n' +
		'printf "  PID USER       VSZ STAT COMMAND\\n"\n');
	fs.chmod(ROOT + '/bin/ps', 0755);
	return ROOT;
}

// How many times the plugin executed `ps`, so a per-poll subprocess can be
// reported as a fact rather than left as an implementation detail nobody read.
const PS_COUNTER = STUBS + '/ps-count';

// Defined before its first caller on purpose: ucode initialises top-level
// function declarations in source order, so a function declared further down the
// file is still null when an earlier top-level statement runs a test that calls
// it.
function shellQuote(value) {
	return "'" + replace(value, "'", "'\\''") + "'";
}

function countPsSpawns() {
	// One byte per spawn, so the file's size is the count. Appending a byte is
	// cheaper and more reliable than parsing a number from a shell loop.
	let info = fs.stat(PS_COUNTER);
	return info == null ? 0 : info.size;
}

function instrumentPs() {
	writeFile(ROOT + '/bin/ps', '#!/bin/sh\n' +
		'printf x >> ' + shellQuote(PS_COUNTER) + '\n' +
		'printf "  PID USER       VSZ STAT COMMAND\\n"\n' +
		'printf " 9001 root      1580 S    airupnp -Z -x /var/etc/evil.xml\\n"\n');
	fs.chmod(ROOT + '/bin/ps', 0755);
	fs.writefile(PS_COUNTER, '');
}

function replyBytes(reply) {
	return length(sprintf('%J', reply));
}

function kib(bytes) {
	return sprintf('%.1f KiB', bytes / 1024);
}

// --- the measurement --------------------------------------------------------

const DEVICE_COUNTS = [1, 8, 32, 64];

// Budget: the serialized `status` reply with 64 devices - the backend's own
// hard cap - must stay under 64 KiB. Measured value at the documented per-device
// field maxima (see the table printed below): 35,167 bytes. The cap is 64 KiB,
// +86 % over the measurement, because a 64-device reply is already the worst case
// the backend permits and a new per-device field of a few dozen bytes should not
// force a cap edit. It still fails loudly if status starts carrying something it
// should not - a log tail, the rendered XML, an icon per device.
//
// Note for a reader: 64 speakers is not a home LAN. The 1-device number below is
// the one that describes real usage; this one describes the bound.
const STATUS_CAP_64 = 65536;
// Budget for the single-device reply. Measured: 792 bytes. 4 KiB is +417 % over
// that, which leaves room for several added fields per device and for a longer
// version string, while catching a regression that embeds the device XML or a
// log tail in the reply.
const STATUS_CAP_1 = 4096;
// Budget for the logs reply. The backend bounds the TEXT at 65536 bytes
// (TAIL_BYTES) and each line at 512 bytes, but the JSON rpcd puts on the wire is
// larger, and by how much depends on what the log contains: a quote or a
// backslash becomes two bytes when serialized. Measured on this build: 65,150
// bytes of plain ASCII lines serialize to 65,566 bytes (ratio 1.00), while the
// same 65,150 bytes of backslashes serialize to 130,590 bytes (ratio 2.00). The
// cap is therefore 160 KiB, i.e. the 128 KiB an exact 2x escape would produce plus
// the `lines`/`truncated` envelope and a little slack - not the ~1.5x a
// guess would have picked. It can only be exceeded if the documented text caps
// stop being enforced or if a log can somehow escape into more than 2 bytes per
// byte.
const LOGS_CAP = 163840;

let statusSizes = {};
let logsSizes = {};
let statusSpawns = null;
let logsSpawns = null;

test('status reply size for 1, 8, 32 and 64 devices', () => {
	let rows = [];
	for (let count in DEVICE_COUNTS) {
		newSandbox();
		let configured = [];
		for (let i = 0; i < count; i++)
			push(configured, configuredDevice(i));
		let cached = [];
		for (let i = 0; i < count; i++)
			push(cached, discoveredDevice(i));
		configureStubs(STUBS, {
			devices: configured,
			services: { 'airconnect-manager': { instances: { upnp: { running: true, pid: 4242 } } } }
		});
		writeFile(STATE_DIR + '/devices.json', sprintf('%J\n', { scanned_at: time() - 60, devices: cached }));
		let reply = plugin().status.call({ args: {} });
		assert(length(reply.devices) == count,
			count + ' devices requested, ' + length(reply.devices) + ' in the reply');
		let bytes = replyBytes(reply);
		statusSizes[count] = bytes;
		push(rows, sprintf('      %2d device(s): %6d bytes (%s)', count, bytes, kib(bytes)));
	}
	print(join('\n', rows), '\n');
});

test('the 64-device cap holds when 128 devices are offered', () => {
	newSandbox();
	let configured = [], cached = [];
	for (let i = 0; i < 128; i++) {
		push(configured, configuredDevice(i));
		push(cached, discoveredDevice(i));
	}
	configureStubs(STUBS, {
		devices: configured,
		services: { 'airconnect-manager': { instances: { upnp: { running: true, pid: 4242 } } } }
	});
	writeFile(STATE_DIR + '/devices.json', sprintf('%J\n', { scanned_at: time() - 60, devices: cached }));
	let reply = plugin().status.call({ args: {} });
	assert(length(reply.devices) == 64,
		'expected the documented 64-device cap, got ' + length(reply.devices));
	// The reply must not grow with the number of candidates the cache holds: the
	// cap is what makes the poll size bounded, so it is asserted on bytes too.
	let bytes = replyBytes(reply);
	assert(bytes <= STATUS_CAP_64,
		'a 128-candidate reply is ' + bytes + ' bytes, over the ' + STATUS_CAP_64 + ' byte cap');
	print(sprintf('      128 candidates -> %d devices in the reply, %d bytes\n', length(reply.devices), bytes));
});

test('the single-device status reply stays under its cap', () => {
	let bytes = statusSizes[1];
	assert(bytes != null, 'the one-device measurement did not run');
	assert(bytes <= STATUS_CAP_1,
		'a one-device reply is ' + bytes + ' bytes, over the ' + STATUS_CAP_1 + ' byte cap');
	print(sprintf('      1 device: %d bytes, cap %d\n', bytes, STATUS_CAP_1));
});

test('the 64-device status reply stays under its cap', () => {
	let bytes = statusSizes[64];
	assert(bytes != null, 'the 64-device measurement did not run');
	assert(bytes <= STATUS_CAP_64,
		'a 64-device reply is ' + bytes + ' bytes, over the ' + STATUS_CAP_64 + ' byte cap');
	// A real router never has 64 speakers, but the cap is what makes the poll
	// size bounded, so it is asserted rather than described.
	print(sprintf('      64 devices: %d bytes (%s), cap %d (%s), headroom %d bytes\n',
		bytes, kib(bytes), STATUS_CAP_64, kib(STATUS_CAP_64), STATUS_CAP_64 - bytes));
});

test('logs reply size at 200 lines of a realistic log', () => {
	newSandbox();
	configureStubs(STUBS, {});
	let lines = [];
	for (let i = 0; i < 200; i++)
		push(lines, sprintf('[%s] airupnp: discovery response from 192.0.2.%d udn %s seq %d',
			'2026-10-22 02:00:00', 1 + (i % 254), udn(i), i));
	writeFile(LOG_FILE, join('\n', lines) + '\n');
	let reply = plugin().logs.call({ args: {} });
	assert(length(reply.lines) == 200, 'expected 200 lines, got ' + length(reply.lines));
	assert(reply.truncated === false, 'a log of exactly 200 lines must not report truncation');
	let bytes = replyBytes(reply);
	logsSizes.realistic = bytes;
	print(sprintf('      200 realistic lines (%d raw bytes): %d bytes JSON\n',
		length(join('\n', lines)), bytes));
	assert(bytes <= LOGS_CAP,
		'the logs reply is ' + bytes + ' bytes, over the ' + LOGS_CAP + ' byte cap');
});

test('the 200-line cap is enforced, not just documented', () => {
	newSandbox();
	configureStubs(STUBS, {});
	let lines = [];
	for (let i = 0; i < 5000; i++)
		push(lines, sprintf('[%s] airupnp: event %d from 192.0.2.%d', '2026-10-22 02:00:00', i, 1 + (i % 254)));
	writeFile(LOG_FILE, join('\n', lines) + '\n');
	let reply = plugin().logs.call({ args: {} });
	assert(length(reply.lines) == 200,
		'a 5000-line log must be cut to 200 lines, got ' + length(reply.lines));
	assert(reply.truncated === true, 'cutting a log must be reported as truncated');
	// The newest lines survive, not the oldest ones.
	assert(index(reply.lines[199], 'event 4999') >= 0, 'the newest line was dropped: ' + reply.lines[199]);
	let bytes = replyBytes(reply);
	logsSizes.cappedLines = bytes;
	print(sprintf('      5000 lines in -> %d lines out, %d bytes JSON\n', length(reply.lines), bytes));
	assert(bytes <= LOGS_CAP,
		'the capped logs reply is ' + bytes + ' bytes, over the ' + LOGS_CAP + ' byte cap');
});

test('the 64 KiB byte cap and the 512-byte line cap are enforced', () => {
	newSandbox();
	configureStubs(STUBS, {});
	// One line of 4000 bytes: the per-line cap is what must cut it. 200 of them
	// also exceed the 64 KiB text budget, so both caps are exercised at once.
	let line = repeated('x', 4000);
	let lines = [];
	for (let i = 0; i < 200; i++)
		push(lines, line);
	writeFile(LOG_FILE, join('\n', lines) + '\n');
	let reply = plugin().logs.call({ args: {} });
	assert(reply.truncated === true, 'a log over both caps must be reported as truncated');
	for (let entry in reply.lines)
		assert(length(entry) == 512, 'a line survived the 512-byte cap: ' + length(entry));
	let text = length(join('\n', reply.lines));
	assert(text <= 65536, 'the log text is ' + text + ' bytes, over the 64 KiB budget');
	let bytes = replyBytes(reply);
	logsSizes.worstCase = bytes;
	print(sprintf('      200 x 4000-byte lines in -> %d lines, %d text bytes, %d bytes JSON\n',
		length(reply.lines), text, bytes));
	assert(bytes <= LOGS_CAP,
		'the worst-case logs reply is ' + bytes + ' bytes, over the ' + LOGS_CAP + ' byte cap');
});

// The caps bound the log TEXT, not the JSON rpcd serializes from it, and JSON
// escaping is what turns a bounded reply into an unbounded-looking one: one
// backslash byte becomes two. A log written by an engine that quotes a path on
// every line is not hypothetical, so the escape ratio is measured rather than
// assumed.
test('JSON escaping is the real worst case, not plain ASCII', () => {
	newSandbox();
	configureStubs(STUBS, {});
	// 200 lines of 512 backslashes: every content byte doubles when serialized,
	// which also drives the text past the 64 KiB budget.
	let lines = [];
	for (let i = 0; i < 200; i++) {
		let line = '';
		while (length(line) < 512)
			line += '\\';
		push(lines, substr(line, 0, 512));
	}
	writeFile(LOG_FILE, join('\n', lines) + '\n');
	let reply = plugin().logs.call({ args: {} });
	let text = length(join('\n', reply.lines));
	let bytes = replyBytes(reply);
	logsSizes.escaped = bytes;
	assert(text <= 65536, 'the escaped log text is ' + text + ' bytes, over the 64 KiB budget');
	assert(bytes <= LOGS_CAP,
		'the escaped logs reply is ' + bytes + ' bytes, over the ' + LOGS_CAP + ' byte cap');
	// The ratio is the fact the cap was derived from, so it is reported even when
	// the assertion holds.
	print(sprintf('      backslash-only log: %d text bytes -> %d JSON bytes (x%.2f)\n',
		text, bytes, bytes / text));
	assert(bytes <= 2 * 65536 + 4096,
		'an escaped reply is ' + bytes + ' bytes, more than 2x the 64 KiB text budget');
});

test('an empty logs reply is not a degenerate case', () => {
	newSandbox();
	configureStubs(STUBS, {});
	let reply = plugin().logs.call({ args: {} });
	assert(length(reply.lines) == 0 && reply.truncated === false, 'expected an empty reply');
	let bytes = replyBytes(reply);
	assert(bytes > 0 && bytes <= 64, 'an empty logs reply is ' + bytes + ' bytes');
	print(sprintf('      no log file: %d bytes JSON\n', bytes));
});

// A reply size says nothing about what the router has to do to produce it. The
// only part of that cost a host can actually observe is the number of processes
// the backend spawns per call, because a fork+exec on a 600 MHz router costs
// every bit as much as the JSON. detectConflicts() runs `ps` inside every
// `status`, so it is counted here rather than described.
test('one status poll spawns at most one subprocess', () => {
	newSandbox();
	configureStubs(STUBS, {});
	instrumentPs();
	let before = countPsSpawns();
	let reply = plugin().status.call({ args: {} });
	let after = countPsSpawns();
	let spawns = after - before;
	statusSpawns = spawns;
	// Exactly one: the plugin must not also shell out to logread, uci, iwinfo or
	// the init script just to answer a status read. 0 would mean the fake was
	// bypassed and the count proves nothing.
	assert(spawns == 1,
		'one status poll spawned ' + spawns + ' processes; the fake ps counter recorded ' + after);
	assert(length(reply.conflicts) == 1, 'the fake ps must reach detectConflicts');
	print(sprintf('      status poll: %d subprocess spawn(s), %d-byte reply\n',
		spawns, replyBytes(reply)));
});

// `logs` is loaded on demand (the button, never the poll), so what matters is
// that it does not spawn one process per log source.
test('one logs call spawns at most one subprocess', () => {
	newSandbox();
	configureStubs(STUBS, {});
	writeFile(LOG_FILE, 'one line\n');
	instrumentPs();
	let before = countPsSpawns();
	plugin().logs.call({ args: {} });
	// No /sbin/logread exists in the sandbox, so no process is spawned at all:
	// the log files were read directly. The assertion is an upper bound, and the
	// measured value is printed so a behaviour change is visible.
	let spawns = countPsSpawns() - before;
	logsSpawns = spawns;
	assert(spawns == 0, 'a logs call from a log file spawned ' + spawns + ' process(es)');
	print(sprintf('      logs from a file: %d subprocess spawn(s)\n', spawns));
});

// --- summary ----------------------------------------------------------------

if (statusSizes[1] != null && statusSizes[64] != null)
	print(sprintf('\nstatus: 1 device %d B, 8 %d B, 32 %d B, 64 %d B (cap %d)\n',
		statusSizes[1], statusSizes[8], statusSizes[32], statusSizes[64], STATUS_CAP_64));
if (logsSizes.realistic != null)
	print(sprintf('logs:   200 lines %d B, 5000 lines capped %d B, 512-byte lines %d B, escaped %d B (cap %d)\n',
		logsSizes.realistic, logsSizes.cappedLines, logsSizes.worstCase, logsSizes.escaped, LOGS_CAP));
if (statusSpawns != null)
	print(sprintf('spawns: status %d, logs %d subprocess(es) per call\n', statusSpawns, logsSpawns));

removeTree(ROOT);

print('1..', passed + failed, '\n', passed, ' passed; ', failed, ' failed\n');
exit(failed ? 1 : 0);
