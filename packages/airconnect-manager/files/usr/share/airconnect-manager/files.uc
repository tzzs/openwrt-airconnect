// SPDX-License-Identifier: MIT
// files.uc - bounded file access for the rpcd backend.
//
// Only the `fs` module is used, which exists both on the router and in the
// host ucode build, so every function here is exercised by tests/state/run.uc
// instead of being an untested branch inside the plugin.
//
// Two rules shape this module:
//   * a write never leaves a half-written destination (temp file in the same
//     directory, one complete write, rename), and
//   * a read never takes more than the caller's budget, and never starts in the
//     middle of a line and presents that fragment as a complete one.
// Why `const f = function() {}` plus `export { }` instead of `export function f`
// ---------------------------------------------------------------------------
// The ucode runtime shipped by the target (libucode.so.20230711, as installed by
// iStoreOS 25.12.5) rejects `export function` with "Syntax error: Unexpected
// token / Expecting ';'". `export const` and a trailing `export { ... }` list do
// compile there and the imported binding is callable, so that is the form every
// module in this package uses. Do not "modernise" it back: it verifiably fails
// to load on the device, and the host test runner uses a newer ucode that would
// not catch the regression.

import * as fs from 'fs';

// fs.mkdir() is not recursive in this ucode build (a third argument is
// ignored), so each missing ancestor is created explicitly, exactly as
// runtime.uc does for the runtime directory.
const ensureDir = function(path) {
	if (type(path) != 'string' || path == '')
		return false;
	let parts = split(path, '/');
	let current = substr(path, 0, 1) == '/' ? '' : '.';
	for (let part in parts) {
		if (part == '')
			continue;
		current += '/' + part;
		let info = fs.stat(current);
		if (info != null) {
			if (info.type != 'directory')
				return false;
			continue;
		}
		if (fs.mkdir(current, 0750) == null)
			return false;
	}
	return true;
};

// A unique name per write. ucode exposes no getpid(); the wall clock, the
// monotonic nanosecond field and a counter are enough because the file is
// opened with O_EXCL, so a collision fails loudly instead of overwriting.
let tempCounter = 0;

function tempName(path) {
	let mono = clock(true);
	return path + '.tmp.' + sprintf('%d.%d.%d', time(), mono[1], ++tempCounter);
}

// Write `data` to `path` atomically. Returns true on success. The destination is
// never opened for writing, so a failure at any step leaves the previous
// contents byte-identical.
const writeAtomic = function(path, data, mode) {
	if (type(path) != 'string' || path == '' || type(data) != 'string')
		return false;
	mode = mode ?? 0640;
	let temp = tempName(path);
	let handle = null;
	try {
		handle = fs.open(temp, 'wx', mode);
		if (handle == null)
			return false;
		if (handle.write(data) != length(data)) {
			handle.close();
			fs.unlink(temp);
			return false;
		}
		// ucode exposes flush() (file -> kernel) but no fsync(). Flushing and
		// closing before the rename is what guarantees the destination is never
		// truncated or partial; power-loss durability of the temp file is not
		// claimed.
		handle.flush();
		handle.close();
		handle = null;
		fs.chmod(temp, mode);
		if (fs.rename(temp, path) == null) {
			fs.unlink(temp);
			return false;
		}
		return true;
	}
	catch (error) {
		if (handle != null) {
			try { handle.close(); } catch (close_error) { }
		}
		fs.unlink(temp);
		return false;
	}
};

// The first line of a read that began mid-file is a fragment, not a line. Drop
// it and report that something was dropped, so the caller can set `truncated`
// without looking at the text again.
function trimFragment(text) {
	let newline = index(text, '\n');
	return newline < 0 ? '' : substr(text, newline + 1);
}

// Whether `start` happens to be the first byte of a line. The byte before it is
// the only way to know: without this, a budget that lands exactly on a line
// boundary would silently discard the first complete line.
function atLineStart(handle, start) {
	if (start <= 0)
		return true;
	if (handle.seek(start - 1, 0) == null)
		return false;
	let previous = handle.read(1);
	return previous === '\n';
}

// Read at most `budget` bytes from the end of a file, seeking past the part that
// is not needed instead of reading the whole file.
const readTail = function(path, budget) {
	let result = { text: '', truncated: false };
	if (type(path) != 'string' || type(budget) != 'int' || budget < 1)
		return result;
	let info = fs.stat(path);
	if (info == null || info.type != 'file' || info.size <= 0)
		return result;
	let start = info.size > budget ? info.size - budget : 0;
	let handle = fs.open(path, 'r');
	if (handle == null)
		return result;
	let text, aligned = true;
	try {
		if (start > 0) {
			aligned = atLineStart(handle, start);
			if (!aligned && handle.seek(start, 0) == null) {
				handle.close();
				return result;
			}
		}
		text = handle.read(budget + 1) ?? '';
		handle.close();
	}
	catch (error) {
		try { handle.close(); } catch (close_error) { }
		return result;
	}
	if (type(text) != 'string')
		return result;
	if (start > 0) {
		result.truncated = true;
		if (!aligned)
			text = trimFragment(text);
	}
	result.text = text;
	return result;
};

// The same bounds for a command's output. Only used for syslog, whose reader
// has no seekable file behind it. The command must be a fixed literal.
const commandTail = function(command, budget) {
	let result = { text: '', truncated: false };
	if (type(command) != 'string' || type(budget) != 'int' || budget < 1)
		return result;
	let proc = fs.popen(command, 'r');
	if (proc == null)
		return result;
	let text = proc.read(budget + 1) ?? '';
	proc.close();
	if (type(text) != 'string')
		return result;
	if (length(text) > budget) {
		result.truncated = true;
		text = trimFragment(text);
	}
	result.text = text;
	return result;
};

// Read a whole file only when it is plausibly small: a size check first means a
// hostile or corrupted file cannot be pulled into memory.
const readText = function(path, limit) {
	if (type(path) != 'string' || type(limit) != 'int' || limit < 1)
		return null;
	let info = fs.stat(path);
	if (info == null || info.type != 'file' || info.size <= 0 || info.size > limit)
		return null;
	let text = fs.readfile(path);
	return type(text) == 'string' ? text : null;
};

// A JSON object from a size-bounded file, or null when it is missing,
// oversized, unparsable or not an object.
const readJson = function(path, limit) {
	let text = readText(path, limit);
	if (text == null)
		return null;
	try {
		let parsed = json(text);
		return type(parsed) == 'object' && parsed != null ? parsed : null;
	}
	catch (error) {
		return null;
	}
};

// Whether a path exists, without following a final symlink into an unexpected
// target. Used only for presence checks such as "is a legacy binary installed".
// Named pathExists, not exists, because `exists()` is a ucode builtin and an
// import of that name would shadow it for the whole file.
const pathExists = function(path) {
	if (type(path) != 'string' || path == '')
		return false;
	return fs.lstat(path) != null;
};

export { ensureDir, writeAtomic, readTail, commandTail, readText, readJson, pathExists };
