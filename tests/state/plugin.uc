// SPDX-License-Identifier: MIT
// Host-side integration tests for the rpcd plugin's I/O paths.
//
// The plugin is executed through loadfile() with a sandbox root
// (AIRCONNECT_MANAGER_ROOT) and fake `uci`/`ubus` modules on the module search
// path. That covers what the pure suites cannot: cache read/write, the 24 hour
// staleness rule, log tailing and truncation, conflict detection, and the
// action/scan refusals.
//
// It proves NOTHING about a real router: there is no ubusd, no netifd, no procd
// and no SSDP here. The fake ubus answers exactly the three calls the plugin
// makes, and the fake uci returns the sections described by a JSON file.
//
// The ucode module cache is process-wide, so the two stubs are installed once
// and read their behaviour from <stubdir>/config.json on every call. Because the
// sandbox root is fixed for the lifetime of the process, the suite is started by
// tests/state/check-plugin.sh, which creates the sandbox and exports
// AIRCONNECT_MANAGER_ROOT, the stub directory and UCODE_STUB_DIR.
//
// Run: bash tests/state/check-plugin.sh   (which runs this file)

import * as fs from 'fs';

const PLUGIN = fs.dirname(sourcepath()) +
	'/../../packages/airconnect-manager/files/usr/share/rpcd/ucode/airconnect-manager';
const STUBS = getenv('AIRCONNECT_MANAGER_STUBS');
const STUB_CONFIG = STUBS + '/config.json';

let passed = 0;
let failed = 0;

function assert(condition, message) {
	if (!condition)
		die(message || 'assertion failed');
}

function deepEqual(actual, expected, path) {
	path = path || 'value';
	assert(type(actual) == type(expected), path + ': type mismatch (' + type(actual) + ' vs ' + type(expected) + ')');
	if (type(actual) == 'array') {
		assert(length(actual) == length(expected), path + ': array size mismatch');
		for (let i = 0; i < length(expected); i++)
			deepEqual(actual[i], expected[i], path + '[' + i + ']');
	}
	else if (type(actual) == 'object') {
		assert(length(actual) == length(expected), path + ': object size mismatch (' + length(actual) + ' vs ' + length(expected) + ')');
		for (let key in keys(expected)) {
			assert(exists(actual, key), path + '.' + key + ': missing key');
			deepEqual(actual[key], expected[key], path + '.' + key);
		}
	}
	else
		assert(actual === expected, path + ': unexpected value ' + sprintf('%J', actual));
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

function shellQuote(value) {
	return "'" + replace(value, "'", "'\\''") + "'";
}

function repeated(value, count) {
	let result = '';
	for (let i = 0; i < count; i++)
		result += value;
	return result;
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

// --- sandbox ---------------------------------------------------------------

if (STUBS == null || STUBS == '')
	die('AIRCONNECT_MANAGER_STUBS is not set; run this through tests/state/check-plugin.sh');

const ROOT = getenv('AIRCONNECT_MANAGER_ROOT');
if (ROOT == null || ROOT == '')
	die('AIRCONNECT_MANAGER_ROOT is not set; run this through tests/state/check-plugin.sh');

function sandbox() {
	removeTree(ROOT);
	mkdirp(ROOT);
	return ROOT;
}

// The fake uci and ubus modules are installed once; their behaviour comes from
// <stubs>/config.json, rewritten by each test.
writeFile(STUBS + '/uci.uc',
	'import * as fs from "fs";\n' +
	'let self = fs.dirname(sourcepath());\n' +
	'({ cursor: function() { return {\n' +
	'  load: function(name) { },\n' +
	'  get_all: function(name, section) {\n' +
	'    let config = json(fs.readfile(self + "/config.json")) ?? {};\n' +
	'    return config.main ?? null;\n' +
	'  },\n' +
	'  foreach: function(name, kind, callback) {\n' +
	'    let config = json(fs.readfile(self + "/config.json")) ?? {};\n' +
	'    for (let device in config.devices ?? [])\n' +
	'      if (callback(device) === false)\n' +
	'        break;\n' +
	'    return true;\n' +
	'  }\n' +
	'}; } })\n');

writeFile(STUBS + '/ubus.uc',
	'import * as fs from "fs";\n' +
	'let self = fs.dirname(sourcepath());\n' +
	'({ connect: function() { return {\n' +
	'  call: function(object, method, args) {\n' +
	'    let config = json(fs.readfile(self + "/config.json")) ?? {};\n' +
	'    if (object == "service" && method == "list") {\n' +
	'      let reply = {};\n' +
	'      let services = config.services ?? {};\n' +
	'      if (services[args.name] != null)\n' +
	'        reply[args.name] = services[args.name];\n' +
	'      return reply;\n' +
	'    }\n' +
	'    if (object == "network.device" && method == "status")\n' +
	'      return { "ipv4-address": [ { address: "192.0.2.10" } ] };\n' +
	'    return {};\n' +
	'  }\n' +
	'}; } })\n');

// Configure the stubs for one test.
function stub(options) {
	options = options ?? {};
	let config = {
		main: options.main ?? {
			enabled: '1', interface: 'br-lan', airupnp: '1', aircast: '0', codec: 'flac',
			latency: '1000:2000', max_volume: '100', media_volume: '0.5', log_level: 'warn'
		},
		devices: options.devices ?? [],
		services: options.services ?? {}
	};
	writeFile(STUB_CONFIG, sprintf('%J\n', config));
}

// A fresh plugin instance. Every loadfile() call re-executes the file, so the
// plugin's own top-level state (the cached ubus connection, the runtime API) is
// rebuilt each time.
function plugin() {
	return loadfile(PLUGIN)()['airconnect.manager'];
}

function instances(list) {
	let result = { instances: {} };
	for (let name in list ?? {})
		result.instances[name] = list[name];
	return result;
}

function discovered(engine, udn, extra) {
	let device = {
		engine: engine, udn: udn, original_name: 'Demo Speaker', model: 'Demo Model',
		manufacturer: 'Demo Manufacturer', address: '192.0.2.20',
		last_seen: 1700000000, online: true
	};
	for (let key in extra ?? {})
		device[key] = extra[key];
	return device;
}

function configDevice(engine, udn, name) {
	let device = { '.name': 'cfg_' + udn, '.type': 'device', engine: engine, udn: udn };
	if (name != null)
		device.name = name;
	return device;
}

// --- status ----------------------------------------------------------------

test('status reports UCI state, procd state, version and cached devices', () => {
	let root = sandbox();
	stub({
		services: { 'airconnect-manager': instances({ upnp: { running: true, pid: 4242 } }) },
		devices: [configDevice('upnp', 'uuid:demo-1', 'Configured')]
	});
	writeFile(root + '/usr/share/airconnect-manager/VERSION', '0.1.0\n');
	writeFile(root + '/var/lib/airconnect-manager/devices.json', sprintf('%J\n',
		{ scanned_at: time() - 60, devices: [discovered('upnp', 'uuid:demo-1'), discovered('cast', 'uuid:demo-2')] }));
	let reply = plugin().status.call({ args: {} });
	assert(reply.enabled === true && reply.interface == 'br-lan', 'UCI state not read');
	assert(reply.version == '0.1.0', 'version not read: ' + sprintf('%J', reply.version));
	assert(reply.services.upnp.running === true, 'upnp must be running');
	assert(reply.services.cast.running === false, 'cast must be stopped');
	assert(reply.services.upnp.enabled === true && reply.services.cast.enabled === false, 'engine selection wrong');
	assert(length(reply.devices) == 2, 'expected two devices, got ' + length(reply.devices));
	assert(reply.devices[0].udn == 'uuid:demo-1' && reply.devices[0].configured === true, 'configured device lost');
	assert(reply.devices[0].name == 'Configured', 'the configured name must win over the discovered one');
	assert(reply.devices[1].udn == 'uuid:demo-2' && reply.devices[1].configured === false, 'unconfigured device lost');
	assert(reply.scan.last_scan != null, 'last_scan missing');
});

test('status reports running:false when procd does not know the service', () => {
	let root = sandbox();
	stub({});
	plugin().status.call({ args: {} });
	let reply = plugin().status.call({ args: {} });
	// The fake ubus answers and knows no such service: procd said "not running",
	// which is a known false and must not be reported as unknown.
	assert(reply.services.upnp.running === false, 'expected false, got ' + sprintf('%J', reply.services.upnp.running));
	assert(reply.services.cast.running === false, 'expected false');
});

test('status ignores a cache older than 24 hours', () => {
	let root = sandbox();
	stub({ devices: [configDevice('upnp', 'uuid:demo-1', 'Configured')] });
	writeFile(root + '/var/lib/airconnect-manager/devices.json', sprintf('%J\n',
		{ scanned_at: time() - 90000, devices: [discovered('cast', 'uuid:demo-stale')] }));
	let reply = plugin().status.call({ args: {} });
	assert(reply.scan.last_scan === null, 'a stale scan must not be reported');
	assert(length(reply.devices) == 1 && reply.devices[0].udn == 'uuid:demo-1', 'configured device missing');
	assert(reply.devices[0].online === false, 'a configured device with no discovery must be offline');
	assert(reply.devices[0].model === null && reply.devices[0].address === null, 'facts must not be invented');
});

test('status survives a corrupt cache and a missing VERSION', () => {
	let root = sandbox();
	stub({});
	writeFile(root + '/var/lib/airconnect-manager/devices.json', '{not json');
	let reply = plugin().status.call({ args: {} });
	deepEqual(reply.devices, []);
	assert(reply.version === null, 'a missing VERSION must be null');
	assert(reply.scan.last_scan === null, 'a corrupt cache must not report a scan');
});

test('status reports an invalid VERSION token as unknown', () => {
	let root = sandbox();
	stub({});
	writeFile(root + '/usr/share/airconnect-manager/VERSION', 'not a version\n');
	assert(plugin().status.call({ args: {} }).version === null, 'a malformed VERSION must not be shown');
});

test('status never starts a scan', () => {
	let root = sandbox();
	stub({});
	plugin().status.call({ args: {} });
	assert(fs.stat(root + '/var/lib/airconnect-manager/scan.lock') == null, 'status took the scan lock');
	assert(fs.stat(root + '/var/lib/airconnect-manager/devices.json') == null, 'status wrote a cache file');
});

test('status reports scan.error from the cache so a failed scan is visible', () => {
	let root = sandbox();
	stub({});
	writeFile(root + '/var/lib/airconnect-manager/devices.json', sprintf('%J\n',
		{ scanned_at: time() - 30, devices: [], error: 'no IPv4 address is available on the selected interface' }));
	let reply = plugin().status.call({ args: {} });
	assert(reply.scan.error == 'no IPv4 address is available on the selected interface', 'scan error lost');
});

// --- conflicts -------------------------------------------------------------

test('a legacy init script that procd reports running is a conflict', () => {
	let root = sandbox();
	stub({ services: { airconnect: instances({ instance1: { running: true, pid: 900 } }) } });
	writeFile(root + '/etc/init.d/airconnect', '#!/bin/sh\n');
	deepEqual(plugin().status.call({ args: {} }).conflicts, ["Legacy service 'airconnect' is running."]);
});

test('a legacy init script that is not running is not a conflict', () => {
	let root = sandbox();
	stub({ services: { airconnect: instances({ instance1: { running: false } }) } });
	writeFile(root + '/etc/init.d/airconnect', '#!/bin/sh\n');
	deepEqual(plugin().status.call({ args: {} }).conflicts, []);
});

test('legacy binaries in /usr/bin are a conflict, reported once', () => {
	let root = sandbox();
	stub({});
	writeFile(root + '/usr/bin/airupnp', 'binary');
	writeFile(root + '/usr/bin/aircast', 'binary');
	deepEqual(plugin().status.call({ args: {} }).conflicts, ['Legacy binaries found in /usr/bin.']);
});

test('conflict detection never deletes or modifies what it finds', () => {
	let root = sandbox();
	stub({ services: { airconnect: instances({ instance1: { running: true } }) } });
	writeFile(root + '/usr/bin/airupnp', 'binary');
	writeFile(root + '/etc/init.d/airconnect', '#!/bin/sh\n');
	plugin().status.call({ args: {} });
	assert(fs.stat(root + '/usr/bin/airupnp') != null, 'the legacy binary was removed');
	assert(fs.readfile(root + '/usr/bin/airupnp') === 'binary', 'the legacy binary was modified');
	assert(fs.stat(root + '/etc/init.d/airconnect') != null, 'the legacy init script was removed');
});

// --- action ----------------------------------------------------------------

test('action refuses an unknown action name instead of running anything', () => {
	let root = sandbox();
	stub({});
	writeFile(root + '/etc/init.d/airconnect-manager',
		'#!/bin/sh\ntouch ' + root + '/var/lib/airconnect-manager/action-ran\nexit 0\n');
	fs.chmod(root + '/etc/init.d/airconnect-manager', 0755);
	let threw = false;
	try {
		plugin().action.call({ args: { action: 'reboot' } });
	}
	catch (error) {
		threw = true;
	}
	assert(threw, 'an unknown action must die');
	assert(fs.stat(root + '/var/lib/airconnect-manager/action-ran') == null, 'something ran');
});

test('action refuses to start while a legacy instance is present', () => {
	let root = sandbox();
	stub({});
	writeFile(root + '/usr/bin/airupnp', 'binary');
	writeFile(root + '/etc/init.d/airconnect-manager',
		'#!/bin/sh\ntouch ' + root + '/var/lib/airconnect-manager/action-ran\nexit 0\n');
	fs.chmod(root + '/etc/init.d/airconnect-manager', 0755);
	deepEqual(plugin().action.call({ args: { action: 'start' } }),
		{ ok: false, error: 'Conflicting AirConnect instance detected' });
	assert(fs.stat(root + '/var/lib/airconnect-manager/action-ran') == null, 'the init script ran despite the conflict');
});

test('action refuses restart while a legacy instance is present', () => {
	let root = sandbox();
	stub({});
	writeFile(root + '/usr/bin/aircast', 'binary');
	deepEqual(plugin().action.call({ args: { action: 'restart' } }),
		{ ok: false, error: 'Conflicting AirConnect instance detected' });
});

test('stop is allowed while a legacy instance is present', () => {
	let root = sandbox();
	stub({ services: { 'airconnect-manager': instances({ upnp: { running: false } }) } });
	writeFile(root + '/usr/bin/airupnp', 'binary');
	writeFile(root + '/etc/init.d/airconnect-manager', '#!/bin/sh\nexit 0\n');
	fs.chmod(root + '/etc/init.d/airconnect-manager', 0755);
	deepEqual(plugin().action.call({ args: { action: 'stop' } }), { ok: true });
});

test('action reports the init script output when it fails', () => {
	let root = sandbox();
	stub({});
	writeFile(root + '/etc/init.d/airconnect-manager',
		'#!/bin/sh\necho "engine binary is missing" >&2\nexit 1\n');
	fs.chmod(root + '/etc/init.d/airconnect-manager', 0755);
	let reply = plugin().action.call({ args: { action: 'restart' } });
	assert(reply.ok === false, 'a failing command must report ok:false');
	assert(index(reply.error, 'engine binary is missing') >= 0, 'the command output was lost: ' + reply.error);
});

test('action does not claim success when procd reports the service still stopped', () => {
	let root = sandbox();
	// The script exits 0 but procd still reports the engine stopped, so the exit
	// code alone is not evidence of a start.
	stub({ services: { 'airconnect-manager': instances({ upnp: { running: false } }) } });
	writeFile(root + '/etc/init.d/airconnect-manager', '#!/bin/sh\nexit 0\n');
	fs.chmod(root + '/etc/init.d/airconnect-manager', 0755);
	deepEqual(plugin().action.call({ args: { action: 'start' } }),
		{ ok: false, error: 'procd did not start the service' });
});

test('action reports success when procd agrees the engine is running', () => {
	let root = sandbox();
	stub({ services: { 'airconnect-manager': instances({ upnp: { running: true, pid: 77 } }) } });
	writeFile(root + '/etc/init.d/airconnect-manager', '#!/bin/sh\nexit 0\n');
	fs.chmod(root + '/etc/init.d/airconnect-manager', 0755);
	deepEqual(plugin().action.call({ args: { action: 'start' } }), { ok: true });
});

test('action reports failure when a stop leaves an engine running', () => {
	let root = sandbox();
	stub({ services: { 'airconnect-manager': instances({ upnp: { running: true } }) } });
	writeFile(root + '/etc/init.d/airconnect-manager', '#!/bin/sh\nexit 0\n');
	fs.chmod(root + '/etc/init.d/airconnect-manager', 0755);
	deepEqual(plugin().action.call({ args: { action: 'stop' } }),
		{ ok: false, error: 'The service is still running' });
});

// --- scan ------------------------------------------------------------------

test('scan refuses when both engines are disabled', () => {
	let root = sandbox();
	stub({ main: { enabled: '1', airupnp: '0', aircast: '0' } });
	deepEqual(plugin().scan.call({ args: {} }), { ok: false, error: 'No discovery engine is enabled' });
	assert(fs.stat(root + '/var/lib/airconnect-manager/scan.lock') == null, 'a refused scan took the lock');
});

test('scan refuses an invalid interface token through config.uc', () => {
	let root = sandbox();
	stub({ main: { enabled: '1', airupnp: '1', interface: 'not an interface' } });
	let reply = plugin().scan.call({ args: {} });
	assert(reply.ok === false, 'an invalid interface must be rejected');
	assert(index(reply.error, 'main.interface:') >= 0, 'unexpected error: ' + reply.error);
});

test('scan refuses while a live lock exists', () => {
	let root = sandbox();
	stub({});
	writeFile(root + '/var/lib/airconnect-manager/scan.lock', '1\n');
	deepEqual(plugin().scan.call({ args: {} }), { ok: false, error: 'A scan is already running' });
});

test('scan reports failure and leaves no lock when the worker cannot start', () => {
	let root = sandbox();
	stub({});
	// /usr/bin/ucode does not exist inside the sandbox, so the worker cannot be
	// started and scan must say so rather than answering ok:true.
	deepEqual(plugin().scan.call({ args: {} }), { ok: false, error: 'Could not start the discovery worker' });
	assert(fs.stat(root + '/var/lib/airconnect-manager/scan.lock') == null, 'a failed spawn left the lock behind');
});

// The worker branch is what actually performs discovery, so it is exercised here
// directly: the same file, executed with the fixed `scan-worker` argument. The
// host has no netifd, so discovery fails - and the point of this test is that the
// failure is recorded, the previous snapshot survives, and the lock is released.
test('the scan worker records a failure, keeps the old snapshot and releases the lock', () => {
	let root = sandbox();
	stub({});
	let previous = { scanned_at: time() - 100, devices: [discovered('upnp', 'uuid:demo-keep')] };
	writeFile(root + '/var/lib/airconnect-manager/devices.json', sprintf('%J\n', previous));
	writeFile(root + '/var/lib/airconnect-manager/scan.lock', '1\n');
	let ucode = getenv('UCODE');
	assert(ucode != null && ucode != '', 'UCODE is not set; run this through tests/state/check-plugin.sh');
	let command = 'AIRCONNECT_MANAGER_ROOT=' + shellQuote(root) + ' ' +
		shellQuote(ucode) + ' -L ' + shellQuote(STUBS) + ' -L ' +
		shellQuote(getenv('UCODE_LIB')) + ' ' + shellQuote(PLUGIN) + ' scan-worker 2>&1';
	let proc = fs.popen(command, 'r');
	assert(proc != null, 'could not run the worker');
	let output = proc.read(65536) ?? '';
	let code = proc.close();
	assert(code != 0, 'a failed scan must exit nonzero: ' + output);
	assert(fs.stat(root + '/var/lib/airconnect-manager/scan.lock') == null, 'the worker did not release the lock');
	let cache = json(fs.readfile(root + '/var/lib/airconnect-manager/devices.json'));
	assert(type(cache) == 'object' && cache != null, 'the cache was not written');
	assert(type(cache.error) == 'string' && cache.error != '', 'the failure was not recorded');
	assert(cache.scanned_at == previous.scanned_at, 'a failed scan must not claim a fresh scan time');
	assert(length(cache.devices) == 1 && cache.devices[0].udn == 'uuid:demo-keep', 'the previous snapshot was lost');
});

test('the scan worker does not register an object when run as a program', () => {
	let root = sandbox();
	stub({ main: { enabled: '1', airupnp: '0', aircast: '0' } });
	writeFile(root + '/var/lib/airconnect-manager/scan.lock', '1\n');
	let command = 'AIRCONNECT_MANAGER_ROOT=' + shellQuote(root) + ' ' +
		shellQuote(getenv('UCODE')) + ' -L ' + shellQuote(STUBS) + ' -L ' +
		shellQuote(getenv('UCODE_LIB')) + ' ' + shellQuote(PLUGIN) + ' scan-worker 2>&1';
	let proc = fs.popen(command, 'r');
	let output = proc.read(65536) ?? '';
	proc.close();
	// The worker exits before the signature is returned, so nothing can ever be
	// registered and stdout stays empty.
	assert(output == '', 'the worker printed something: ' + output);
	assert(fs.stat(root + '/var/lib/airconnect-manager/scan.lock') == null, 'the worker did not release the lock');
});

// --- logs ------------------------------------------------------------------

test('logs tails a log file, strips control bytes and reports truncation', () => {
	let root = sandbox();
	stub({});
	let lines = [];
	for (let i = 0; i < 300; i++)
		push(lines, 'line ' + i + '\r');
	writeFile(root + '/var/log/airconnect-manager.log', join('\n', lines) + '\n');
	let reply = plugin().logs.call({ args: {} });
	assert(reply.truncated === true, 'more than 200 lines must be reported as truncated');
	assert(length(reply.lines) == 200, 'expected 200 lines, got ' + length(reply.lines));
	assert(reply.lines[length(reply.lines) - 1] == 'line 299', 'the newest line must be last');
	assert(index(reply.lines[0], '\r') < 0, 'a CR survived');
});

test('logs returns an empty list when there is no log at all', () => {
	let root = sandbox();
	stub({});
	deepEqual(plugin().logs.call({ args: {} }), { lines: [], truncated: false });
});

test('logs caps a single line and reports the cap', () => {
	let root = sandbox();
	stub({});
	writeFile(root + '/var/log/airconnect-manager.log', repeated('x', 4000) + '\n');
	let reply = plugin().logs.call({ args: {} });
	assert(length(reply.lines) == 1, 'expected one line');
	assert(length(reply.lines[0]) == 512, 'the line was not capped');
	assert(reply.truncated === true, 'the cap must be reported');
});

test('logs merges the per-engine logs after the manager log', () => {
	let root = sandbox();
	stub({});
	writeFile(root + '/var/log/airconnect-manager.log', 'manager\n');
	writeFile(root + '/var/log/airconnect-manager/upnp.log', 'upnp engine\n');
	writeFile(root + '/var/log/airconnect-manager/cast.log', 'cast engine\n');
	deepEqual(plugin().logs.call({ args: {} }).lines, ['manager', 'upnp engine', 'cast engine']);
});

test('logs never returns a path, an environment value or a config value', () => {
	let root = sandbox();
	stub({ main: { enabled: '1', interface: 'br-secret', airupnp: '1', max_volume: '42' } });
	writeFile(root + '/var/log/airconnect-manager.log', 'plain engine output\n');
	let reply = plugin().logs.call({ args: {} });
	for (let line in reply.lines) {
		assert(index(line, root) < 0, 'a sandbox path leaked into the log reply');
		assert(index(line, 'br-secret') < 0, 'a config value leaked into the log reply');
	}
});

removeTree(ROOT);

print('1..', passed + failed, '\n', passed, ' passed; ', failed, ' failed\n');
exit(failed ? 1 : 0);
