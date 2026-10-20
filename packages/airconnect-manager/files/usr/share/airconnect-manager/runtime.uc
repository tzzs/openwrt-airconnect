#!/usr/bin/env ucode
// SPDX-License-Identifier: MIT
// runtime.uc - the only module allowed to read /etc/config/airconnect-manager
// and to write the generated engine XML under /var/etc/airconnect-manager.
//
// This file never writes the persistent configuration: UCI is read-only input
// here, and /etc/config is never opened for writing.
//
// Why this file has no `export` statement
// --------------------------------------
// ucode decides between module and script mode at compile time. A file that
// contains `export` can only be loaded as a module and dies with "Exports may
// only appear at top level of a module" when executed directly; a file without
// `export` cannot be imported by name ("Module ... does not export ...").
// The procd init script executes this file directly as
// `/usr/share/airconnect-manager/runtime.uc apply`, so script mode wins and the
// API is published two ways instead:
//
//   1. the trailing expression of this file evaluates to the API object, so
//      `loadfile('/usr/share/airconnect-manager/runtime.uc')()` returns
//      `{ loadConfig, applyConfig, runCommand }`;
//   2. the same object is assigned to `global.airconnect_runtime`, so a
//      side-effect `import '.../runtime.uc'` makes it reachable.
//
// The CLI block at the end of this file runs only when this file is the program
// being executed, which is detected at top level from sourcepath(1) and
// SCRIPT_NAME; see the comment there for why it cannot be a function.
// `length(ARGV) > 0` is NOT a usable discriminator: ARGV is a global that is
// already populated inside imported modules, so an importer that passes
// arguments would accidentally trigger the CLI.

import * as fs from 'fs';
import { normalizeConfig, renderXml } from './config.uc';

const CONFIG_NAME = 'airconnect-manager';
const DEFAULT_DIR = '/var/etc/airconnect-manager';
const DEFAULT_ENGINES = ['upnp', 'cast'];

// The init script derives its procd `-x` argument from these names, so they are
// part of the interface with T1 and must not be renamed casually.
const ENGINE_FILES = { upnp: 'airupnp.xml', cast: 'aircast.xml' };

const USAGE = 'usage: runtime.uc apply | validate | show upnp|cast\n';

function messageOf(error) {
	if (type(error) == 'object' && error != null && type(error.message) == 'string')
		return error.message;
	return sprintf('%s', error);
}

// UCI metadata keys (".name", ".type", ".anonymous", ".index") are transport
// details, not options. Dropping them here keeps normalizeConfig's contract.
function stripMeta(section) {
	let values = {};
	for (let key in section)
		if (substr(key, 0, 1) != '.')
			values[key] = section[key];
	return values;
}

// loadConfig(cursor, name) - read UCI into the shape normalizeConfig expects.
//
// The cursor is injected instead of imported so the host test suite can pass a
// fake: any object exposing get_all(name, section) and foreach(name, type, cb)
// is accepted. All UCI values stay strings; validation is normalizeConfig's
// job, never this function's.
function loadConfig(cursor, name) {
	name = name ?? CONFIG_NAME;
	let main = {};
	let section = cursor.get_all(name, 'main');
	if (type(section) == 'object' && section != null)
		main = stripMeta(section);
	let devices = [];
	cursor.foreach(name, 'device', function(section) {
		let device = stripMeta(section);
		if (type(section['.name']) == 'string')
			device.section = section['.name'];
		push(devices, device);
		return true;
	});
	return { main: main, devices: devices };
}

// A normalized object is what normalizeConfig returns, recognizable by the
// boolean it always produces for main.enabled. Raw UCI is all strings, so the
// two shapes cannot be confused.
function isNormalized(value) {
	return type(value) == 'object' && value != null &&
		type(value.main) == 'object' && value.main != null &&
		type(value.main.enabled) == 'bool';
}

function enabledEngines(main) {
	let engines = [];
	if (main.airupnp === true)
		push(engines, 'upnp');
	if (main.aircast === true)
		push(engines, 'cast');
	return engines;
}

let tempCounter = 0;

function uniqueSuffix() {
	// ucode exposes no getpid(). The temporary name combines wall clock, the
	// monotonic nanosecond field and a per-process counter. A collision would be
	// harmless anyway: the temp file is opened with O_EXCL, so a clash fails
	// loudly instead of overwriting anything.
	let mono = clock(true);
	return sprintf('%d.%d.%d', time(), mono[1], ++tempCounter);
}

function ensureDir(dir, errors) {
	let parts = split(dir, '/');
	let path = substr(dir, 0, 1) == '/' ? '' : '.';
	for (let part in parts) {
		if (part == '')
			continue;
		path += '/' + part;
		let info = fs.stat(path);
		if (info != null) {
			if (info.type != 'directory') {
				push(errors, path + ': not a directory');
				return false;
			}
			continue;
		}
		// fs.mkdir() in this ucode build is not recursive (a third argument is
		// ignored), so each missing ancestor is created explicitly.
		if (fs.mkdir(path, 0750) == null) {
			push(errors, path + ': cannot create directory: ' + (fs.error() ?? 'unknown error'));
			return false;
		}
	}
	// mkdir() is subject to umask, so pin the mode the router expects.
	if (fs.chmod(dir, 0750) == null) {
		push(errors, dir + ': cannot set mode 0750: ' + (fs.error() ?? 'unknown error'));
		return false;
	}
	return true;
}

// Write one file atomically: a unique temp file in the same directory, written
// completely, flushed and closed, chmod 0640, then renamed onto the final path.
// The destination is never opened for writing, so a failure at any step leaves
// the previous valid file byte-identical.
function writeAtomic(dir, name, data, errors) {
	let final = dir + '/' + name;
	let temp = dir + '/.' + name + '.tmp.' + uniqueSuffix();
	let handle = null;
	try {
		handle = fs.open(temp, 'wx', 0640);
		if (handle == null)
			die('cannot create temporary file: ' + (fs.error() ?? 'unknown error'));
		let written = handle.write(data);
		if (written != length(data))
			die('short write (' + written + ' of ' + length(data) + ' bytes)');
		// ucode exposes fflush() (file -> kernel) but no fsync(). Flushing and
		// closing before the rename is what guarantees the destination is never
		// truncated or partial; power-loss durability of the temp file itself is
		// not claimed.
		if (handle.flush() == null)
			die('cannot flush temporary file: ' + (fs.error() ?? 'unknown error'));
		if (handle.close() == null)
			die('cannot close temporary file: ' + (fs.error() ?? 'unknown error'));
		handle = null;
		if (fs.chmod(temp, 0640) == null)
			die('cannot set mode 0640: ' + (fs.error() ?? 'unknown error'));
		if (fs.rename(temp, final) == null)
			die('cannot replace file: ' + (fs.error() ?? 'unknown error'));
		return true;
	}
	catch (error) {
		if (handle != null) {
			try { handle.close(); } catch (close_error) { }
		}
		fs.unlink(temp);
		push(errors, final + ': ' + messageOf(error));
		return false;
	}
}

// FNV-1a (32 bit) is the documented fallback when the optional digest module is
// not installed. It is not a security primitive; it only lets the UI tell two
// renders apart. The 32x32 multiply is split into 16-bit halves because ucode
// integers are signed 64-bit doubles-backed values and a plain multiply loses
// the low bits.
function fnv1a(data) {
	let hash = 0x811c9dc5;
	for (let i = 0; i < length(data); i++) {
		hash = hash ^ ord(data, i);
		let low = hash & 0xffff;
		let high = (hash >> 16) & 0xffff;
		hash = (((low * 16777619) & 0xffffffff) + (((high * 16777619) & 0xffff) * 65536)) & 0xffffffff;
	}
	return sprintf('%08x', hash);
}

function configDigest(data) {
	// `import * as digest from 'digest'` is a compile-time failure when the
	// module is absent, so the optional module is loaded at runtime instead.
	try {
		let module = require('digest');
		if (type(module) == 'object' && module != null && type(module.sha256) == 'function') {
			let value = module.sha256(data);
			if (type(value) == 'string')
				return value;
		}
	}
	catch (error) {
		// Fall through to the local digest.
	}
	return fnv1a(data);
}

function writeStatus(dir, engines, rendered, written) {
	let canonical = [];
	for (let engine in engines)
		if (index(written, dir + '/' + ENGINE_FILES[engine]) >= 0)
			push(canonical, rendered[engine]);
	let text = sprintf('{\n  "applied_at": %d,\n  "engines": %J,\n  "config_digest": "%s"\n}\n',
		time(), engines, configDigest(join('\n', canonical)));
	let errors = [];
	if (!writeAtomic(dir, 'status.json', text, errors)) {
		// Status is a convenience for the UI, never a precondition for the
		// engines: a failure here is logged and the apply still succeeds.
		for (let error in errors)
			warn('airconnect-manager: cannot write status: ' + error + '\n');
	}
}

// applyConfig(input, options) - render and install the runtime XML.
//
// options: { dir, engines, dry_run }
//   dir      target directory, defaults to /var/etc/airconnect-manager
//   engines  engines to render, defaults to ['upnp', 'cast']
//   dry_run  render only; write nothing at all
//
// Returns { ok, written, errors } and, for dry runs, `rendered`.
//
// Atomicity is per file, deliberately: if engine 1 is written and engine 2
// fails, engine 1's new file stays because it is already valid, and the result
// reports ok:false plus which engine failed. Blanking a working engine because
// its sibling broke would turn one bad setting into a total outage.
function applyConfig(input, options) {
	options = options ?? {};
	let dir = options.dir ?? DEFAULT_DIR;
	let engines = options.engines ?? DEFAULT_ENGINES;
	let dryRun = options.dry_run === true;
	let result = { ok: false, written: [], errors: [] };

	if (type(dir) != 'string' || dir == '') {
		push(result.errors, 'dir: expected a non-empty path');
		return result;
	}
	if (type(engines) != 'array') {
		push(result.errors, 'engines: expected an array');
		return result;
	}
	let requested = [];
	for (let engine in engines) {
		if (engine != 'upnp' && engine != 'cast') {
			push(result.errors, 'engines: expected upnp or cast, got ' + sprintf('%J', engine));
			return result;
		}
		if (index(requested, engine) < 0)
			push(requested, engine);
	}

	let normalized;
	try {
		normalized = isNormalized(input) ? input : normalizeConfig(input);
	}
	catch (error) {
		// Validation failed: nothing is rendered and nothing is touched.
		push(result.errors, messageOf(error));
		return result;
	}

	let rendered = {};
	for (let engine in requested) {
		try {
			rendered[engine] = renderXml(normalized, engine);
		}
		catch (error) {
			// renderXml revalidates the whole configuration, so an engine-specific
			// rejection (e.g. a PCM default for Cast) surfaces here. The existing
			// file for this engine is left alone.
			push(result.errors, dir + '/' + ENGINE_FILES[engine] + ': ' + messageOf(error));
		}
	}

	if (dryRun) {
		result.rendered = rendered;
		result.ok = length(result.errors) == 0;
		return result;
	}

	if (!length(rendered)) {
		// Nothing was requested (both engines disabled) and nothing failed, so
		// this is a successful no-op rather than an error. No status file is
		// written because no XML was produced for it to describe.
		result.ok = length(result.errors) == 0;
		return result;
	}

	if (!ensureDir(dir, result.errors))
		return result;

	for (let engine in requested) {
		if (!exists(rendered, engine))
			continue;
		if (writeAtomic(dir, ENGINE_FILES[engine], rendered[engine], result.errors))
			push(result.written, dir + '/' + ENGINE_FILES[engine]);
	}

	result.ok = length(result.errors) == 0 && length(result.written) == length(requested);
	if (result.ok)
		writeStatus(dir, requested, rendered, result.written);
	return result;
}

// --- CLI -------------------------------------------------------------------

function cursorFromUci() {
	// The uci module only exists on the router; requiring it at runtime keeps
	// this file loadable on the host for the test suite. `require()` is used
	// instead of a top-level `import` because a missing module would otherwise
	// be a compile error, not a runtime one.
	let uci = require('uci');
	let cursor = uci.cursor();
	cursor.load(CONFIG_NAME);
	return cursor;
}

function usage(reason) {
	return { code: 2, stdout: '', stderr: reason + '\n' + USAGE };
}

// runCommand(argv, options) returns { code, stdout, stderr } instead of printing,
// so the CLI contract is testable without capturing process output.
//
// options: { cursor, dir } - both optional seams used by the tests; the real
// CLI passes neither and gets the uci module and /var/etc/airconnect-manager.
// Exit codes: 0 success, 1 validation/render failure, 2 usage error.
function runCommand(argv, options) {
	options = options ?? {};
	let command = length(argv) ? argv[0] : null;

	let read = function() {
		let cursor = options.cursor ?? cursorFromUci();
		return loadConfig(cursor);
	};

	if (command == 'apply') {
		if (length(argv) != 1)
			return usage('apply takes no arguments');
		let raw;
		try {
			raw = read();
		}
		catch (error) {
			return { code: 1, stdout: '', stderr: 'cannot read UCI: ' + messageOf(error) + '\n' };
		}
		let engines;
		try {
			engines = enabledEngines(normalizeConfig(raw).main);
		}
		catch (error) {
			return { code: 1, stdout: '', stderr: messageOf(error) + '\n' };
		}
		// Only the engines the user selected are rendered. A disabled engine's
		// previous file is left in place; the init script never starts an engine
		// it was not asked to run.
		let result = applyConfig(raw, { engines: engines, dir: options.dir });
		return { code: result.ok ? 0 : 1, stdout: sprintf('%J\n', result), stderr: '' };
	}

	if (command == 'validate') {
		if (length(argv) != 1)
			return usage('validate takes no arguments');
		try {
			let normalized = normalizeConfig(read());
			return {
				code: 0,
				stdout: sprintf('configuration is valid: %d device(s), upnp=%s, cast=%s\n',
					length(normalized.devices),
					normalized.main.airupnp ? 'on' : 'off',
					normalized.main.aircast ? 'on' : 'off'),
				stderr: ''
			};
		}
		catch (error) {
			return { code: 1, stdout: '', stderr: messageOf(error) + '\n' };
		}
	}

	if (command == 'show') {
		if (length(argv) != 2)
			return usage('show needs exactly one engine');
		let engine = argv[1];
		if (engine != 'upnp' && engine != 'cast')
			return usage('unknown engine: ' + sprintf('%J', engine));
		try {
			let normalized = normalizeConfig(read());
			return { code: 0, stdout: renderXml(normalized, engine), stderr: '' };
		}
		catch (error) {
			return { code: 1, stdout: '', stderr: messageOf(error) + '\n' };
		}
	}

	return usage(command == null ? 'missing command' : 'unknown command: ' + sprintf('%J', command));
}

// Whether this file is the program being executed is decided at the top level.
//
// `sourcepath(1)` must be read here and not inside a function: the depth
// argument counts call frames, so inside a helper the file's own frame is depth
// 0 and depth 1 resolves to the same path again, which makes every caller look
// like a program invocation. At the top level the outermost source has no
// parent (null), while an imported or loadfile()'d file always has one.
//
// The realpath comparison against SCRIPT_NAME then rejects the case where an
// unrelated script loadfile()s this file: there the parent is null too, but
// SCRIPT_NAME still names the caller, not this file.
const PARENT_SOURCE = sourcepath(1);
const SELF_SOURCE = sourcepath();
const INVOKED_AS_PROGRAM = (
	PARENT_SOURCE == null &&
	type(SCRIPT_NAME) == 'string' && SCRIPT_NAME != null &&
	fs.realpath(SCRIPT_NAME) != null &&
	fs.realpath(SELF_SOURCE) != null &&
	fs.realpath(SCRIPT_NAME) == fs.realpath(SELF_SOURCE)
);

if (INVOKED_AS_PROGRAM) {
	let outcome = runCommand(ARGV);
	if (outcome.stdout != '')
		fs.stdout.write(outcome.stdout);
	if (outcome.stderr != '')
		fs.stderr.write(outcome.stderr);
	exit(outcome.code);
}

global.airconnect_runtime = {
	loadConfig: loadConfig,
	applyConfig: applyConfig,
	runCommand: runCommand
};

({ loadConfig: loadConfig, applyConfig: applyConfig, runCommand: runCommand })
