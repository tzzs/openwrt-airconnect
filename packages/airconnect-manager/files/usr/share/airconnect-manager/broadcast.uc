// SPDX-License-Identifier: MIT
// mDNS observation of the AirPlay advertisement AirConnect itself publishes.
//
// discovery.uc finds DLNA/Chromecast speakers on the LAN. This module is its
// counterpart: it reads the _raop._tcp service the AirConnect engines register
// for those speakers, which is the only part of "is it broadcasting?" that the
// upstream surface actually exposes.
//
// What the evidence supports (all verified against the 1.12.4 sources and the
// shipped static binaries, see docs/VERIFICATION.zh-CN.md):
//
//   - raop_server.c:raopsr_create() registers exactly one service type,
//     "_raop._tcp.local", with an instance name of
//     "<12 uppercase hex of the device MAC>@<AirPlay name>".
//   - Its TXT record carries "am=<model>", where model is the string the caller
//     passes: "airupnp" from airupnp.c or "aircast" from aircast.c. That is an
//     unambiguous, per-engine marker and it is what services.<engine> keys on.
//   - There is no _airplay._tcp registration and no status API. "Playing" is not
//     observable and is never reported here.
//
// The per-device key is the MAC prefix, and it is only reliable when the engine
// had to synthesise the MAC. airupnp.c:1014-1024 and aircast.c:663-671 read the
// real MAC through SendARP() first and only fall back to hash32(UDN). The Linux
// SendARP() in crosstools/cross_net.c hardcodes areq.arp_dev = "eth0", so the
// fallback is guaranteed whenever the configured LAN interface is not literally
// "eth0". When it is, the prefix could be either the hash or the speaker's real
// MAC bytes 2..5, which this manager cannot derive, so the per-device state is
// reported as unknown rather than guessed.
//
// Everything here is bounded: one packet, one query, a short deadline, a record
// cap and a pointer-loop guard. Every failure mode returns unknown.
// Why `const f = function() {}` plus `export { }` instead of `export function f`
// ---------------------------------------------------------------------------
// The ucode runtime shipped by the target (libucode.so.20230711, as installed by
// iStoreOS 25.12.5) rejects `export function` with "Syntax error: Unexpected
// token / Expecting ';'". `export const` and a trailing `export { ... }` list do
// compile there and the imported binding is callable, so that is the form every
// module in this package uses. Do not "modernise" it back: it verifiably fails
// to load on the device, and the host test runner uses a newer ucode that would
// not catch the regression.

import * as socket from 'socket';

// A reply larger than this is dropped before parsing, so a hostile or broken
// responder cannot grow memory or the loop count. A real advertisement measured
// on the wire is 244 bytes.
const PACKET_LIMIT = 4096;
// Hard cap on records parsed across all three sections.
const RECORD_LIMIT = 64;
// Upstream truncates the instance name to 63 bytes (raop_server.c:151-153).
const INSTANCE_LIMIT = 63;
const MDNS_ADDR = '224.0.0.251';
const MDNS_PORT = 5353;
const RAOP_TYPE = '_raop._tcp.local';
// The interface name that makes the engine's SendARP() call able to succeed.
// See the header: crosstools/cross_net.c hardcodes arp_dev to this literal.
const ARP_INTERFACE = 'eth0';

function now() {
	let t = clock(true);
	return t[0] + t[1] / 1000000;
}

function u16(data, pos) {
	if (pos < 0 || pos + 1 >= length(data))
		return null;
	return (ord(data, pos) << 8) | ord(data, pos + 1);
}

// djb2-33, matching hash32() in crosstools/cross_util.c. ucode integers are not
// truncated to 32 bits, so the running value is kept below 2^32 explicitly; every
// intermediate stays non-negative and below 2^32, which reproduces the C
// uint32_t wrap exactly.
const hash32 = function(value) {
	if (type(value) != 'string')
		return null;
	let hash = 5381;
	for (let i = 0; i < length(value); i++)
		hash = (hash * 33 + ord(value, i)) % 4294967296;
	return hash;
};

// The 12-hex-character prefix AirConnect puts at the front of every _raop
// instance name, for the synthesised-MAC path. hash32(UDN) is stored
// little-endian into MAC bytes 2..5 (airupnp.c:1020) and bytes 0..1 are set to
// 0xbb for airupnp or 0xcc for aircast. Both spellings are returned because the
// manager cannot tell which engine hosts a device from the advertisement alone.
const macPrefixes = function(udn) {
	let h = hash32(udn);
	if (h == null)
		return null;
	let bytes = [];
	for (let i = 0; i < 4; i++) {
		push(bytes, h % 256);
		h = (h - (h % 256)) / 256;
	}
	let suffix = '';
	for (let i = 0; i < 4; i++)
		suffix += sprintf('%02X', bytes[i]);
	return { upnp: 'BBBB' + suffix, cast: 'CCCC' + suffix };
};

// Read one DNS name, following compression pointers. Returns { name, end } where
// end is the offset just past the name as first encountered. Returns null on a
// truncated name, a label over 63 bytes, a pointer that does not point strictly
// backwards, or more than 64 hops (a pointer loop).
function readName(data, pos) {
	let labels = [], end = pos, jumped = false, hops = 0, bytes = 0;
	while (true) {
		if (++hops > 64 || pos >= length(data))
			return null;
		let b = ord(data, pos);
		if (b == 0) {
			pos++;
			if (!jumped)
				end = pos;
			break;
		}
		if ((b & 0xc0) == 0xc0) {
			let ptr = u16(data, pos);
			if (ptr == null)
				return null;
			ptr = ptr & 0x3fff;
			if (!jumped)
				end = pos + 2;
			// A pointer must move strictly backwards; anything else is a loop.
			if (ptr >= pos)
				return null;
			pos = ptr;
			jumped = true;
			continue;
		}
		if (b & 0xc0)
			return null;
		pos++;
		bytes += b + 1;
		if (pos + b > length(data) || bytes > 255)
			return null;
		let label = '';
		for (let i = 0; i < b; i++)
			label += chr(ord(data, pos + i));
		push(labels, label);
		pos += b;
	}
	return { name: join('.', labels), labels: labels, end: end };
}

function lower(value) {
	let out = '';
	for (let i = 0; i < length(value); i++) {
		let c = ord(value, i);
		if (c >= 0x41 && c <= 0x5a)
			c += 0x20;
		out += chr(c);
	}
	return out;
}

function upper(value) {
	let out = '';
	for (let i = 0; i < length(value); i++) {
		let c = ord(value, i);
		if (c >= 0x61 && c <= 0x7a)
			c -= 0x20;
		out += chr(c);
	}
	return out;
}

// Extract the instance name from a name that ends in the _raop._tcp.local
// service type. mDNS stores the instance as a single 63-byte label, but an
// AirPlay name containing a dot is published verbatim inside that label, so the
// instance is every label before the trailing type, rejoined. Returns null when
// the name is not a _raop service name at all.
function raopInstance(parsedName) {
	let labels = parsedName.labels;
	let count = length(labels);
	if (count < 4)
		return null;
	if (lower(labels[count - 3]) != '_raop' || lower(labels[count - 2]) != '_tcp' ||
		lower(labels[count - 1]) != 'local')
		return null;
	let parts = [];
	for (let i = 0; i < count - 3; i++)
		push(parts, labels[i]);
	let instance = join('.', parts);
	if (length(instance) == 0 || length(instance) > INSTANCE_LIMIT)
		return null;
	return instance;
}

// A DNS TXT rdata block is a sequence of length-prefixed strings. Returns the
// list of strings, or null if the block is malformed.
function txtStrings(rdata) {
	let result = [], pos = 0;
	while (pos < length(rdata)) {
		let len = ord(rdata, pos);
		pos++;
		if (pos + len > length(rdata))
			return null;
		push(result, substr(rdata, pos, len));
		pos += len;
	}
	return result;
}

// The "am=" value of a TXT record, lowercased, or null when absent or malformed.
// Upstream writes it as the first TXT entry (raop_server.c:138, txt[0]).
function txtModel(strings) {
	for (let item in strings) {
		if (substr(item, 0, 3) == 'am=')
			return lower(substr(item, 3));
	}
	return null;
}

// Parse an mDNS response. Returns
//   { instances: [ { name, model } ], complete: true }
// for a well-formed standard response, or null when the packet is not a standard
// response or any record is malformed. An empty instances list is a valid
// answer: the responder was heard and advertised no _raop service.
//
// Only the PTR records whose owner name is exactly _raop._tcp.local contribute
// instances; the _services._dns-sd._udp.local enumeration PTR is ignored, so a
// service-type listing can never be mistaken for a receiver. TXT records are
// associated by instance name across all three sections, which is how mDNS
// sends them (answer + additional).
const parseResponse = function(data) {
	if (type(data) != 'string' || length(data) < 12 || length(data) > PACKET_LIMIT)
		return null;
	let flags = u16(data, 2);
	// QR must be 1 and the opcode 0: a query or an update is not an advertisement.
	if (flags == null || (flags & 0xf800) != 0x8000)
		return null;
	let qd = u16(data, 4), an = u16(data, 6), ns = u16(data, 8), ar = u16(data, 10);
	if (qd == null || qd > 1 || an == null || ns == null || ar == null)
		return null;
	if (an > RECORD_LIMIT || ns > RECORD_LIMIT || ar > RECORD_LIMIT)
		return null;
	let pos = 12;
	for (let i = 0; i < qd; i++) {
		let question = readName(data, pos);
		if (question == null)
			return null;
		pos = question.end + 4;
		if (pos > length(data))
			return null;
	}
	let order = [], names = {}, models = {};
	for (let section = 0; section < 3; section++) {
		let count = [an, ns, ar][section];
		for (let i = 0; i < count; i++) {
			let owner = readName(data, pos);
			if (owner == null)
				return null;
			pos = owner.end;
			let rtype = u16(data, pos), rclass = u16(data, pos + 2);
			let rdlen = u16(data, pos + 8);
			if (rtype == null || rclass == null || rdlen == null)
				return null;
			pos += 10;
			if (pos + rdlen > length(data))
				return null;
			// mDNS sets the cache-flush bit in the class; mask it off.
			rclass = rclass & 0x7fff;
			let rdata = substr(data, pos, rdlen);
			if (rclass == 1) {
				if (rtype == 12 && lower(owner.name) == RAOP_TYPE) {
					let target = readName(data, pos);
					if (target == null)
						return null;
					// A PTR target is the instance name followed by the service type
					// ("<instance>._raop._tcp.local").
					let instance = raopInstance(target);
					if (instance == null)
						return null;
					let key = lower(instance);
					if (!exists(names, key)) {
						names[key] = instance;
						push(order, key);
					}
				}
				else if (rtype == 16) {
					let strings = txtStrings(rdata);
					if (strings == null)
						return null;
					// The TXT owner is the instance name plus the service type, so it is
					// keyed the same way the PTR was.
					let instance = raopInstance(owner);
					if (instance == null)
						return null;
					let key = lower(instance);
					let model = txtModel(strings);
					if (model != null && !exists(models, key))
						models[key] = model;
				}
			}
			pos += rdlen;
		}
	}
	let instances = [];
	for (let key in order)
		push(instances, { name: names[key], model: exists(models, key) ? models[key] : null });
	return { complete: true, instances: instances };
};

// The MAC prefix carried by an instance name, uppercased, or null when the name
// does not begin with 12 hex characters followed by "@".
const instancePrefix = function(name) {
	if (type(name) != 'string' || length(name) < 13)
		return null;
	let prefix = upper(substr(name, 0, 12));
	if (!match(prefix, /^[0-9A-F]{12}$/) || substr(name, 12, 1) != '@')
		return null;
	return prefix;
};

// Whether the configured interface lets the engine take the synthesised-MAC
// path. Only then is the prefix derivable from the UDN. See the header.
const prefixIsDerivable = function(interfaceName) {
	return type(interfaceName) == 'string' && interfaceName != '' &&
		lower(interfaceName) != ARP_INTERFACE;
};

// Reduce one completed scan to the per-engine service state. An engine is
// broadcasting when an instance advertised with its own am= marker. Returns null
// when the scan did not complete, which the caller must render as unknown.
const engineStates = function(scanResult) {
	if (type(scanResult) != 'object' || scanResult == null || scanResult.complete !== true)
		return null;
	let instances = type(scanResult.instances) == 'array' ? scanResult.instances : [];
	let states = { upnp: false, cast: false };
	for (let instance in instances) {
		if (type(instance) != 'object' || instance == null)
			continue;
		if (instance.model == 'airupnp')
			states.upnp = true;
		else if (instance.model == 'aircast')
			states.cast = true;
	}
	return states;
};

// Reduce one completed scan to a per-device state. Returns true, false or null:
// null means unknown and is returned whenever the answer would be a guess -
// the scan did not complete, the interface makes the prefix ambiguous, the
// device has no UDN, or two different instances claim the same prefix.
const deviceState = function(scanResult, interfaceName, udn) {
	if (type(scanResult) != 'object' || scanResult == null || scanResult.complete !== true)
		return null;
	if (!prefixIsDerivable(interfaceName))
		return null;
	let prefixes = macPrefixes(udn);
	if (prefixes == null)
		return null;
	let instances = type(scanResult.instances) == 'array' ? scanResult.instances : [];
	let hits = [];
	for (let instance in instances) {
		if (type(instance) != 'object' || instance == null)
			continue;
		let prefix = instancePrefix(instance.name);
		if (prefix == null)
			continue;
		if (prefix == prefixes.upnp || prefix == prefixes.cast)
			push(hits, instance.name);
	}
	// A scan that completed with no match is a measured negative.
	if (length(hits) == 0)
		return false;
	// More than one distinct instance under one prefix cannot be attributed to
	// this device, so it is not a positive either.
	let distinct = {};
	for (let name in hits)
		distinct[lower(name)] = true;
	return length(keys(distinct)) == 1 ? true : null;
};

// One bounded mDNS query. The socket is non-blocking, the deadline is short, and
// the loop stops at the first acceptable reply. Returns
//   { complete: true,  instances: [...] }   when a reply was parsed, or
//   { complete: false, reason: "..." }      for every other outcome.
// The caller must treat complete:false as unknown, never as "not broadcasting".
const scan = function(address, interfaceName) {
	if (type(address) != 'string' || !match(address, /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/))
		die('Broadcast scan requires a valid IPv4 address');
	if (type(interfaceName) != 'string' || length(interfaceName) > 15 ||
		interfaceName == '.' || interfaceName == '..' ||
		!match(interfaceName, /^[A-Za-z0-9_][A-Za-z0-9_.-]*$/))
		die('Broadcast scan requires a valid network interface');
	let deadline = now() + 3;
	let sock = socket.create(socket.AF_INET,
		socket.SOCK_DGRAM | socket.SOCK_NONBLOCK | socket.SOCK_CLOEXEC, 0);
	if (!sock)
		die('Unable to create the mDNS socket');
	let bound = sock.setopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, interfaceName) &&
		sock.bind({ address: address, port: 0 }) &&
		sock.setopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF,
			{ multiaddr: address, address: '0.0.0.0', ifindex: 0 });
	if (!bound) {
		sock.close();
		die('Unable to bind the mDNS socket to the selected interface');
	}
	// One standard query: id 0, QDCOUNT 1, QNAME _raop._tcp.local, QTYPE PTR (12),
	// QCLASS IN with the QU bit (0x8001) so the responder answers by unicast and
	// the scan does not stir every mDNS listener on the LAN into multicast.
	let query = chr(0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0) +
		chr(5) + '_raop' + chr(4) + '_tcp' + chr(5) + 'local' + chr(0) +
		chr(0, 12, 0x80, 0x01);
	if (sock.send(query, 0, { address: MDNS_ADDR, port: MDNS_PORT }) == null) {
		sock.close();
		die('Unable to send the mDNS query');
	}
	let raw = null;
	while (now() < deadline) {
		let events = socket.poll(max(1, int((deadline - now()) * 1000)), sock);
		if (events == null) {
			sock.close();
			die('Unable to poll the mDNS socket');
		}
		if (!length(events))
			break;
		let peer = {};
		let reply = sock.recv(PACKET_LIMIT + 1, socket.MSG_DONTWAIT, peer);
		if (reply == null)
			continue;
		// An oversize packet is dropped before parsing; it cannot flip a state.
		if (length(reply) > PACKET_LIMIT)
			continue;
		raw = reply;
		break;
	}
	sock.close();
	if (raw == null)
		return { complete: false, reason: 'no reply' };
	let parsed = parseResponse(raw);
	if (parsed == null)
		return { complete: false, reason: 'unparsable reply' };
	return parsed;
};

export { hash32, macPrefixes, parseResponse, instancePrefix, prefixIsDerivable, engineStates, deviceState, scan };
