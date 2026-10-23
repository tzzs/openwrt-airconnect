// SPDX-License-Identifier: MIT
// Pure validation and serialization. This module does not read UCI or write files.
// Why `const f = function() {}` plus `export { }` instead of `export function f`
// ---------------------------------------------------------------------------
// The ucode runtime shipped by the target (libucode.so.20230711, as installed by
// iStoreOS 25.12.5) rejects `export function` with "Syntax error: Unexpected
// token / Expecting ';'". `export const` and a trailing `export { ... }` list do
// compile there and the imported binding is callable, so that is the form every
// module in this package uses. Do not "modernise" it back: it verifiably fails
// to load on the device, and the host test runner uses a newer ucode that would
// not catch the regression.

function invalid(path, reason) {
	die(path + ': ' + reason);
}

function object(value, path) {
	if (type(value) != 'object')
		invalid(path, 'expected an object');
	return value;
}

function option(source, key, fallback) {
	return exists(source, key) ? source[key] : fallback;
}

function boolean(value, path) {
	if (value === true || value === 1 || value === '1')
		return true;
	if (value === false || value === 0 || value === '0')
		return false;
	invalid(path, 'expected 0 or 1');
}

function whitespace(cp) {
	return cp == 32 || cp == 160 || cp == 5760 ||
		(cp >= 8192 && cp <= 8202) || cp == 8232 || cp == 8233 ||
		cp == 8239 || cp == 8287 || cp == 12288 || cp == 65279;
}

// ucode strings and length() are byte based. Decode explicitly so malformed
// UTF-8, XML-forbidden characters and Unicode controls cannot reach the engine.
function text(value, path, max_bytes, allow_empty) {
	if (type(value) != 'string')
		invalid(path, 'expected a string');
	if (length(value) > max_bytes)
		invalid(path, 'exceeds ' + max_bytes + ' UTF-8 bytes');
	if (value == '' && allow_empty)
		return value;
	let visible = false;
	for (let i = 0; i < length(value); ) {
		let b = ord(value, i++);
		let cp = b;
		let remaining = 0;
		let minimum = 0;
		if (b >= 0xc2 && b <= 0xdf) {
			cp = b & 0x1f;
			remaining = 1;
			minimum = 0x80;
		}
		else if (b >= 0xe0 && b <= 0xef) {
			cp = b & 0x0f;
			remaining = 2;
			minimum = 0x800;
		}
		else if (b >= 0xf0 && b <= 0xf4) {
			cp = b & 0x07;
			remaining = 3;
			minimum = 0x10000;
		}
		else if (b > 0x7f)
			invalid(path, 'invalid UTF-8');
		if (i + remaining > length(value))
			invalid(path, 'invalid UTF-8');
		for (let n = 0; n < remaining; n++) {
			let next = ord(value, i++);
			if (next < 0x80 || next > 0xbf)
				invalid(path, 'invalid UTF-8');
			cp = (cp << 6) | (next & 0x3f);
		}
		if (cp < minimum || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff))
			invalid(path, 'invalid UTF-8');
		if (cp < 32 || (cp >= 127 && cp <= 159) || cp == 0xfffe || cp == 0xffff)
			invalid(path, 'control or XML-forbidden character');
		if (!whitespace(cp))
			visible = true;
	}
	if (!visible)
		invalid(path, 'must not be empty or whitespace only');
	return value;
}

function number(value, path, min, max, integer) {
	let kind = type(value);
	if (kind == 'string') {
		// Patterns are anchored, but ucode's `$` also matches before a trailing
		// newline, so require the match to consume the whole value.
		let re = integer ? /^(0|[1-9][0-9]*)$/ : /^(0|[1-9][0-9]*)(\.[0-9]+)?$/;
		let m = match(value, re);
		if (!m || length(m[0]) != length(value))
			invalid(path, integer ? 'expected a decimal integer' : 'expected a decimal number');
		value = +value;
	}
	else if (kind != 'int' && kind != 'double')
		invalid(path, 'expected a number');
	// The comparisons also reject +/-Infinity and NaN without a math module.
	if (!(value >= min && value <= max) || (integer && value != int(value)))
		invalid(path, 'expected ' + (integer ? 'an integer' : 'a finite number') + ' in ' + min + '..' + max);
	return value;
}

function codec(value, path) {
	if (type(value) != 'string')
		invalid(path, 'expected a codec string');
	let flac = match(value, /^flac:[0-9]$/);
	// `$` matches before a trailing newline in ucode, so confirm the match
	// consumed the whole value before trusting it.
	if (value == 'wav' || value == 'pcm' || value == 'flac' ||
		(flac && length(flac[0]) == length(value)))
		return value;
	let parts = match(value, /^(mp3|aac)(:([1-9][0-9]{1,2}))?$/);
	if (parts && length(parts[0]) == length(value)) {
		if (!parts[3])
			return value;
		let rate = int(parts[3]);
		if (rate >= (parts[1] == 'mp3' ? 32 : 16) && rate <= 320)
			return value;
	}
	invalid(path, 'use wav, pcm (UPnP), flac[:0..9], mp3[:32..320] or aac[:16..320]');
}

function latency(value, path) {
	if (type(value) != 'string')
		invalid(path, 'expected RTP:HTTP milliseconds');
	let parts = match(value, /^(0|[1-9][0-9]{0,4}):(0|[1-9][0-9]{0,4})$/);
	// ucode's `$` accepts a trailing newline, so the match must span the value.
	if (!parts || length(parts[0]) != length(value) ||
		int(parts[1]) > 10000 || int(parts[2]) > 10000)
		invalid(path, 'expected RTP:HTTP integers in 0..10000');
	return value;
}

// http_length is an enum, not a number: upstream only documents and handles three
// modes (`-g -3|-1|0`, README "HTTP content-length and transfer modes").
//   -3 chunked encoding, -1 no content-length, 0 a fixed dummy length.
// Any other integer would be handed to the engine as a literal Content-Length.
// Read by airupnp/src/config_upnp.c:131; aircast/src/config_cast.c has no such item.
function httpLength(value, path) {
	let text = type(value) == 'int' ? sprintf('%d', value) : value;
	if (type(text) != 'string' || index(['-3', '-1', '0'], text) < 0)
		invalid(path, 'expected -3 (chunked), -1 (no content-length) or 0 (fixed length)');
	return int(text);
}

// `artwork` is a URL the speaker is asked to fetch; the manager never requests it.
// Upstream copies it with strcpy() into char ArtWork[4*STR_LEN] = 1024 bytes
// (airupnp.h:65, aircast.h:53), so 1023 is the hard ceiling and this product limit
// is deliberately stricter. The allowed bytes are RFC 3986 unreserved + sub-delims
// + ':' '@' '/' '?' '#' '-' '[' ']', which also excludes quotes, angle brackets,
// backslashes and every control byte, so the value cannot break the XML or the
// JSON metadata payload the Cast engine builds from it (cast_util.c:32-35).
//
// The set is checked one byte at a time on purpose: a bracket class is what this
// repo's ucode has already been bitten by, and `[` `]` are legal URL bytes.
const ARTWORK_MAX = 512;
const ARTWORK_BYTES = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~%!$&()*+,;=:@/?#-[]';

function artwork(value, path) {
	if (type(value) != 'string')
		invalid(path, 'expected an http:// or https:// URL');
	// Empty means "no artwork": upstream tests *Conf->ArtWork before using it
	// (airupnp.c:999, aircast.c:206), so this is the upstream default too.
	if (value == '')
		return value;
	if (length(value) > ARTWORK_MAX)
		invalid(path, 'exceeds ' + ARTWORK_MAX + ' UTF-8 bytes');
	let offset = 0;
	if (substr(value, 0, 8) == 'https://')
		offset = 8;
	else if (substr(value, 0, 7) == 'http://')
		offset = 7;
	if (offset == 0)
		invalid(path, 'expected a lowercase http:// or https:// URL');
	if (length(value) == offset)
		invalid(path, 'expected a host after the scheme');
	for (let i = offset; i < length(value); i++) {
		if (index(ARTWORK_BYTES, chr(ord(value, i))) < 0)
			invalid(path, 'expected a URL without spaces, quotes or control characters');
	}
	return value;
}

function inherited(source, key, fallback) {
	return !exists(source, key) || source[key] === '' ? fallback : source[key];
}

const normalizeConfig = function(input) {
	object(input, 'config');
	let source = exists(input, 'main') ? object(input.main, 'main') : {};
	let main = {
		enabled: boolean(option(source, 'enabled', '0'), 'main.enabled'),
		interface: option(source, 'interface', 'br-lan'),
		airupnp: boolean(option(source, 'airupnp', '1'), 'main.airupnp'),
		aircast: boolean(option(source, 'aircast', '0'), 'main.aircast'),
		codec: codec(option(source, 'codec', 'flac'), 'main.codec'),
		latency: latency(option(source, 'latency', '1000:2000'), 'main.latency'),
		max_volume: number(option(source, 'max_volume', '100'), 'main.max_volume', 1, 100, true),
		media_volume: number(option(source, 'media_volume', '0.5'), 'main.media_volume', 0, 1, false),
		log_level: option(source, 'log_level', 'warn'),
		// Upstream defaults from glMRConfig (airupnp.c:67-83, aircast.c:51-63).
		// Writing a value equal to the engine's own default keeps the generated
		// XML behaviourally identical for a configuration that predates it.
		metadata: boolean(option(source, 'metadata', '1'), 'main.metadata'),
		flush: boolean(option(source, 'flush', '1'), 'main.flush'),
		drift: boolean(option(source, 'drift', '0'), 'main.drift'),
		artwork: artwork(option(source, 'artwork', ''), 'main.artwork'),
		http_length: httpLength(option(source, 'http_length', '-1'), 'main.http_length'),
		// The search-topic buffer is char[sizeof(MEDIA_RENDERER)+2], i.e. the URN,
		// ':', one digit and NUL (airupnp.c:96, 598, 1160), so 9 is the largest
		// version that is not truncated. MediaRenderer:1-3 are the published ones.
		upnp_max: number(option(source, 'upnp_max', '1'), 'main.upnp_max', 1, 9, true),
		stop_receiver: boolean(option(source, 'stop_receiver', '0'), 'main.stop_receiver')
	};
	let ifaceMatch = match(main.interface, /^[A-Za-z0-9_][A-Za-z0-9_.-]*$/);
	if (type(main.interface) != 'string' || length(main.interface) > 15 ||
		!ifaceMatch || length(ifaceMatch[0]) != length(main.interface) ||
		main.interface == '.' || main.interface == '..')
		invalid('main.interface', 'expected a Linux interface token of 1..15 ASCII bytes');
	if (type(main.log_level) != 'string' || index(['error', 'warn', 'info', 'debug'], main.log_level) < 0)
		invalid('main.log_level', 'expected error, warn, info or debug');
	if (main.aircast && main.codec == 'pcm')
		invalid('main.codec', 'pcm is supported only by UPnP; choose a Cast-compatible default');
	let entries = exists(input, 'devices') ? input.devices : [];
	if (type(entries) != 'array')
		invalid('devices', 'expected an array');
	let devices = [];
	let seen = { upnp: {}, cast: {} };
	for (let i = 0; i < length(entries); i++) {
		let path = 'devices[' + i + ']';
		let entry = object(entries[i], path);
		let engine = entry.engine;
		if (engine !== 'upnp' && engine !== 'cast')
			invalid(path + '.engine', 'expected upnp or cast');
		let udn = text(entry.udn, path + '.udn', 255, false);
		if (exists(seen[engine], udn))
			invalid(path + '.udn', 'duplicate UDN for ' + engine);
		seen[engine][udn] = true;
		let device = {
			engine: engine,
			udn: udn,
			enabled: boolean(option(entry, 'enabled', '1'), path + '.enabled'),
			name: text(option(entry, 'name', ''), path + '.name', 63, true),
			max_volume: number(inherited(entry, 'max_volume', main.max_volume), path + '.max_volume', 1, 100, true),
			media_volume: number(inherited(entry, 'media_volume', main.media_volume), path + '.media_volume', 0, 1, false),
			codec: codec(inherited(entry, 'codec', main.codec), path + '.codec'),
			latency: latency(inherited(entry, 'latency', main.latency), path + '.latency'),
			// These five are read from a <device> block by the engine that owns them,
			// so a device override is real and inherits exactly like codec/latency.
			// upnp_max is absent on purpose: upstream parses it into the device
			// struct but only ever reads glMRConfig.UPnPMax (airupnp.c:599, 1159),
			// so a per-device value would be dead XML. It is global-only, like
			// interface and log_level.
			metadata: boolean(inherited(entry, 'metadata', main.metadata), path + '.metadata'),
			flush: boolean(inherited(entry, 'flush', main.flush), path + '.flush'),
			drift: boolean(inherited(entry, 'drift', main.drift), path + '.drift'),
			artwork: artwork(inherited(entry, 'artwork', main.artwork), path + '.artwork'),
			http_length: httpLength(inherited(entry, 'http_length', main.http_length), path + '.http_length'),
			stop_receiver: boolean(inherited(entry, 'stop_receiver', main.stop_receiver), path + '.stop_receiver')
		};
		if (engine == 'cast' && device.codec == 'pcm')
			invalid(path + '.codec', 'pcm is supported only by UPnP');
		if (exists(entry, 'section')) {
			if (type(entry.section) != 'string')
				invalid(path + '.section', 'expected a string');
			device.section = entry.section;
		}
		push(devices, device);
	}
	return { main: main, devices: devices };
};

function escapeXml(value) {
	value = replace('' + value, /&/g, '&amp;');
	value = replace(value, /</g, '&lt;');
	value = replace(value, />/g, '&gt;');
	value = replace(value, /"/g, '&quot;');
	return replace(value, /'/g, '&apos;');
}

function element(lines, indent, tag, value) {
	push(lines, indent + '<' + tag + '>' + escapeXml(value) + '</' + tag + '>');
}

const renderXml = function(normalized, engine) {
	if (engine !== 'upnp' && engine !== 'cast')
		invalid('engine', 'expected upnp or cast');
	// Revalidation makes callers unable to bypass limits with a hand-made object.
	let config = normalizeConfig(normalized);
	let main = config.main;
	let root = engine == 'upnp' ? 'airupnp' : 'aircast';
	let volume = engine == 'upnp' ? 'max_volume' : 'media_volume';
	if (engine == 'cast' && main.codec == 'pcm')
		invalid('main.codec', 'pcm is supported only by UPnP');
	let lines = ['<?xml version="1.0" encoding="UTF-8"?>', '<' + root + '>'];
	element(lines, '  ', 'binding', main.interface);
	for (let tag in ['main_log', engine == 'upnp' ? 'upnp_log' : 'cast_log', 'util_log'])
		element(lines, '  ', tag, main.log_level);
	if (engine == 'upnp')
		element(lines, '  ', 'raop_log', main.log_level);
	push(lines, '  <common>');
	element(lines, '    ', 'enabled', 1);
	element(lines, '    ', 'codec', main.codec);
	element(lines, '    ', 'latency', main.latency);
	element(lines, '    ', volume, main[volume]);
	element(lines, '    ', 'metadata', main.metadata ? 1 : 0);
	element(lines, '    ', 'flush', main.flush ? 1 : 0);
	element(lines, '    ', 'drift', main.drift ? 1 : 0);
	if (main.artwork != '')
		element(lines, '    ', 'artwork', main.artwork);
	// The two engine-specific compatibility switches stay out of the other root
	// entirely: aircast never reads http_length or upnp_max, airupnp never reads
	// stop_receiver, and a silently ignored element is worse than no element.
	if (engine == 'upnp') {
		element(lines, '    ', 'http_length', main.http_length);
		element(lines, '    ', 'upnp_max', main.upnp_max);
	}
	else
		element(lines, '    ', 'stop_receiver', main.stop_receiver ? 1 : 0);
	push(lines, '  </common>');
	for (let device in config.devices) {
		if (device.engine != engine)
			continue;
		push(lines, '  <device>');
		element(lines, '    ', 'udn', device.udn);
		if (device.name != '')
			element(lines, '    ', 'name', device.name);
		element(lines, '    ', 'enabled', device.enabled ? 1 : 0);
		element(lines, '    ', 'codec', device.codec);
		element(lines, '    ', 'latency', device.latency);
		element(lines, '    ', volume, device[volume]);
		element(lines, '    ', 'metadata', device.metadata ? 1 : 0);
		element(lines, '    ', 'flush', device.flush ? 1 : 0);
		element(lines, '    ', 'drift', device.drift ? 1 : 0);
		if (device.artwork != '')
			element(lines, '    ', 'artwork', device.artwork);
		if (engine == 'upnp')
			element(lines, '    ', 'http_length', device.http_length);
		else
			element(lines, '    ', 'stop_receiver', device.stop_receiver ? 1 : 0);
		push(lines, '  </device>');
	}
	push(lines, '</' + root + '>');
	return join('\n', lines) + '\n';
};

export { normalizeConfig, renderXml };
