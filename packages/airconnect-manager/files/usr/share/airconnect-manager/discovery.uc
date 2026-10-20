// SPDX-License-Identifier: MIT
// SSDP only: this module never starts AirConnect or advertises an AirPlay service.
import * as socket from 'socket';
import * as fs from 'fs';

const BODY_LIMIT = 65536;
const RESPONSE_LIMIT = 64;
const DESCRIPTION_LIMIT = 32;
const SEARCH_TARGET = 'urn:schemas-upnp-org:device:MediaRenderer:1';

// ucode cannot express NUL in a regex bracket class, and `$` accepts a trailing
// newline, so reject control bytes with an explicit scan. Tab, LF and CR are
// permitted; everything else in 0x00-0x1f plus 0x7f is rejected.
function hasControl(value) {
	for (let i = 0; i < length(value); i++) {
		let c = ord(value, i);
		if (c == 0 || (c < 0x20 && c != 0x09 && c != 0x0a && c != 0x0d) || c == 0x7f)
			return true;
	}
	return false;
}

function now() {
	let t = clock(true);
	return t[0] + t[1] / 1000000;
}

// Canonical dotted IPv4 only. Refuse DNS, alternate numeric encodings and
// link-local/metadata, loopback, multicast and public destinations. This first
// release deliberately supports RFC1918 LANs only.
export function privateAddress(address) {
	if (type(address) != 'string' || !match(address, /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/))
		return false;
	let parts = split(address, '.');
	for (let p in parts)
		if (length(p) > 3 || (length(p) > 1 && substr(p, 0, 1) == '0') || int(p, 10) > 255)
			return false;
	return int(parts[0], 10) == 10 ||
		(int(parts[0], 10) == 172 && int(parts[1], 10) >= 16 && int(parts[1], 10) <= 31) ||
		(int(parts[0], 10) == 192 && int(parts[1], 10) == 168);
}

export function validateLocation(location, peer) {
	if (type(location) != 'string' || length(location) > 1024 || !privateAddress(peer))
		return null;
	// The path whitelist also forbids whitespace, backslashes and fragments.
	// Curl receives the URL as one quoted argument and URL globbing is disabled.
	let m = match(location, /^http:\/\/([0-9.]+)(:[0-9]+)?(\/[A-Za-z0-9._~!$&'()*+,;=:@%/?-]*)?$/);
	if (!m || m[1] != peer)
		return null;
	let port = m[2] ? int(substr(m[2], 1), 10) : 80;
	if (port < 1 || port > 65535 || (m[2] && length(m[2]) > 6))
		return null;
	return { location, address: peer, port };
}

export function parseSsdp(response, peer) {
	if (type(peer) == 'object')
		peer = peer.address;
	if (type(response) != 'string' || length(response) > 8192 ||
		hasControl(response))
		return null;
	let lines = split(replace(response, '\r\n', '\n'), '\n');
	if (!length(lines) || !match(lines[0], /^HTTP\/1\.[01] 200([ \t].*)?$/))
		return null;
	let headers = {};
	for (let i = 1; i < length(lines); i++) {
		if (lines[i] == '')
			break;
		let m = match(lines[i], /^([A-Za-z0-9-]+):[ \t]*(.*)$/);
		if (!m || length(lines[i]) > 2048)
			return null;
		let key = lc(m[1]);
		if (exists(headers, key))
			return null;
		headers[key] = trim(m[2]);
	}
	if (headers.st != SEARCH_TARGET)
		return null;
	let location = validateLocation(headers.location, peer);
	let usn = headers.usn ? split(headers.usn, '::')[0] : null;
	if (!location || !usn || length(usn) > 255 || !match(usn, /^uuid:[A-Za-z0-9._:-]+$/))
		return null;
	return { location: location.location, address: peer, udn: usn };
}

function codepoint(n) {
	if (n < 32 || n == 127 || n > 0x10ffff || (n >= 0xd800 && n <= 0xdfff))
		return null;
	if (n < 0x80) return chr(n);
	if (n < 0x800) return chr(0xc0 | (n >> 6), 0x80 | (n & 63));
	if (n < 0x10000) return chr(0xe0 | (n >> 12), 0x80 | ((n >> 6) & 63), 0x80 | (n & 63));
	return chr(0xf0 | (n >> 18), 0x80 | ((n >> 12) & 63), 0x80 | ((n >> 6) & 63), 0x80 | (n & 63));
}

function decodeText(value) {
	let good = true;
	let decoded = replace(value, /&([^;]*);/g, function(full, name) {
		let entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
		if (exists(entities, name)) return entities[name];
		let n = null;
		if (match(name, /^#[0-9]{1,7}$/)) n = int(substr(name, 1), 10);
		else if (match(name, /^#x[0-9A-Fa-f]{1,6}$/)) n = int(substr(name, 2), 16);
		let c = n == null ? null : codepoint(n);
		if (c == null) good = false;
		return c ?? '';
	});
	// A stray ampersand is malformed XML, but a decoded &amp; is valid text.
	if (match(replace(value, /&[^;]*;/g, ''), /&/)) good = false;
	return good ? trim(decoded) : null;
}

// A deliberately small, bounded XML tokenizer, not a general XML interpreter.
// No DTDs, entities, CDATA, processing instructions (except XML declaration),
// namespace tricks in extracted fields, nested field markup or external loads.
export function parseDescription(xml, candidate, seen) {
	if (type(xml) != 'string' || length(xml) > BODY_LIMIT || !length(xml) ||
		hasControl(xml) ||
		type(candidate) != 'object' || !privateAddress(candidate.address))
		return null;
	if (substr(xml, 0, 3) == chr(239, 187, 191)) xml = substr(xml, 3);
	let stack = [], devices = [], root = false, roots = 0, tags = 0, pos = 0;
	while (pos < length(xml)) {
		let start = index(xml, '<', pos);
		let text = substr(xml, pos, (start < 0 ? length(xml) : start) - pos);
		if (!length(stack) && length(trim(text))) return null;
		if (length(stack)) stack[length(stack) - 1].text += text;
		if (start < 0) { pos = length(xml); break; }
		if (substr(xml, start, 4) == '<!--') {
			let end = index(xml, '-->', start + 4);
			if (end < 0 || index(substr(xml, start + 4, end - start - 4), '--') >= 0) return null;
			pos = end + 3;
			continue;
		}
		if (match(substr(xml, start, 6), /^<\?xml[ \t\r\n]$/) && !root && !length(stack) && roots == 0 && !length(trim(substr(xml, 0, start)))) {
			let end = index(xml, '?>', start + 5);
			if (end < 0) return null;
			pos = end + 2;
			continue;
		}
		if (substr(xml, start, 2) == '<!' || substr(xml, start, 2) == '<?') return null;
		let end = start + 1, quote = null;
		for (; end < length(xml); end++) {
			let c = substr(xml, end, 1);
			if (quote) { if (c == quote) quote = null; }
			else if (c == '"' || c == "'") quote = c;
			else if (c == '>') break;
			else if (c == '<') return null;
		}
		if (end >= length(xml) || ++tags > 2048) return null;
		let token = substr(xml, start + 1, end - start - 1);
		pos = end + 1;
		let close = substr(token, 0, 1) == '/';
		let selfclose = !close && substr(token, -1) == '/';
		if (close) token = substr(token, 1);
		if (selfclose) token = substr(token, 0, length(token) - 1);
		let m = match(token, /^([A-Za-z_][A-Za-z0-9_.:-]*)([ \t\r\n].*)?$/s);
		if (!m || (close && length(trim(m[2] ?? '')))) return null;
		let name = m[1];
		// Validate attribute syntax instead of interpreting any attribute values.
		let attrs = m[2] ?? '';
		while (length(trim(attrs))) {
			let a = match(attrs, /^[ \t\r\n]+[A-Za-z_][A-Za-z0-9_.:-]*[ \t\r\n]*=[ \t\r\n]*("[^"]*"|'[^']*')/);
			if (!a || index(a[0], '<') >= 0) return null;
			attrs = substr(attrs, length(a[0]));
		}
		if (close) {
			if (!length(stack) || stack[length(stack) - 1].name != name) return null;
			let node = pop(stack);
			if (length(stack) && stack[length(stack) - 1].name == 'device' &&
				match(name, /^(deviceType|UDN|friendlyName|modelName|manufacturer)$/)) {
				let parent = stack[length(stack) - 1];
				let value = decodeText(node.text);
				if (node.children || value == null || exists(parent.fields, name)) return null;
				parent.fields[name] = value;
			}
			if (name == 'device') push(devices, node.fields);
			continue;
		}
		if (!length(stack)) {
			if (++roots != 1 || name != 'root') return null;
			root = true;
		}
		else stack[length(stack) - 1].children = true;
		if (length(stack) >= 32) return null;
		if (!selfclose) push(stack, { name, text: '', fields: {}, children: false });
	}
	if (!root || length(stack)) return null;
	for (let d in devices) {
		if (!match(d.deviceType ?? '', /^urn:schemas-upnp-org:device:MediaRenderer:[1-9][0-9]*$/) || d.UDN != candidate.udn || !length(d.UDN) || length(d.UDN) > 255 ||
			!match(d.UDN, /^uuid:[A-Za-z0-9._:-]+$/)) continue;
		if (length(d.friendlyName ?? '') > 255 || length(d.modelName ?? '') > 128 || length(d.manufacturer ?? '') > 128) return null;
		return {
			engine: 'upnp', udn: d.UDN, original_name: d.friendlyName || null,
			model: d.modelName || null, manufacturer: d.manufacturer || null,
			address: candidate.address, last_seen: seen ?? time(), online: true
		};
	}
	return null;
}

export function deduplicate(devices) {
	let seen = {}, result = [];
	for (let d in devices)
		if (d && d.engine == 'upnp' && d.udn && !seen[d.udn]) {
			seen[d.udn] = true;
			push(result, d);
		}
	return result;
}

function shellquote(value) {
	return "'" + replace(value, "'", "'\\''") + "'";
}

function fetchDescription(candidate, address, budget) {
	// -q must be first: ignore root's curlrc. No proxy, redirect, URL globbing,
	// DNS or other protocols. Both advertised and actual output size are bounded.
	let command = '/usr/bin/curl -q --silent --fail --globoff --noproxy ' + shellquote('*') +
		' --proto ' + shellquote('=http') + ' --max-redirs 0 --max-filesize 65536' +
		' --connect-timeout ' + sprintf('%.3f', budget) + ' --max-time ' + sprintf('%.3f', budget) +
		' --interface ' + shellquote(address) + ' -- ' + shellquote(candidate.location) + ' 2>/dev/null';
	let proc = fs.popen(command, 'r');
	if (!proc) return null;
	let body = proc.read(BODY_LIMIT + 1);
	let status = proc.close();
	if (status != 0 || type(body) != 'string' || length(body) > BODY_LIMIT) return null;
	return body;
}

// The interface is bound with SO_BINDTODEVICE, so only a bare Linux interface
// token is accepted. This is deliberately the same rule config.uc enforces for
// main.interface - first character [A-Za-z0-9_], the rest [A-Za-z0-9_.-], 1..15
// bytes, and neither '.' nor '..' - because a value allowed here and refused
// there could only fail after a socket had been created. `$` also matches a
// trailing newline in ucode, so the match must span the whole value.
function validInterface(value) {
	if (length(value) > 15 || value == '.' || value == '..')
		return false;
	let m = match(value, /^[A-Za-z0-9_][A-Za-z0-9_.-]*$/);
	return m != null && length(m[0]) == length(value);
}

export function discover(address, interfaceName) {
	if (!privateAddress(address) || type(interfaceName) != 'string' || !validInterface(interfaceName))
		die('Discovery requires a private IPv4 address and a valid network interface');
	let deadline = now() + 8;
	let sock = socket.create(socket.AF_INET, socket.SOCK_DGRAM | socket.SOCK_NONBLOCK | socket.SOCK_CLOEXEC, 0);
	if (!sock) die('Unable to create SSDP socket');
	if (!sock.setopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, interfaceName) ||
		!sock.bind({ address, port: 0 })) {
		sock.close();
		die('Unable to bind SSDP socket to the selected interface');
	}
	let request = 'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 2\r\nST: ' + SEARCH_TARGET + '\r\n\r\n';
	if (sock.send(request, 0, { address: '239.255.255.250', port: 1900 }) == null) {
		sock.close();
		die('Unable to send SSDP search');
	}
	let candidates = [], locations = {}, responses = 0;
	let searchDeadline = min(deadline, now() + 3);
	while (responses < RESPONSE_LIMIT && now() < searchDeadline) {
		let events = socket.poll(max(1, int((searchDeadline - now()) * 1000)), sock);
		if (events == null) { sock.close(); die('Unable to poll SSDP socket'); }
		if (!length(events)) break;
		let peer = {};
		let response = sock.recv(8193, socket.MSG_DONTWAIT, peer);
		if (response == null) continue;
		responses++;
		let c = parseSsdp(response, peer);
		if (c && !locations[c.location] && length(candidates) < DESCRIPTION_LIMIT) {
			locations[c.location] = true;
			push(candidates, c);
		}
	}
	sock.close();
	let devices = [];
	for (let c in candidates) {
		// Reserve time for cleanup and parsing; never start another network call
		// after the shared budget, even when a hostile LAN returns many URLs.
		let remaining = deadline - now() - 0.1;
		if (remaining < 0.1) break;
		let body = fetchDescription(c, address, min(2, remaining));
		if (body != null) {
			let device = parseDescription(body, c, time());
			if (device) push(devices, device);
		}
	}
	return deduplicate(devices);
}
