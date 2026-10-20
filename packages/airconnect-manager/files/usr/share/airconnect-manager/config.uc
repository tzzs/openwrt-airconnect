// SPDX-License-Identifier: MIT
// Pure validation and serialization. This module does not read UCI or write files.

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
		if (!match(value, integer ? /^(0|[1-9][0-9]*)$/ : /^(0|[1-9][0-9]*)(\.[0-9]+)?$/))
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
	if (value == 'wav' || value == 'pcm' || value == 'flac' || match(value, /^flac:[0-9]$/))
		return value;
	let parts = match(value, /^(mp3|aac)(:([1-9][0-9]{1,2}))?$/);
	if (parts) {
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
	if (!parts || int(parts[1]) > 10000 || int(parts[2]) > 10000)
		invalid(path, 'expected RTP:HTTP integers in 0..10000');
	return value;
}

function inherited(source, key, fallback) {
	return !exists(source, key) || source[key] === '' ? fallback : source[key];
}

export function normalizeConfig(input) {
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
		log_level: option(source, 'log_level', 'warn')
	};
	if (type(main.interface) != 'string' || length(main.interface) > 15 ||
		!match(main.interface, /^[A-Za-z0-9_][A-Za-z0-9_.-]*$/) ||
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
			latency: latency(inherited(entry, 'latency', main.latency), path + '.latency')
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
}

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

export function renderXml(normalized, engine) {
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
		push(lines, '  </device>');
	}
	push(lines, '</' + root + '>');
	return join('\n', lines) + '\n';
}
