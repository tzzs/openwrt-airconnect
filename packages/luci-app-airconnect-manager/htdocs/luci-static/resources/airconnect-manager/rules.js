// SPDX-License-Identifier: MIT
// Field rules shared by every AirConnect Manager form.
//
// These functions are the browser half of the validation contract that
// /usr/share/airconnect-manager/config.uc enforces on the router. Each one
// takes a raw form value and returns `true` when it is acceptable, or a short
// user-facing message string when it is not - exactly what a LuCI form
// `validate` callback may return.
//
// tests/parity/cases.json is the shared contract. tests/parity/run.uc proves
// the backend honours that table and tests/parity/check-frontend.mjs proves
// these functions agree with it. Never loosen one side to make the other pass:
// the backend is the authority, the view must tighten to match it.
//
// LuCI loads this file with `'require airconnect-manager.rules'`, and its
// `require` is not a general module loader: the factory must yield a class
// (`Class.isSubclass(factory())`), which LuCI then instantiates and hands to the
// view. Returning a plain object aborts the entire view with
//   TypeError: "airconnect-manager.rules" factory yields invalid constructor
// so the rules are prototype methods of a `L.Class.extend()` class. `L` is one
// of the arguments LuCI passes to every class file; nothing else of the LuCI
// API is touched, and tests/parity/check-frontend.mjs builds the same class
// through a minimal `L.Class` shim before instantiating it.
//
// `_` is only consulted when a rule runs, and the messages fall back to plain
// English strings when no translation helper is present.

'use strict';

var t = (typeof _ === 'function') ? _ : function(s) { return s; };

// ucode's `$` also matches before a trailing newline, JavaScript's does not.
// The backend therefore compares the matched length against the value length,
// and this file does the same: the two implementations stay structurally
// identical, so a later edit (an `m` flag, a lookahead, a looser class) cannot
// silently make the browser accept what the router rejects.
function full(value, pattern) {
	var match = pattern.exec(value);
	return match != null && match[0].length === value.length;
}

function text(value) {
	return value == null ? '' : String(value);
}

function utf8Length(value) {
	if (typeof TextEncoder === 'function')
		return new TextEncoder().encode(value).length;
	// Fallback for engines without TextEncoder. It counts the same bytes the
	// encoder would produce, so the 63-byte limit does not depend on it.
	var bytes = 0;
	for (var i = 0; i < value.length; i++) {
		var code = value.charCodeAt(i);
		if (code < 0x80)
			bytes += 1;
		else if (code < 0x800)
			bytes += 2;
		else if (code >= 0xd800 && code <= 0xdbff && i + 1 < value.length &&
			value.charCodeAt(i + 1) >= 0xdc00 && value.charCodeAt(i + 1) <= 0xdfff) {
			bytes += 4;
			i++;
		}
		else
			bytes += 3;
	}
	return bytes;
}

function interfaceValue(value) {
	var v = text(value);
	if (v.length < 1 || v.length > 15 || v === '.' || v === '..' ||
	    !full(v, /^[A-Za-z0-9_][A-Za-z0-9_.-]*$/))
		return t('Enter an interface name of 1-15 characters that starts with a letter or digit.');
	return true;
}

function upnpVolume(value) {
	var v = text(value);
	if (!full(v, /^(0|[1-9][0-9]*)$/) || Number(v) < 1 || Number(v) > 100)
		return t('Use a whole number from 1 to 100.');
	return true;
}

function castVolume(value) {
	var v = text(value);
	if (!full(v, /^(0|[1-9][0-9]*)(\.[0-9]+)?$/) || Number(v) > 1)
		return t('Use a number from 0 to 1, for example 0.5.');
	return true;
}

function latency(value) {
	var v = text(value);
	var parts = v.split(':');
	var message = t('Use two whole numbers from 0 to 10000 separated by a colon, for example 1000:2000.');
	if (parts.length !== 2)
		return message;
	for (var i = 0; i < 2; i++) {
		if (!full(parts[i], /^(0|[1-9][0-9]{0,4})$/) || Number(parts[i]) > 10000)
			return message;
	}
	return true;
}

// Unicode whitespace, matching config.uc's whitespace() list: `\s` covers the
// ASCII controls and most separators, the explicit code points cover the rest.
var WHITESPACE = /[\s\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]/;

function airplayName(value) {
	var v = text(value);
	if (v === '')
		return true;
	if (utf8Length(v) > 63)
		return t('Use at most 63 bytes for the AirPlay name.');
	var visible = false;
	for (var i = 0; i < v.length; i++) {
		var code = v.charCodeAt(i);
		// A lone surrogate has no UTF-8 form. The backend would silently receive
		// the replacement character instead, so reject it here rather than let a
		// speaker be renamed to something the user never typed.
		if (code >= 0xd800 && code <= 0xdbff) {
			var next = i + 1 < v.length ? v.charCodeAt(i + 1) : 0;
			if (next < 0xdc00 || next > 0xdfff)
				return t('Remove control or invalid characters from the AirPlay name.');
			i++;
			visible = true;
			continue;
		}
		if (code >= 0xdc00 && code <= 0xdfff)
			return t('Remove control or invalid characters from the AirPlay name.');
		if (code < 0x20 || (code >= 0x7f && code <= 0x9f) || code === 0xfffe || code === 0xffff)
			return t('Remove control or invalid characters from the AirPlay name.');
		if (!WHITESPACE.test(String.fromCharCode(code)))
			visible = true;
	}
	if (!visible)
		return t('Use a name that is not only spaces.');
	return true;
}

function logLevel(value) {
	var v = text(value);
	if (['error', 'warn', 'info', 'debug'].indexOf(v) < 0)
		return t('Choose error, warn, info or debug.');
	return true;
}

// The 0/1 switches upstream reads with atoi()/atol() into a bool: metadata,
// flush, drift and stop_receiver all go through this one rule, because they are
// the same contract. config.uc's boolean() accepts "0", "1", 0 and 1 only, so
// the browser must not accept "true", "yes" or an empty string either.
function binaryFlag(value) {
	var v = text(value);
	if (v !== '0' && v !== '1')
		return t('Choose off (0) or on (1).');
	return true;
}

// The three transfer modes upstream documents for http_length (`-g -3|-1|0`,
// README "HTTP content-length and transfer modes"). It is an enum, never a
// free number: any other integer becomes a literal Content-Length header.
function httpLength(value) {
	var v = text(value);
	if (['-3', '-1', '0'].indexOf(v) < 0)
		return t('Choose -3 (chunked), -1 (no content-length) or 0 (fixed length).');
	return true;
}

// airupnp builds the search topic in char[sizeof(URN) + 2], i.e. the URN, ':',
// one digit and the terminating NUL, so 9 is the largest usable version.
function upnpMax(value) {
	var v = text(value);
	if (!full(v, /^(0|[1-9][0-9]*)$/) || Number(v) < 1 || Number(v) > 9)
		return t('Use a whole number from 1 to 9.');
	return true;
}

// Byte set from config.uc's ARTWORK_BYTES: RFC 3986 unreserved + sub-delims +
// ':' '@' '/' '?' '#' '-' '[' ']'. Checked per character rather than with one
// large character class so the two implementations cannot drift on escaping.
var ARTWORK_MAX = 512;
var ARTWORK_BYTES = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~%!$&()*+,;=:@/?#-[]';

function artwork(value) {
	var v = text(value);
	// Empty means "no artwork", which is the upstream default.
	if (v === '')
		return true;
	if (utf8Length(v) > ARTWORK_MAX)
		return t('Use at most 512 bytes for the artwork URL.');
	var offset = v.indexOf('https://') === 0 ? 8 : v.indexOf('http://') === 0 ? 7 : 0;
	if (offset === 0)
		return t('Use a lowercase http:// or https:// URL.');
	if (v.length === offset)
		return t('Add a host after http:// or https://.');
	for (var i = offset; i < v.length; i++) {
		if (ARTWORK_BYTES.indexOf(v.charAt(i)) < 0)
			return t('Remove spaces, quotes or control characters from the artwork URL.');
	}
	return true;
}

// A class, not an object literal: LuCI rejects anything else (see the header).
return L.Class.extend({
	interfaceValue: interfaceValue,
	upnpVolume: upnpVolume,
	castVolume: castVolume,
	latency: latency,
	airplayName: airplayName,
	logLevel: logLevel,
	binaryFlag: binaryFlag,
	httpLength: httpLength,
	upnpMax: upnpMax,
	artwork: artwork
});
