// SPDX-License-Identifier: MIT
// Host-side tests for runtime.uc: UCI loading, validation, atomic writes and
// the "keep the last good file" guarantee. Runs with the OpenWrt ucode host
// build; no UCI, no router, no network.
//
// Run: ucode -L ~/.local/opt/ucode-host/lib/ucode tests/runtime/run.uc
import * as fs from 'fs';
import { normalizeConfig, renderXml } from '../../packages/airconnect-manager/files/usr/share/airconnect-manager/config.uc';
import { uciMain, uciDevices, fakeCursor, rawConfig, pcmUpnpOnly, previousXml } from './fixtures.uc';

// runtime.uc is a script-mode file (see its header): it cannot be named-imported
// and instead returns its API object from a trailing expression.
// loadfile() resolves against the process working directory, unlike `import`
// which is relative to this file, so the path is anchored on sourcepath().
const RUNTIME_PATH = fs.dirname(sourcepath()) +
	'/../../packages/airconnect-manager/files/usr/share/airconnect-manager/runtime.uc';
const runtime = loadfile(RUNTIME_PATH)();

let passed = 0;
let failed = 0;
let sandbox = null;

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
		assert(length(actual) == length(expected), path + ': object size mismatch');
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

function rejects(label, callback, path) {
	test(label, () => {
		let message = null;
		try { callback(); }
		catch (error) { message = error.message; }
		assert(type(message) == 'string', 'expected validation error');
		assert(index(message, path + ':') == 0, 'missing field path: ' + message);
	});
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

// Each test that touches the filesystem allocates its own directory; the
// previous one is removed when the next is allocated and the last one is
// removed before the summary, so a run leaves nothing behind in /tmp.
let previousSandbox = null;

function newDir() {
	if (previousSandbox != null)
		removeTree(previousSandbox);
	// A unique temp directory per test keeps the cases independent.
	let dir = fs.mkdtemp('/tmp/airconnect-runtime.XXXXXX');
	previousSandbox = dir;
	return dir;
}

function cleanupSandboxes() {
	if (previousSandbox != null) {
		removeTree(previousSandbox);
		previousSandbox = null;
	}
}

function readOrNull(path) {
	return fs.readfile(path);
}

function modeOf(path) {
	let info = fs.stat(path);
	return info == null ? null : info.mode;
}


// --- loadConfig -------------------------------------------------------------

test('loadConfig reads main and device sections from the injected cursor', () => {
	let cursor = fakeCursor(uciMain(), uciDevices());
	let raw = runtime.loadConfig(cursor);
	assert(exists(raw, 'main') && exists(raw, 'devices'), 'expected main and devices');
	assert(raw.main.enabled === '1' && raw.main.interface == 'br-lan', 'main options not copied');
	assert(length(raw.devices) == 2, 'expected two devices');
	assert(raw.devices[0].engine == 'upnp' && raw.devices[1].engine == 'cast', 'device engines');
});

test('loadConfig asks UCI for the documented package and section names', () => {
	let cursor = fakeCursor(uciMain(), uciDevices());
	runtime.loadConfig(cursor);
	deepEqual(cursor.calls, [
		'get_all airconnect-manager main',
		'foreach airconnect-manager device'
	]);
});

test('loadConfig accepts an explicit package name', () => {
	let cursor = fakeCursor(uciMain(), []);
	runtime.loadConfig(cursor, 'other-name');
	assert(cursor.calls[0] == 'get_all other-name main', 'package name was not forwarded');
});

test('loadConfig drops UCI metadata and keeps section as the device id', () => {
	let raw = runtime.loadConfig(fakeCursor(uciMain(), uciDevices()));
	for (let key in ['.name', '.type', '.anonymous', '.index']) {
		assert(!exists(raw.main, key), 'main still carries ' + key);
		for (let device in raw.devices)
			assert(!exists(device, key), 'device still carries ' + key);
	}
	assert(raw.devices[0].section == 'device_demo_upnp', 'device section name lost');
	assert(raw.devices[1].section == 'device_demo_cast', 'device section name lost');
});

test('loadConfig returns raw strings and does not validate', () => {
	// max_volume 0 is invalid, but loadConfig must hand it over untouched so the
	// failure is reported by normalizeConfig with its field path.
	let raw = runtime.loadConfig(fakeCursor(uciMain({ max_volume: '0' }), []));
	assert(raw.main.max_volume === '0', 'loadConfig coerced or dropped a value');
});

test('loadConfig tolerates a missing main section and no devices', () => {
	let raw = runtime.loadConfig(fakeCursor(null, []));
	deepEqual(raw.main, {});
	deepEqual(raw.devices, []);
});

// --- applyConfig: happy path ------------------------------------------------

test('applyConfig writes both engines with exactly the rendered bytes', () => {
	sandbox = newDir();
	let raw = rawConfig();
	let expected = normalizeConfig(raw);
	let result = runtime.applyConfig(raw, { dir: sandbox, engines: ['upnp', 'cast'] });
	assert(result.ok === true, 'expected ok, got ' + sprintf('%J', result.errors));
	deepEqual(result.written, [sandbox + '/airupnp.xml', sandbox + '/aircast.xml']);
	deepEqual(result.errors, []);
	for (let engine in ['upnp', 'cast']) {
		let file = sandbox + '/' + (engine == 'upnp' ? 'airupnp.xml' : 'aircast.xml');
		let content = readOrNull(file);
		assert(type(content) == 'string', engine + ' file missing');
		assert(content === renderXml(expected, engine), engine + ' bytes differ from renderXml');
	}
});

test('applyConfig creates a missing directory with mode 0750', () => {
	sandbox = newDir();
	let nested = sandbox + '/a/b/runtime';
	let result = runtime.applyConfig(rawConfig(), { dir: nested });
	assert(result.ok === true, 'expected ok: ' + sprintf('%J', result.errors));
	assert(fs.stat(nested) != null && fs.stat(nested).type == 'directory', 'directory missing');
	assert(modeOf(nested) == 0750, 'directory mode is ' + sprintf('%o', modeOf(nested) ?? 0));
});

test('applyConfig accepts an already normalized configuration', () => {
	sandbox = newDir();
	let normalized = normalizeConfig(rawConfig());
	let result = runtime.applyConfig(normalized, { dir: sandbox });
	assert(result.ok === true, 'expected ok: ' + sprintf('%J', result.errors));
	assert(readOrNull(sandbox + '/airupnp.xml') === renderXml(normalized, 'upnp'), 'bytes differ');
});

test('applyConfig renders only the requested engines', () => {
	sandbox = newDir();
	let result = runtime.applyConfig(rawConfig(), { dir: sandbox, engines: ['upnp'] });
	assert(result.ok === true, 'expected ok: ' + sprintf('%J', result.errors));
	deepEqual(result.written, [sandbox + '/airupnp.xml']);
	assert(readOrNull(sandbox + '/aircast.xml') == null, 'aircast.xml must not be written');
});

test('applyConfig leaves no temporary files behind', () => {
	sandbox = newDir();
	runtime.applyConfig(rawConfig(), { dir: sandbox });
	for (let name in fs.lsdir(sandbox) ?? [])
		assert(substr(name, 0, 1) != '.', 'temporary file left behind: ' + name);
});

// --- applyConfig: validation failure keeps the last good file ---------------

test('a validation failure creates no file and keeps the previous bytes', () => {
	sandbox = newDir();
	// Seed a previously valid runtime file; this is the "keep last good" proof.
	let previous = previousXml('upnp');
	fs.writefile(sandbox + '/airupnp.xml', previous);
	let before = readOrNull(sandbox + '/airupnp.xml');

	let result = runtime.applyConfig(rawConfig({ max_volume: '0' }), { dir: sandbox, engines: ['upnp'] });
	assert(result.ok === false, 'expected ok:false');
	deepEqual(result.written, []);
	assert(length(result.errors) == 1, 'expected exactly one error');
	assert(index(result.errors[0], 'main.max_volume:') == 0, 'unexpected error: ' + result.errors[0]);
	let after = readOrNull(sandbox + '/airupnp.xml');
	assert(after === before, 'the previous file was modified');
	assert(after === previous, 'the previous file is not byte-identical');
});

test('a validation failure does not create a directory or status file', () => {
	sandbox = newDir();
	let target = sandbox + '/never-created';
	let result = runtime.applyConfig({ main: { max_volume: '0' } }, { dir: target });
	assert(result.ok === false, 'expected ok:false');
	assert(fs.stat(target) == null, 'the runtime directory was created for an invalid config');
});

rejects('normalizeConfig is the authority for invalid input', () => normalizeConfig({ main: { max_volume: '0' } }), 'main.max_volume');
test('applyConfig reports a non-object input instead of throwing', () => {
	sandbox = newDir();
	let result = runtime.applyConfig('not a config', { dir: sandbox });
	assert(result.ok === false && length(result.errors) == 1, 'expected one error');
	assert(index(result.errors[0], 'config:') == 0, 'unexpected error: ' + result.errors[0]);
});

// --- applyConfig: asymmetric engine failure ---------------------------------

test('one engine failing keeps the other engine current and reports ok:false', () => {
	sandbox = newDir();
	// Seed both files so "untouched" is provable byte for byte.
	let previousCast = previousXml('cast');
	fs.writefile(sandbox + '/airupnp.xml', previousXml('upnp'));
	fs.writefile(sandbox + '/aircast.xml', previousCast);

	// pcmUpnpOnly(): main.codec is pcm, which renderXml accepts for UPnP but
	// rejects for Cast. This is the documented asymmetric trigger; a cast device
	// with codec pcm does NOT work, because renderXml revalidates the whole
	// configuration and would reject both engines.
	let result = runtime.applyConfig(pcmUpnpOnly(), { dir: sandbox, engines: ['upnp', 'cast'] });
	assert(result.ok === false, 'expected ok:false');
	deepEqual(result.written, [sandbox + '/airupnp.xml']);
	assert(length(result.errors) == 1, 'expected exactly one error: ' + sprintf('%J', result.errors));
	assert(index(result.errors[0], sandbox + '/aircast.xml:') == 0, 'error does not name the cast path: ' + result.errors[0]);
	assert(index(result.errors[0], 'pcm is supported only by UPnP') >= 0, 'error lost the reason: ' + result.errors[0]);

	assert(readOrNull(sandbox + '/airupnp.xml') === renderXml(pcmUpnpOnly(), 'upnp'), 'upnp was not updated');
	assert(readOrNull(sandbox + '/aircast.xml') === previousCast, 'the cast file was touched');
});

test('a failing engine leaves no status file claiming success', () => {
	sandbox = newDir();
	let result = runtime.applyConfig(pcmUpnpOnly(), { dir: sandbox });
	assert(result.ok === false, 'expected ok:false');
	assert(readOrNull(sandbox + '/status.json') == null, 'status.json must not be written on failure');
});

// --- applyConfig: dry run ---------------------------------------------------

test('dry_run renders every engine and writes nothing at all', () => {
	sandbox = newDir();
	let raw = rawConfig();
	let expected = normalizeConfig(raw);
	let result = runtime.applyConfig(raw, { dir: sandbox, engines: ['upnp', 'cast'], dry_run: true });
	assert(result.ok === true, 'expected ok: ' + sprintf('%J', result.errors));
	deepEqual(result.written, []);
	deepEqual(result.errors, []);
	assert(result.rendered.upnp === renderXml(expected, 'upnp'), 'upnp render mismatch');
	assert(result.rendered.cast === renderXml(expected, 'cast'), 'cast render mismatch');
});

test('dry_run does not create the directory or any file', () => {
	sandbox = newDir();
	let target = sandbox + '/dry';
	runtime.applyConfig(rawConfig(), { dir: target, dry_run: true });
	assert(fs.stat(target) == null, 'dry run created the directory');
	deepEqual(fs.lsdir(sandbox) ?? [], []);
});

test('dry_run reports a render failure without writing', () => {
	sandbox = newDir();
	let result = runtime.applyConfig(pcmUpnpOnly(), { dir: sandbox, engines: ['cast'], dry_run: true });
	assert(result.ok === false, 'expected ok:false');
	assert(length(result.errors) == 1, 'expected one error');
	deepEqual(fs.lsdir(sandbox) ?? [], []);
});

// --- file modes -------------------------------------------------------------

test('written XML files and status.json are mode 0640', () => {
	sandbox = newDir();
	let result = runtime.applyConfig(rawConfig(), { dir: sandbox });
	assert(result.ok === true, 'expected ok: ' + sprintf('%J', result.errors));
	for (let name in ['airupnp.xml', 'aircast.xml', 'status.json']) {
		let mode = modeOf(sandbox + '/' + name);
		assert(mode == 0640, name + ' mode is ' + sprintf('%o', mode ?? 0) + ', expected 0640');
	}
});

test('no runtime file is world-readable', () => {
	sandbox = newDir();
	runtime.applyConfig(rawConfig(), { dir: sandbox });
	for (let name in fs.lsdir(sandbox) ?? []) {
		let perm = fs.stat(sandbox + '/' + name).perm;
		assert(!perm.other_read && !perm.other_write && !perm.other_exec, name + ' is world accessible');
	}
});

// --- status.json ------------------------------------------------------------

test('status.json is valid JSON with an integer applied_at and both engines', () => {
	sandbox = newDir();
	let before = time();
	let result = runtime.applyConfig(rawConfig(), { dir: sandbox });
	assert(result.ok === true, 'expected ok: ' + sprintf('%J', result.errors));
	let text = readOrNull(sandbox + '/status.json');
	assert(type(text) == 'string', 'status.json missing');
	let status = json(text);
	assert(type(status) == 'object' && status != null, 'status.json is not a JSON object');
	assert(type(status.applied_at) == 'int', 'applied_at is not an integer');
	assert(status.applied_at >= before && status.applied_at <= time() + 1, 'applied_at is not a plausible epoch');
	deepEqual(status.engines, ['upnp', 'cast']);
	assert(type(status.config_digest) == 'string' && length(status.config_digest) >= 8, 'config_digest missing');
});

test('status.json digest is stable for identical input and changes with content', () => {
	sandbox = newDir();
	runtime.applyConfig(rawConfig(), { dir: sandbox });
	let first = json(readOrNull(sandbox + '/status.json')).config_digest;
	runtime.applyConfig(rawConfig(), { dir: sandbox });
	let second = json(readOrNull(sandbox + '/status.json')).config_digest;
	assert(first === second, 'digest changed for identical input');

	runtime.applyConfig(rawConfig({ interface: 'br-guest' }), { dir: sandbox });
	let third = json(readOrNull(sandbox + '/status.json')).config_digest;
	assert(first != third, 'digest did not change when the rendered XML changed');
});

test('status.json records only the engines that were written', () => {
	sandbox = newDir();
	runtime.applyConfig(rawConfig(), { dir: sandbox, engines: ['upnp'] });
	deepEqual(json(readOrNull(sandbox + '/status.json')).engines, ['upnp']);
});

// --- never writes the persistent config -------------------------------------

test('applyConfig never creates or modifies /etc/config', () => {
	sandbox = newDir();
	let etcConfig = sandbox + '/etc/config';
	fs.mkdir(sandbox + '/etc', 0750);
	fs.mkdir(etcConfig, 0750);
	let marker = etcConfig + '/airconnect-manager';
	fs.writefile(marker, "config main 'main'\n\toption enabled '1'\n");
	let before = readOrNull(marker);

	runtime.applyConfig(rawConfig(), { dir: sandbox + '/var/etc/airconnect-manager' });
	assert(readOrNull(marker) === before, 'the persistent config was modified');
	deepEqual(fs.lsdir(etcConfig), ['airconnect-manager']);
});

// --- CLI contract -----------------------------------------------------------

test('runCommand rejects unknown commands with the usage exit code', () => {
	let outcome = runtime.runCommand(['nonsense']);
	assert(outcome.code == 2, 'expected exit 2, got ' + outcome.code);
	assert(index(outcome.stderr, 'unknown command') == 0, 'unexpected stderr: ' + outcome.stderr);
});

test('runCommand rejects a missing command and bad arity', () => {
	assert(runtime.runCommand([]).code == 2, 'missing command must be a usage error');
	assert(runtime.runCommand(['apply', 'extra']).code == 2, 'apply takes no arguments');
	assert(runtime.runCommand(['validate', 'extra']).code == 2, 'validate takes no arguments');
	assert(runtime.runCommand(['show']).code == 2, 'show needs an engine');
	assert(runtime.runCommand(['show', 'upnp', 'cast']).code == 2, 'show takes one engine');
	assert(runtime.runCommand(['show', 'dlna']).code == 2, 'show rejects unknown engines');
});

test('runCommand apply fails cleanly when UCI is unavailable on the host', () => {
	// The uci module does not exist here, so this exercises the error path the
	// router would take if the config could not be read: exit 1, no exception.
	let outcome = runtime.runCommand(['apply']);
	assert(outcome.code == 1, 'expected exit 1, got ' + outcome.code);
	assert(index(outcome.stderr, 'cannot read UCI:') == 0, 'unexpected stderr: ' + outcome.stderr);
	assert(outcome.stdout == '', 'stdout must stay empty on failure');
});

test('runCommand apply writes the selected engines and prints JSON', () => {
	sandbox = newDir();
	let raw = rawConfig();
	let outcome = runtime.runCommand(['apply'], { cursor: fakeCursor(raw.main, raw.devices), dir: sandbox });
	assert(outcome.code == 0, 'expected exit 0, got ' + outcome.code + ': ' + outcome.stderr);
	assert(outcome.stderr == '', 'unexpected stderr: ' + outcome.stderr);
	// apply is documented as machine readable on stdout.
	let result = json(outcome.stdout);
	assert(result != null && result.ok === true, 'stdout is not the JSON result: ' + outcome.stdout);
	deepEqual(result.written, [sandbox + '/airupnp.xml', sandbox + '/aircast.xml']);
});

test('runCommand apply renders only the engines enabled in UCI', () => {
	sandbox = newDir();
	let raw = rawConfig({ airupnp: '1', aircast: '0' });
	let outcome = runtime.runCommand(['apply'], { cursor: fakeCursor(raw.main, raw.devices), dir: sandbox });
	assert(outcome.code == 0, 'expected exit 0, got ' + outcome.code);
	deepEqual(json(outcome.stdout).written, [sandbox + '/airupnp.xml']);
	assert(readOrNull(sandbox + '/aircast.xml') == null, 'cast was rendered while disabled');
});

test('runCommand apply exits 1 and writes nothing for an invalid config', () => {
	sandbox = newDir();
	let previous = previousXml('upnp');
	fs.writefile(sandbox + '/airupnp.xml', previous);
	let raw = rawConfig({ max_volume: '0' });
	let outcome = runtime.runCommand(['apply'], { cursor: fakeCursor(raw.main, raw.devices), dir: sandbox });
	assert(outcome.code == 1, 'expected exit 1, got ' + outcome.code);
	assert(index(outcome.stderr, 'main.max_volume:') == 0, 'unexpected stderr: ' + outcome.stderr);
	assert(readOrNull(sandbox + '/airupnp.xml') === previous, 'the previous file was modified');
});

test('runCommand validate accepts a good config and rejects a bad one', () => {
	sandbox = newDir();
	let raw = rawConfig();
	let good = runtime.runCommand(['validate'], { cursor: fakeCursor(raw.main, raw.devices) });
	assert(good.code == 0, 'expected exit 0, got ' + good.code + ': ' + good.stderr);
	assert(index(good.stdout, 'configuration is valid') == 0, 'unexpected stdout: ' + good.stdout);
	// validate must not write runtime files.
	deepEqual(fs.lsdir(sandbox) ?? [], []);

	let bad = rawConfig({ max_volume: '0' });
	let rejected = runtime.runCommand(['validate'], { cursor: fakeCursor(bad.main, bad.devices) });
	assert(rejected.code == 1, 'expected exit 1, got ' + rejected.code);
	assert(index(rejected.stderr, 'main.max_volume:') == 0, 'unexpected stderr: ' + rejected.stderr);
	assert(rejected.stdout == '', 'stdout must stay empty on failure');
});

test('runCommand show prints the rendered XML for one engine', () => {
	let raw = rawConfig();
	let expected = normalizeConfig(raw);
	for (let engine in ['upnp', 'cast']) {
		let outcome = runtime.runCommand(['show', engine], { cursor: fakeCursor(raw.main, raw.devices) });
		assert(outcome.code == 0, 'expected exit 0 for ' + engine + ', got ' + outcome.code);
		assert(outcome.stdout === renderXml(expected, engine), engine + ' stdout differs from renderXml');
	}
});

test('runCommand show reports a render failure with exit 1', () => {
	// show revalidates, so the PCM-for-Cast rejection surfaces here too.
	sandbox = newDir();
	let raw = rawConfig({ codec: 'pcm', aircast: '0' });
	let outcome = runtime.runCommand(['show', 'cast'], { cursor: fakeCursor(raw.main, raw.devices) });
	assert(outcome.code == 1, 'expected exit 1, got ' + outcome.code);
	assert(index(outcome.stderr, 'pcm is supported only by UPnP') >= 0, 'unexpected stderr: ' + outcome.stderr);
	assert(outcome.stdout == '', 'stdout must stay empty on failure');
});

cleanupSandboxes();
print('1..', passed + failed, '\n', passed, ' passed; ', failed, ' failed\n');
exit(failed ? 1 : 0);
