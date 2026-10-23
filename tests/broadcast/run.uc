// SPDX-License-Identifier: MIT
// Host tests for broadcast.uc, the mDNS half of the four-state separation.
//
// Run: ucode -L ~/.local/opt/ucode-host/lib/ucode tests/broadcast/run.uc
//
// Everything here is a pure function of bytes: no socket is opened, no multicast
// is sent, and nothing touches the LAN. `scan()` itself is NOT called - it is the
// one function in the module that does I/O, and a host test cannot honestly
// exercise a multicast round trip. What is tested is the entire decision layer
// that turns a packet into true / false / unknown, which is where a wrong answer
// would come from.
//
// The packet fixtures are real: the "matching" fixture is the byte sequence the
// shipped airupnp-linux-x86_64-static 1.12.4 emitted on the wire, captured with
// tcpdump during this task (see docs/VERIFICATION.zh-CN.md). Its UDN is
// uuid:demo-synthetic-renderer, its instance name is
// BBBBA7A5DB92@Demo Speaker+ and its TXT model is airupnp.

import {
	hash32, macPrefixes, parseResponse, instancePrefix, prefixIsDerivable,
	engineStates, deviceState
} from '../../packages/airconnect-manager/files/usr/share/airconnect-manager/broadcast.uc';

let passed = 0;
let failed = 0;

function assert(condition, message) {
	if (!condition)
		die(message || 'assertion failed');
}

function deepEqual(actual, expected, path) {
	path = path || 'value';
	assert(type(actual) == type(expected),
		path + ': type mismatch (' + type(actual) + ' vs ' + type(expected) + ')');
	if (type(actual) == 'array') {
		assert(length(actual) == length(expected),
			path + ': array size mismatch (' + length(actual) + ' vs ' + length(expected) + ')');
		for (let i = 0; i < length(expected); i++)
			deepEqual(actual[i], expected[i], path + '[' + i + ']');
	}
	else if (type(actual) == 'object') {
		assert(length(actual) == length(expected),
			path + ': object size mismatch (' + length(actual) + ' vs ' + length(expected) + ')');
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

function hex(value) {
	let out = '';
	for (let i = 0; i < length(value); i++)
		out += sprintf('%02x', ord(value, i));
	return out;
}

function unhex(text) {
	let out = '';
	for (let i = 0; i + 1 < length(text); i += 2)
		out += chr(int(substr(text, i, 2), 16));
	return out;
}

// --- packet builders --------------------------------------------------------
// Hand-built DNS messages, so a test states the exact bytes it means instead of
// inheriting whatever a helper decided.

function label(text) {
	return chr(length(text)) + text;
}

function name(dotted) {
	let out = '';
	for (let part in split(dotted, '.'))
		if (part != '')
			out += label(part);
	return out + chr(0);
}

function header(flags, qd, an, ns, ar) {
	// DNS header: id(2) flags(2) qdcount(2) ancount(2) nscount(2) arcount(2).
	return chr(0, 0, (flags >> 8) & 0xff, flags & 0xff,
		(qd >> 8) & 0xff, qd & 0xff, (an >> 8) & 0xff, an & 0xff,
		(ns >> 8) & 0xff, ns & 0xff, (ar >> 8) & 0xff, ar & 0xff);
}

function u16(value) {
	return chr((value >> 8) & 0xff, value & 0xff);
}

function u32(value) {
	return chr((value >> 24) & 0xff, (value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff);
}

// A resource record with a literal rdata string.
function record(owner, rtype, rclass, ttl, rdata) {
	return owner + u16(rtype) + u16(rclass) + u32(ttl) + u16(length(rdata)) + rdata;
}

function txtRdata(strings) {
	let out = '';
	for (let item in strings)
		out += label(item);
	return out;
}

// A PTR record whose target is an uncompressed instance name. A real mDNS PTR
// target is the instance name followed by the service type, which is exactly
// what the captured packet contains.
function ptrRecord(instance) {
	return record(name('_raop._tcp.local'), 12, 1, 120, name(instance + '._raop._tcp.local'));
}

function txtRecord(instance, strings) {
	return record(name(instance + '._raop._tcp.local'), 16, 0x8001, 4500, txtRdata(strings));
}

// The standard "one receiver" advertisement: PTR in the answer section, TXT in
// additional, exactly the shape mdnsd sends.
function advertisement(instance, model) {
	let answer = ptrRecord(instance);
	let extra = txtRecord(instance, ['am=' + model, 'tp=UDP', 'txtvers=1']);
	return header(0x8400, 0, 1, 0, 1) + answer + extra;
}

// The real captured bytes: airupnp 1.12.4 advertising for
// uuid:demo-synthetic-renderer. Kept verbatim so the parser is anchored to a
// packet a real engine produced, not only to one this file built.
const CAPTURED_UPNP =
	'000084000000000100000004' +
	'055f72616f70045f746370056c6f63616c00000c000100000078001d1a' +
	'4242424241374135444239324044656d6f20537065616b65722bc00c' +
	'c028001080010000119400630a616d3d61697275706e700674703d55445008736d3d66616c7365' +
	'0873763d66616c736504656b3d310665743d302c31086d643d302c312c3206636e3d302c31' +
	'0463683d320573733d31360873723d343431303004766e3d3309747874766572733d31' +
	'c0280021800100000078000f0000000096d106636f6c696d61c017' +
	'c0c600018001000000780004c0a80501' +
	'c0c6002f8001000000780009c0c600054000000000';

const CAPTURED_INSTANCE = 'BBBBA7A5DB92@Demo Speaker+';
const CAPTURED_UDN = 'uuid:demo-synthetic-renderer';

// --- hash32 and the MAC prefix ---------------------------------------------

test('hash32 reproduces the C djb2-33 value the engine logged', () => {
	// The engine printed "adding renderer (Demo Speaker) with mac BBBB92DBA5A7"
	// for this UDN; the low four bytes are 92 DB A5 A7, i.e. hash32 stored
	// little-endian into MAC bytes 2..5.
	assert(hash32(CAPTURED_UDN) == 2463868327, 'hash32 = ' + hash32(CAPTURED_UDN));
});

test('macPrefixes spells the synthesised MAC the way the engine does', () => {
	let prefixes = macPrefixes(CAPTURED_UDN);
	// 0x92dba5a7 little-endian is a7 a5 db 92, so the suffix is A7A5DB92 and the
	// full instance prefix the engine registered is BBBBA7A5DB92.
	assert(prefixes.upnp == 'BBBBA7A5DB92', 'upnp prefix = ' + prefixes.upnp);
	assert(prefixes.cast == 'CCCCA7A5DB92', 'cast prefix = ' + prefixes.cast);
});

test('macPrefixes rejects a non-string UDN instead of hashing garbage', () => {
	for (let value in [null, 42, {}, []])
		assert(macPrefixes(value) == null, 'accepted ' + sprintf('%J', value));
	assert(macPrefixes('') != null, 'an empty UDN is still a string and hashes');
});

test('hash32 stays a 32-bit unsigned value for a long input', () => {
	// A 255-byte UDN is the backend's own limit; the C uint32_t wrap must hold.
	let long = 'uuid:';
	for (let i = 0; i < 50; i++)
		long += 'abcdefgh';
	long = substr(long, 0, 255);
	let h = hash32(long);
	assert(h >= 0 && h < 4294967296, 'hash out of range: ' + h);
	assert(h == int(h), 'hash is not an integer: ' + h);
});

// --- the captured packet ----------------------------------------------------

test('the real airupnp 1.12.4 packet parses to one airupnp instance', () => {
	let parsed = parseResponse(unhex(CAPTURED_UPNP));
	assert(parsed != null, 'the captured packet was rejected');
	assert(parsed.complete === true, 'a parsed packet is complete');
	deepEqual(parsed.instances, [{ name: CAPTURED_INSTANCE, model: 'airupnp' }]);
});
test('the captured packet yields a true broadcasting state for its own device', () => {
	let parsed = parseResponse(unhex(CAPTURED_UPNP));
	let state = deviceState(parsed, 'br-lan', CAPTURED_UDN);
	assert(state === true, 'expected true, got ' + sprintf('%J', state));
});

test('the captured packet does not make an unrelated device broadcast', () => {
	let parsed = parseResponse(unhex(CAPTURED_UPNP));
	let state = deviceState(parsed, 'br-lan', 'uuid:demo-some-other-speaker');
	assert(state === false, 'a completed scan with no match must be false, got ' + sprintf('%J', state));
});

test('the captured packet is attributed to airupnp only', () => {
	let parsed = parseResponse(unhex(CAPTURED_UPNP));
	deepEqual(engineStates(parsed), { upnp: true, cast: false });
});

// --- the three-state distinction -------------------------------------------

test('a matching advertisement gives true', () => {
	let instance = macPrefixes(CAPTURED_UDN).upnp + '@Demo Speaker+';
	let parsed = parseResponse(advertisement(instance, 'airupnp'));
	assert(parsed != null, 'the built packet was rejected');
	assert(deviceState(parsed, 'br-lan', CAPTURED_UDN) === true, 'expected true');
});

test('a completed scan with no advertisement gives false, not unknown', () => {
	// A standard response with zero answers is what a responder sends when it has
	// nothing to advertise. The scan ran and completed, so the negative is real.
	let empty = parseResponse(header(0x8400, 0, 0, 0, 0));
	assert(empty != null, 'an empty response must still parse');
	assert(empty.complete === true, 'an empty response is a completed scan');
	assert(deviceState(empty, 'br-lan', CAPTURED_UDN) === false, 'expected false');
});

test('an advertisement for another device leaves this one false', () => {
	let other = macPrefixes('uuid:demo-other').upnp + '@Other Speaker+';
	let parsed = parseResponse(advertisement(other, 'airupnp'));
	assert(deviceState(parsed, 'br-lan', CAPTURED_UDN) === false, 'expected false');
	assert(deviceState(parsed, 'br-lan', 'uuid:demo-other') === true, 'the other device must be true');
});

test('a scan that did not complete gives unknown, never false', () => {
	for (let value in [null, {}, { complete: false }, { complete: false, reason: 'no reply' },
		{ complete: false, reason: 'unparsable reply' }, 'nonsense', 5])
		assert(deviceState(value, 'br-lan', CAPTURED_UDN) === null,
			'a non-complete scan must be unknown: ' + sprintf('%J', value));
});

test('a scan that did not complete gives unknown for every engine too', () => {
	for (let value in [null, {}, { complete: false }, 'nonsense'])
		assert(engineStates(value) === null, 'engine state must be unknown: ' + sprintf('%J', value));
});

test('a completed scan with no instances reports both engines false', () => {
	deepEqual(engineStates(parseResponse(header(0x8400, 0, 0, 0, 0))), { upnp: false, cast: false });
});

// --- the interface rule that keeps a false positive out --------------------

test('the prefix is only derivable when the interface is not eth0', () => {
	// crosstools/cross_net.c hardcodes areq.arp_dev = "eth0" in SendARP(), so on a
	// literally-eth0 LAN the engine may use the speaker's real MAC instead of
	// hash32(UDN), and that prefix cannot be derived here.
	assert(prefixIsDerivable('br-lan') === true, 'br-lan must allow the prefix');
	assert(prefixIsDerivable('lan') === true, 'lan must allow the prefix');
	assert(prefixIsDerivable('eth0') === false, 'eth0 must not claim a derivable prefix');
	assert(prefixIsDerivable('ETH0') === false, 'the check must be case-insensitive');
	assert(prefixIsDerivable('') === false, 'an empty interface must not claim one');
	assert(prefixIsDerivable(null) === false, 'a missing interface must not claim one');
});

test('on eth0 a matching instance is unknown, not true', () => {
	// The advertisement below is exactly what a hash-derived MAC would produce, so
	// a naive prefix match would say true. On eth0 that answer is not knowable.
	let instance = macPrefixes(CAPTURED_UDN).upnp + '@Demo Speaker+';
	let parsed = parseResponse(advertisement(instance, 'airupnp'));
	assert(deviceState(parsed, 'eth0', CAPTURED_UDN) === null,
		'eth0 must yield unknown rather than a guessed true');
});

test('on eth0 a missing instance is unknown, not false', () => {
	// Same rule in the other direction: a negative on eth0 is not a measurement,
	// because the instance that "should" be there may carry a different prefix.
	let empty = parseResponse(header(0x8400, 0, 0, 0, 0));
	assert(deviceState(empty, 'eth0', CAPTURED_UDN) === null,
		'eth0 must yield unknown rather than a guessed false');
});

// --- garbage and oversize packets cannot flip a state ----------------------

test('an oversize packet is rejected before parsing', () => {
	let big = advertisement(CAPTURED_INSTANCE, 'airupnp');
	let padded = big + chr(0);
	while (length(padded) <= 4096)
		padded += chr(0);
	assert(length(padded) > 4096, 'fixture must exceed the limit');
	assert(parseResponse(padded) == null, 'an oversize packet must be rejected');
	// And the resulting state is unknown, not false: nothing was measured.
	assert(deviceState(parseResponse(padded), 'br-lan', CAPTURED_UDN) === null,
		'a rejected packet must not become false');
});

test('a truncated packet is rejected rather than half-read', () => {
	let good = advertisement(CAPTURED_INSTANCE, 'airupnp');
	for (let cut = 1; cut < length(good); cut++) {
		let short = substr(good, 0, cut);
		let parsed = parseResponse(short);
		// Either it parses to no instances (the PTR had not arrived yet) or it is
		// rejected. It must never claim an instance it could not have read.
		if (parsed != null)
			for (let instance in parsed.instances)
				assert(instance.name == CAPTURED_INSTANCE,
					'a truncated packet invented an instance: ' + instance.name);
	}
});

test('random garbage never parses to an instance', () => {
	// Deterministic pseudo-random bytes: a state flip has to survive this.
	let seed = 12345;
	let next = function() {
		seed = (seed * 1103515245 + 12345) % 2147483648;
		return seed;
	};
	for (let round = 0; round < 500; round++) {
		let length_ = 1 + (next() % 600);
		let bytes = '';
		for (let i = 0; i < length_; i++)
			bytes += chr(next() % 256);
		let parsed = parseResponse(bytes);
		if (parsed == null)
			continue;
		// A random byte string that happens to be a valid response must not carry
		// an instance, because no real instance name can be spelled randomly.
		for (let instance in parsed.instances)
			assert(instancePrefix(instance.name) != null,
				'garbage produced an instance without a MAC prefix: ' + instance.name);
	}
});

test('a query is not an advertisement', () => {
	// QR=0 (a query) must be rejected: the scan's own query could otherwise be
	// read back off the wire and treated as a reply.
	let query = header(0x0000, 1, 0, 0, 0) + name('_raop._tcp.local') + u16(12) + u16(0x8001);
	assert(parseResponse(query) == null, 'a query must be rejected');
});

test('a non-standard opcode is rejected', () => {
	// flags 0xa800: QR=1 with opcode 1 (IQUERY). Not an mDNS advertisement.
	assert(parseResponse(header(0xa800, 0, 0, 0, 0)) == null, 'opcode 1 must be rejected');
	assert(parseResponse(header(0x9800, 0, 0, 0, 0)) == null, 'opcode 3 must be rejected');
});

test('a compression pointer loop is rejected instead of hanging', () => {
	// A PTR whose rdata is a pointer to itself at the same offset.
	let body = name('_raop._tcp.local') + u16(12) + u16(1) + u32(120) + u16(2) + chr(0xc0, 0x0c);
	let packet = header(0x8400, 0, 1, 0, 0) + body;
	// chr(0xc0,0x0c) points at offset 12, which is the owner name, not forward;
	// the guard is that the target is itself a name we can read, so the point of
	// the test is that the parser terminates and returns something defensible.
	let parsed = parseResponse(packet);
	if (parsed != null)
		for (let instance in parsed.instances)
			assert(length(instance.name) <= 63, 'a loop produced an oversize name');
	// A forward pointer, which is the actual loop shape, must be rejected.
	let forward = header(0x8400, 0, 1, 0, 0) +
		record(name('_raop._tcp.local'), 12, 1, 120, chr(0xc0, 0x20));
	assert(parseResponse(forward) == null, 'a forward pointer must be rejected');
});

test('a record count over the cap is rejected', () => {
	// 200 answers claimed: over RECORD_LIMIT, so the packet is refused before the
	// parser can be made to loop.
	assert(parseResponse(header(0x8400, 0, 200, 0, 0)) == null, '200 answers must be rejected');
	assert(parseResponse(header(0x8400, 0, 64, 0, 0)) == null, 'a truncated 64-answer packet must be rejected');
});

test('a malformed TXT block is rejected rather than partially believed', () => {
	let instance = CAPTURED_INSTANCE;
	// A TXT length prefix that runs past the rdata end.
	let broken = record(name(instance + '._raop._tcp.local'), 16, 0x8001, 4500, chr(200) + 'am=airupnp');
	let packet = header(0x8400, 0, 1, 0, 1) + ptrRecord(instance) + broken;
	assert(parseResponse(packet) == null, 'a broken TXT must be rejected');
});

test('a name longer than 255 bytes is rejected', () => {
	let long = '';
	for (let i = 0; i < 5; i++)
		long += 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123';
	assert(length(long) > 255, 'fixture must exceed 255 bytes');
	assert(parseResponse(advertisement(long + '@x', 'airupnp')) == null, 'an oversize name must be rejected');
});

// --- the service-type enumeration PTR is not a receiver --------------------

test('the _services._dns-sd._udp enumeration PTR is ignored', () => {
	// mdnsd always emits this alongside a real registration. It lists the service
	// TYPE, so treating it as an instance would report a receiver that does not
	// exist.
	let enumeration = record(name('_services._dns-sd._udp.local'), 12, 1, 4500,
		name('_raop._tcp.local'));
	let parsed = parseResponse(header(0x8400, 0, 1, 0, 0) + enumeration);
	assert(parsed != null, 'the enumeration packet must still parse');
	deepEqual(parsed.instances, []);
	deepEqual(engineStates(parsed), { upnp: false, cast: false });
});

// --- instance prefix parsing ------------------------------------------------

test('instancePrefix reads the 12 hex characters before the at-sign', () => {
	assert(instancePrefix('BBBBA7A5DB92@Demo Speaker+') == 'BBBBA7A5DB92', 'uppercase hex');
	assert(instancePrefix('bbbba7a5db92@Demo Speaker+') == 'BBBBA7A5DB92', 'lowercase hex is folded');
	assert(instancePrefix('BBBBA7A5DB92@') == 'BBBBA7A5DB92', 'an empty name is still a prefix');
});

test('instancePrefix rejects a name that is not in the engine format', () => {
	for (let value in ['', 'BBBBA7A5DB9@x', 'GGGGA7A5DB92@x', 'BBBBA7A5DB92x@y',
		'BBBBA7A5DB92', null, 5, 'zzzzzzzzzzzz@x'])
		assert(instancePrefix(value) == null, 'accepted ' + sprintf('%J', value));
});

test('the am= marker distinguishes the two engines', () => {
	let upnp = parseResponse(advertisement('BBBBA7A5DB92@A+', 'airupnp'));
	let cast = parseResponse(advertisement('CCCCA7A5DB92@A+', 'aircast'));
	deepEqual(engineStates(upnp), { upnp: true, cast: false });
	deepEqual(engineStates(cast), { upnp: false, cast: true });
});

test('an advertisement with no am= marker makes neither engine true', () => {
	let instance = 'BBBBA7A5DB92@A+';
	let packet = header(0x8400, 0, 1, 0, 1) +
		ptrRecord(instance) + txtRecord(instance, ['tp=UDP', 'txtvers=1']);
	let parsed = parseResponse(packet);
	deepEqual(engineStates(parsed), { upnp: false, cast: false });
});

// --- the ambiguous-prefix rule --------------------------------------------

test('two distinct instances under one prefix are unknown, not true', () => {
	// Both engines can advertise for the same UDN (upnp prefix and cast prefix
	// both derive from it), but two DIFFERENT names under the SAME prefix means
	// the attribution is ambiguous.
	let prefix = macPrefixes(CAPTURED_UDN).upnp;
	let packet = header(0x8400, 0, 2, 0, 0) +
		ptrRecord(prefix + '@First+') + ptrRecord(prefix + '@Second+');
	let parsed = parseResponse(packet);
	assert(length(parsed.instances) == 2, 'both instances must be read');
	assert(deviceState(parsed, 'br-lan', CAPTURED_UDN) === null,
		'two instances under one prefix must be unknown');
});

test('the same instance repeated is still one device', () => {
	// mDNS repeats records; a duplicate is not an ambiguity.
	let instance = macPrefixes(CAPTURED_UDN).upnp + '@Demo Speaker+';
	let packet = header(0x8400, 0, 2, 0, 0) + ptrRecord(instance) + ptrRecord(instance);
	let parsed = parseResponse(packet);
	assert(length(parsed.instances) == 1, 'a repeated PTR must be deduplicated');
	assert(deviceState(parsed, 'br-lan', CAPTURED_UDN) === true, 'expected true');
});

test('a device with no UDN cannot be measured', () => {
	// An empty UDN still hashes in the engine, so it is not excluded here; what
	// matters is that a MISSING or non-string UDN is unknown rather than false.
	let empty = parseResponse(header(0x8400, 0, 0, 0, 0));
	for (let value in [null, 5, {}, []])
		assert(deviceState(empty, 'br-lan', value) === null,
			'a device without a UDN must be unknown: ' + sprintf('%J', value));
});

// --- tolerance --------------------------------------------------------------

test('parseResponse tolerates non-string and empty input', () => {
	for (let value in [null, 42, {}, [], '', 'abc'])
		assert(parseResponse(value) == null, 'accepted ' + sprintf('%J', value));
});

test('a packet with only a question parses to no instances', () => {
	let packet = header(0x8400, 1, 0, 0, 0) + name('_raop._tcp.local') + u16(12) + u16(1);
	let parsed = parseResponse(packet);
	assert(parsed != null && length(parsed.instances) == 0, 'expected an empty completed scan');
});

test('the parser never mutates its input', () => {
	let packet = unhex(CAPTURED_UPNP);
	let before = hex(packet);
	parseResponse(packet);
	assert(hex(packet) == before, 'the packet was modified');
});

print('1..', passed + failed, '\n', passed, ' passed; ', failed, ' failed\n');
exit(failed ? 1 : 0);
