/**
 * Field validation rules, the browser half of the shared contract.
 *
 * The backend (/usr/share/airconnect-manager/config.uc) is the authority:
 * tests/parity/run.uc produces the canonical verdicts and
 * tests/parity/check-frontend.mjs compares these functions against them. Each
 * rule takes a raw form value and returns `true` when acceptable or a short
 * user-facing message string when not - exactly what a form validation callback
 * expects.
 *
 * `createRules(t)` takes the translation helper (`_` in LuCI) so the same
 * source serves both the rendered app and the host test runner, where no
 * translation helper is present and the messages fall back to English.
 */

// ucode's `$` matches one extra position before a trailing newline; JavaScript's
// `.exec` does not. The backend compares the matched length against the value
// length, and this file does the same, so the two stay structurally identical
// and a later loosening cannot silently diverge.
function full(value, pattern) {
	const match = pattern.exec(value);
	return match != null && match[0].length === value.length;
}

function text(value) {
	return value == null ? '' : String(value);
}

function utf8Length(value) {
	if (typeof TextEncoder === 'function') return new TextEncoder().encode(value).length;
	let bytes = 0;
	for (let i = 0; i < value.length; i++) {
		const code = value.charCodeAt(i);
		if (code < 0x80) bytes += 1;
		else if (code < 0x800) bytes += 2;
		else if (code >= 0xd800 && code <= 0xdbff && i + 1 < value.length &&
			value.charCodeAt(i + 1) >= 0xdc00 && value.charCodeAt(i + 1) <= 0xdfff) {
			bytes += 4;
			i++;
		} else bytes += 3;
	}
	return bytes;
}

// The exact set JavaScript's `\s` matches. Listed as code points instead of a
// regular-expression literal because U+2028/U+2029 are line terminators and
// cannot appear literally in source.
const WHITESPACE_CODES = [
	0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x20, 0xa0, 0x1680,
	0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007,
	0x2008, 0x2009, 0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff
];

function isWhitespace(code) {
	return WHITESPACE_CODES.indexOf(code) !== -1;
}

export function createRules(t) {
	const _ = typeof t === 'function' ? t : function (s) { return s; };

	function interfaceValue(value) {
		const v = text(value);
		if (v.length < 1 || v.length > 15 || v === '.' || v === '..' ||
			!full(v, /^[A-Za-z0-9_][A-Za-z0-9_.-]*$/))
			return _('Enter an interface name of 1-15 characters that starts with a letter or digit.');
		return true;
	}

	function upnpVolume(value) {
		const v = text(value);
		if (!full(v, /^(0|[1-9][0-9]*)$/) || Number(v) < 1 || Number(v) > 100)
			return _('Use a whole number from 1 to 100.');
		return true;
	}

	function castVolume(value) {
		const v = text(value);
		if (!full(v, /^(0|[1-9][0-9]*)(\.[0-9]+)?$/) || Number(v) > 1)
			return _('Use a number from 0 to 1, for example 0.5.');
		return true;
	}

	function latency(value) {
		const v = text(value);
		const parts = v.split(':');
		const message = _('Use two whole numbers from 0 to 10000 separated by a colon, for example 1000:2000.');
		if (parts.length !== 2) return message;
		for (let i = 0; i < 2; i++) {
			if (!full(parts[i], /^(0|[1-9][0-9]{0,4})$/) || Number(parts[i]) > 10000) return message;
		}
		return true;
	}

	function airplayName(value) {
		const v = text(value);
		if (v === '') return true;
		if (utf8Length(v) > 63) return _('Use at most 63 bytes for the AirPlay name.');
		let visible = false;
		for (let i = 0; i < v.length; i++) {
			const code = v.charCodeAt(i);
			if (code >= 0xd800 && code <= 0xdbff) {
				const next = i + 1 < v.length ? v.charCodeAt(i + 1) : 0;
				if (next < 0xdc00 || next > 0xdfff) return _('Remove control or invalid characters from the AirPlay name.');
				i++;
				visible = true;
				continue;
			}
			if (code >= 0xdc00 && code <= 0xdfff) return _('Remove control or invalid characters from the AirPlay name.');
			if (code < 0x20 || (code >= 0x7f && code <= 0x9f) || code === 0xfffe || code === 0xffff)
				return _('Remove control or invalid characters from the AirPlay name.');
			if (!isWhitespace(code)) visible = true;
		}
		if (!visible) return _('Use a name that is not only spaces.');
		return true;
	}

	function logLevel(value) {
		const v = text(value);
		if (['error', 'warn', 'info', 'debug'].indexOf(v) < 0)
			return _('Choose error, warn, info or debug.');
		return true;
	}

	function binaryFlag(value) {
		const v = text(value);
		if (v !== '0' && v !== '1') return _('Choose off (0) or on (1).');
		return true;
	}

	function httpLength(value) {
		const v = text(value);
		if (['-3', '-1', '0'].indexOf(v) < 0)
			return _('Choose -3 (chunked), -1 (no content-length) or 0 (fixed length).');
		return true;
	}

	function upnpMax(value) {
		const v = text(value);
		if (!full(v, /^(0|[1-9][0-9]*)$/) || Number(v) < 1 || Number(v) > 9)
			return _('Use a whole number from 1 to 9.');
		return true;
	}

	const ARTWORK_MAX = 512;
	const ARTWORK_BYTES = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~%!$&()*+,;=:@/?#-[]';

	function artwork(value) {
		const v = text(value);
		if (v === '') return true;
		if (utf8Length(v) > ARTWORK_MAX) return _('Use at most 512 bytes for the artwork URL.');
		const offset = v.indexOf('https://') === 0 ? 8 : v.indexOf('http://') === 0 ? 7 : 0;
		if (offset === 0) return _('Use a lowercase http:// or https:// URL.');
		if (v.length === offset) return _('Add a host after http:// or https://.');
		for (let i = offset; i < v.length; i++) {
			if (ARTWORK_BYTES.indexOf(v.charAt(i)) < 0)
				return _('Remove spaces, quotes or control characters from the artwork URL.');
		}
		return true;
	}

	return {
		interfaceValue,
		upnpVolume,
		castVolume,
		latency,
		airplayName,
		logLevel,
		binaryFlag,
		httpLength,
		upnpMax,
		artwork
	};
}
