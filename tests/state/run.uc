// SPDX-License-Identifier: MIT
// Host-side tests for state.uc, the pure shaping half of the rpcd backend.
// state.uc has no uci/ubus/filesystem dependency, so everything the plugin
// delegates to it is testable here; the plugin itself is syntax-checked by
// tests/state/check-plugin.sh.
//
// Run: ucode -L ~/.local/opt/ucode-host/lib/ucode tests/state/run.uc
import * as fs from 'fs';
import {
	mergeConfigured, buildStatus, freshCache, freshBroadcast, parsePsOutput, tailLines,
	clampErrors, actionSatisfied, stripControl
} from '../../packages/airconnect-manager/files/usr/share/airconnect-manager/state.uc';
import {
	ensureDir, writeAtomic, readTail, commandTail, readText, readJson, pathExists
} from '../../packages/airconnect-manager/files/usr/share/airconnect-manager/files.uc';

let passed = 0;
let failed = 0;

function assert(condition, message) {
	if (!condition)
		die(message || 'assertion failed');
}

function deepEqual(actual, expected, path) {
	path = path || 'value';
	assert(type(actual) == type(expected), path + ': type mismatch (' + type(actual) + ' vs ' + type(expected) + ')');
	if (type(actual) == 'array') {
		assert(length(actual) == length(expected), path + ': array size mismatch (' + length(actual) + ' vs ' + length(expected) + ')');
		for (let i = 0; i < length(expected); i++)
			deepEqual(actual[i], expected[i], path + '[' + i + ']');
	}
	else if (type(actual) == 'object') {
		assert(length(actual) == length(expected), path + ': object size mismatch (' + length(actual) + ' vs ' + length(expected) + ')');
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

function repeated(value, count) {
	let result = '';
	for (let i = 0; i < count; i++)
		result += value;
	return result;
}

// Synthetic identities only: uuid:demo-* and RFC 5737 addresses.
function discovered(engine, udn, extra) {
	let device = {
		engine: engine, udn: udn, original_name: 'Demo Speaker',
		model: 'Demo Model', manufacturer: 'Demo Manufacturer',
		address: '192.0.2.10', last_seen: 1700000000, online: true
	};
	for (let key in extra ?? {})
		device[key] = extra[key];
	return device;
}

function configured(engine, udn, extra) {
	let device = { engine: engine, udn: udn };
	for (let key in extra ?? {})
		device[key] = extra[key];
	return device;
}

function keysOf(devices) {
	let result = [];
	for (let device in devices)
		push(result, device.engine + '/' + device.udn);
	return result;
}

// --- mergeConfigured --------------------------------------------------------

test('a discovered device is kept with its facts and marked configured when UCI has it', () => {
	let merged = mergeConfigured([discovered('upnp', 'uuid:demo-upnp')], [configured('upnp', 'uuid:demo-upnp', { name: 'Living Room' })]);
	deepEqual(keysOf(merged), ['upnp/uuid:demo-upnp']);
	deepEqual(merged[0], {
		engine: 'upnp', udn: 'uuid:demo-upnp', original_name: 'Demo Speaker',
		name: 'Living Room', model: 'Demo Model', manufacturer: 'Demo Manufacturer',
		address: '192.0.2.10', last_seen: 1700000000, online: true, configured: true
	});
});

test('presence in the snapshot means online, whatever the entry claims', () => {
	// A discovered device is online by definition; a stale or hand-edited cache
	// entry must not be able to report it as offline while still being shown.
	let merged = mergeConfigured([discovered('upnp', 'uuid:demo-a', { online: false })], []);
	assert(merged[0].online === true, 'a device in a fresh snapshot must be online');
	let missing = mergeConfigured([{ engine: 'upnp', udn: 'uuid:demo-b', last_seen: 1700000000 }], []);
	assert(missing[0].online === true, 'a device without an online field must be online');
	assert(missing[0].last_seen == 1700000000, 'last_seen must still come from the entry');
});

test('a discovered device with no UCI section is reported as not configured', () => {
	let merged = mergeConfigured([discovered('cast', 'uuid:demo-cast')], []);
	assert(merged[0].configured === false, 'configured must be false');
	assert(merged[0].name === null, 'an unconfigured device must not carry an AirPlay name');
});

test('a configured device that was not discovered stays visible and offline', () => {
	let merged = mergeConfigured([], [configured('upnp', 'uuid:demo-offline', { name: 'Kitchen' })]);
	deepEqual(merged, [{
		engine: 'upnp', udn: 'uuid:demo-offline', original_name: null, name: 'Kitchen',
		model: null, manufacturer: null, address: null, last_seen: null,
		online: false, configured: true
	}]);
});

test('configured-only entries never invent a model, manufacturer, address or timestamp', () => {
	let merged = mergeConfigured([], [configured('cast', 'uuid:demo-quiet')]);
	for (let field in ['model', 'manufacturer', 'address', 'last_seen', 'original_name'])
		assert(merged[0][field] === null, field + ' must be null, got ' + sprintf('%J', merged[0][field]));
});

test('discovered devices come first, then the configured-only ones', () => {
	let merged = mergeConfigured(
		[discovered('upnp', 'uuid:demo-seen')],
		[configured('upnp', 'uuid:demo-unseen', { name: 'Unseen' }), configured('cast', 'uuid:demo-other')]
	);
	deepEqual(keysOf(merged), ['upnp/uuid:demo-seen', 'upnp/uuid:demo-unseen', 'cast/uuid:demo-other']);
});

test('dedupe is by engine plus UDN, not by UDN alone', () => {
	// The same UDN can legitimately appear once per engine; only exact pairs collapse.
	let merged = mergeConfigured(
		[discovered('upnp', 'uuid:demo-shared'), discovered('cast', 'uuid:demo-shared'), discovered('upnp', 'uuid:demo-shared')],
		[]
	);
	deepEqual(keysOf(merged), ['upnp/uuid:demo-shared', 'cast/uuid:demo-shared']);
});

test('a duplicate in the cache does not duplicate the configured device either', () => {
	let merged = mergeConfigured(
		[discovered('upnp', 'uuid:demo-dup'), discovered('upnp', 'uuid:demo-dup')],
		[configured('upnp', 'uuid:demo-dup', { name: 'Once' })]
	);
	deepEqual(keysOf(merged), ['upnp/uuid:demo-dup']);
	assert(merged[0].name == 'Once', 'the configured name was not applied');
});

test('the configured name overrides the cached one, and an empty name clears it', () => {
	let merged = mergeConfigured(
		[discovered('upnp', 'uuid:demo-name')],
		[configured('upnp', 'uuid:demo-name', { name: 'Override' })]
	);
	assert(merged[0].name == 'Override', 'configured name not applied');
	let cleared = mergeConfigured(
		[discovered('upnp', 'uuid:demo-name')],
		[configured('upnp', 'uuid:demo-name', { name: '' })]
	);
	assert(cleared[0].name === null, 'an empty UCI name must not become a string');
});

test('an invalid engine or UDN is dropped instead of reaching the reply', () => {
	let merged = mergeConfigured(
		[
			discovered('dlna', 'uuid:demo-bad-engine'),
			discovered('upnp', ''),
			discovered('upnp', null),
			discovered('upnp', 'uuid:demo-ok')
		],
		[configured('other', 'uuid:demo-bad'), configured('upnp', null)]
	);
	deepEqual(keysOf(merged), ['upnp/uuid:demo-ok']);
});

test('control bytes in a cached string are rejected rather than passed through', () => {
	let merged = mergeConfigured(
		[discovered('upnp', 'uuid:demo-ctl', { original_name: 'Bad' + chr(0) + 'Name', model: 'M' + chr(1) })],
		[]
	);
	assert(merged[0].original_name === null, 'a NUL in a name must not survive');
	assert(merged[0].model === null, 'a control byte in a model must not survive');
});

test('the device list is bounded to 64 entries', () => {
	let cached = [];
	for (let i = 0; i < 80; i++)
		push(cached, discovered('upnp', 'uuid:demo-cache-' + i));
	let configuredDevices = [];
	for (let i = 0; i < 80; i++)
		push(configuredDevices, configured('cast', 'uuid:demo-uci-' + i));
	let merged = mergeConfigured(cached, configuredDevices);
	assert(length(merged) == 64, 'expected 64 devices, got ' + length(merged));
	// The first 64 discovered devices win: the cache is what the user just asked for.
	assert(merged[0].udn == 'uuid:demo-cache-0', 'wrong first device');
	assert(merged[63].udn == 'uuid:demo-cache-63', 'wrong last device');
});

test('configured-only devices still fill the list when nothing was discovered', () => {
	let configuredDevices = [];
	for (let i = 0; i < 70; i++)
		push(configuredDevices, configured('upnp', 'uuid:demo-only-' + i, { name: 'Speaker ' + i }));
	let merged = mergeConfigured([], configuredDevices);
	assert(length(merged) == 64, 'expected 64 devices, got ' + length(merged));
	assert(merged[0].online === false && merged[0].configured === true, 'configured-only entry shape');
});

test('mergeConfigured tolerates a missing or malformed cache', () => {
	deepEqual(mergeConfigured(null, null), []);
	deepEqual(mergeConfigured('nonsense', []), []);
	deepEqual(mergeConfigured([null, 'x', 5], []), []);
});

// --- freshCache -------------------------------------------------------------

test('a cache inside 24 hours is current and reports its scan time', () => {
	let fresh = freshCache({ scanned_at: 1000000, devices: [discovered('upnp', 'uuid:demo-a')] }, 1000000 + 86399);
	assert(fresh.scanned_at == 1000000, 'scan time lost');
	assert(length(fresh.devices) == 1, 'devices lost');
});

test('a cache older than 24 hours is discarded, devices included', () => {
	deepEqual(freshCache({ scanned_at: 1000000, devices: [discovered('upnp', 'uuid:demo-a')] }, 1000000 + 86401),
		{ scanned_at: null, devices: [] });
});

test('a cache stamped in the future is discarded, a small clock step is tolerated', () => {
	assert(freshCache({ scanned_at: 1000000, devices: [] }, 1000000 + 299).scanned_at == 1000000, 'small skew rejected');
	assert(freshCache({ scanned_at: 1000000, devices: [] }, 1000000 - 301).scanned_at == null, 'future stamp accepted');
});

test('a missing, malformed or empty cache yields no scan time and no devices', () => {
	for (let value in [null, 'x', {}, { scanned_at: null, devices: [] }, { scanned_at: 0 }, { scanned_at: '1000' }])
		deepEqual(freshCache(value, 2000000), { scanned_at: null, devices: [] }, 'cache ' + sprintf('%J', value));
});

// --- buildStatus ------------------------------------------------------------

test('buildStatus reports enabled/interface from UCI and running from procd', () => {
	let status = buildStatus({
		uciMain: { enabled: '1', interface: 'br-lan', airupnp: '1', aircast: '0' },
		devices: [],
		cached: null,
		serviceState: { upnp: true, cast: false },
		conflicts: [],
		version: '0.1.0',
		now: 1700000000
	});
	deepEqual(status.services, {
		upnp: { enabled: true, running: true, broadcasting: null },
		cast: { enabled: false, running: false, broadcasting: null }
	});
	assert(status.enabled === true && status.interface == 'br-lan', 'main state not copied');
	assert(status.version == '0.1.0', 'version not copied');
	deepEqual(status.scan, { running: false, last_scan: null, error: null });
	deepEqual(status.devices, []);
	// No broadcast observation was supplied, so both new sections must report
	// unknown rather than a measured negative.
	deepEqual(status.broadcast, { observed_at: null, error: null });
	deepEqual(status.playback, { known: false, reason: 'no documented engine status API' });
});

test('an unknown service state stays null, never false', () => {
	let status = buildStatus({ uciMain: { enabled: '1', airupnp: '1', aircast: '1' }, serviceState: {} });
	assert(status.services.upnp.running === null, 'upnp must be unknown');
	assert(status.services.cast.running === null, 'cast must be unknown');
	assert(status.services.upnp.enabled === true, 'enabled comes from UCI and stays known');
});

test('disabled is false, and enabled only accepts the spellings config.uc accepts', () => {
	let status = buildStatus({ uciMain: { enabled: '0', airupnp: 0, aircast: false } });
	assert(status.enabled === false && status.services.upnp.enabled === false && status.services.cast.enabled === false,
		'a disabled value must be false');
	let on = buildStatus({ uciMain: { enabled: 1, airupnp: '1', aircast: true } });
	assert(on.enabled === true && on.services.upnp.enabled === true && on.services.cast.enabled === true,
		'accepted truthy spellings must be true');
	let odd = buildStatus({ uciMain: { enabled: 'yes', airupnp: 'on', aircast: 2 } });
	assert(odd.enabled === false && odd.services.upnp.enabled === false && odd.services.cast.enabled === false,
		'values the validator rejects must not be read as enabled');
});

test('devices merge the cache with configured UCI speakers', () => {
	let status = buildStatus({
		uciMain: { enabled: '1', airupnp: '1' },
		devices: [configured('upnp', 'uuid:demo-seen', { name: 'Seen' }), configured('upnp', 'uuid:demo-gone', { name: 'Gone' })],
		cached: { scanned_at: 1700000000, devices: [discovered('upnp', 'uuid:demo-seen')] },
		serviceState: { upnp: true, cast: false },
		now: 1700000100
	});
	deepEqual(keysOf(status.devices), ['upnp/uuid:demo-seen', 'upnp/uuid:demo-gone']);
	assert(status.devices[0].online === true && status.devices[0].configured === true, 'discovered+configured');
	assert(status.devices[1].online === false && status.devices[1].configured === true, 'configured but offline');
	assert(status.scan.last_scan == 1700000000, 'scan time not reported');
});

test('a stale cache contributes no devices and no last_scan', () => {
	let status = buildStatus({
		devices: [configured('upnp', 'uuid:demo-gone')],
		cached: { scanned_at: 1000000, devices: [discovered('upnp', 'uuid:demo-stale')] },
		now: 1000000 + 90000
	});
	deepEqual(keysOf(status.devices), ['upnp/uuid:demo-gone']);
	assert(status.scan.last_scan === null, 'a stale scan must not be reported as last_scan');
});

test('scan state is passed through: running flag, error and last scan', () => {
	let status = buildStatus({
		cached: { scanned_at: 1700000000, devices: [], error: 'Discovery timed out' },
		scanRunning: true,
		scanError: 'Discovery timed out',
		now: 1700000100
	});
	deepEqual(status.scan, { running: true, last_scan: 1700000000, error: 'Discovery timed out' });
});

test('conflicts are copied in order and non-strings are dropped', () => {
	let status = buildStatus({ conflicts: ["Legacy service 'airconnect' is running.", null, 5, 'Legacy binaries found in /usr/bin.'] });
	deepEqual(status.conflicts, ["Legacy service 'airconnect' is running.", 'Legacy binaries found in /usr/bin.']);
});

test('buildStatus tolerates empty input and still returns the full shape', () => {
	let status = buildStatus({});
	deepEqual(keys(status), ['enabled', 'interface', 'version', 'services', 'scan', 'playback',
		'broadcast', 'conflicts', 'devices']);
	assert(status.enabled === false && status.interface === null && status.version === null, 'empty state defaults');
	deepEqual(status.services, {
		upnp: { enabled: false, running: null, broadcasting: null },
		cast: { enabled: false, running: null, broadcasting: null }
	});
});

test('an invalid interface is reported as unknown rather than echoed back', () => {
	// status shows the interface as a fact, so it is held to config.uc's rule.
	for (let value in [repeated('a', 16), '-bad', '.x', '.', '..', 'has space', 'eth0\n', '', null])
		assert(buildStatus({ uciMain: { interface: value } }).interface === null,
			'an invalid interface was reported as valid: ' + sprintf('%J', value));
	for (let value in ['br-lan', 'eth0', 'wlan0.1', 'br_lan', 'x'])
		assert(buildStatus({ uciMain: { interface: value } }).interface === value,
			'a valid interface was rejected: ' + sprintf('%J', value));
});

// --- the four states stay separate ------------------------------------------
// service running / discovered / broadcasting / playing. Each is decided by its
// own source and none may be derived from another; in particular an engine that
// is running and a speaker that was discovered must not imply broadcasting, and
// broadcasting must never imply playback.

// A reduction standing in for broadcast.uc's deviceState/engineStates, injected
// so state.uc stays free of the mDNS module. `known` models a completed scan.
function fakeBroadcast(known, matches) {
	return {
		engine: function(observation) {
			if (!known || observation == null)
				return null;
			return { upnp: matches.upnp === true, cast: matches.cast === true };
		},
		device: function(observation, iface, udn) {
			if (!known || observation == null)
				return null;
			return matches[udn] === true ? true : false;
		}
	};
}

function observed(extra) {
	let result = { scanned_at: 1700000000, complete: true, instances: [] };
	for (let key in extra ?? {})
		result[key] = extra[key];
	return result;
}

test('a running engine and a discovered speaker do not imply broadcasting', () => {
	// The strongest temptation in this feature is to show "broadcasting" because
	// procd says the engine runs. Without an observation the answer must be null.
	let status = buildStatus({
		uciMain: { enabled: '1', interface: 'br-lan', airupnp: '1', aircast: '1' },
		serviceState: { upnp: true, cast: true },
		devices: [configured('upnp', 'uuid:demo-1')],
		cached: { scanned_at: 1700000000, devices: [discovered('upnp', 'uuid:demo-1')] },
		now: 1700000100
	});
	assert(status.services.upnp.running === true, 'the engine is running');
	assert(status.devices[0].online === true, 'the speaker was discovered');
	assert(status.services.upnp.broadcasting === null, 'broadcasting must stay unknown');
	assert(status.devices[0].broadcasting === null, 'per-device broadcasting must stay unknown');
});

test('broadcasting is reported from the observation, independently of running', () => {
	let reduce = fakeBroadcast(true, { upnp: true, cast: false, 'uuid:demo-1': true });
	let status = buildStatus({
		uciMain: { enabled: '1', interface: 'br-lan', airupnp: '1', aircast: '1' },
		serviceState: { upnp: false, cast: false },
		devices: [configured('upnp', 'uuid:demo-1')],
		broadcast: observed(),
		broadcastState: reduce.engine,
		broadcastDevice: reduce.device,
		now: 1700000100
	});
	// procd says stopped, the advertisement says otherwise. Both are reported as
	// measured; neither is corrected to match the other.
	assert(status.services.upnp.running === false, 'running stays what procd said');
	assert(status.services.upnp.broadcasting === true, 'broadcasting comes from the observation');
	assert(status.services.cast.broadcasting === false, 'a completed scan with no cast instance is false');
	assert(status.devices[0].broadcasting === true, 'the device matched');
	assert(status.broadcast.observed_at == 1700000000, 'the observation timestamp is reported');
});

test('a completed scan with no match is false, not unknown', () => {
	let reduce = fakeBroadcast(true, { upnp: false, cast: false });
	let status = buildStatus({
		uciMain: { enabled: '1', interface: 'br-lan', airupnp: '1' },
		devices: [configured('upnp', 'uuid:demo-1')],
		broadcast: observed(),
		broadcastState: reduce.engine,
		broadcastDevice: reduce.device,
		now: 1700000100
	});
	assert(status.services.upnp.broadcasting === false, 'expected a measured false');
	assert(status.devices[0].broadcasting === false, 'expected a measured false per device');
});

test('a failed scan is unknown, never false', () => {
	let reduce = fakeBroadcast(true, { upnp: false, cast: false });
	let status = buildStatus({
		uciMain: { enabled: '1', interface: 'br-lan', airupnp: '1' },
		devices: [configured('upnp', 'uuid:demo-1')],
		// complete:false is how the worker records a failure or a timeout.
		broadcast: { scanned_at: 1700000000, complete: false, reason: 'no reply' },
		broadcastState: reduce.engine,
		broadcastDevice: reduce.device,
		now: 1700000100
	});
	assert(status.services.upnp.broadcasting === null, 'a failed scan must be unknown');
	assert(status.devices[0].broadcasting === null, 'a failed scan must be unknown per device');
	assert(status.broadcast.observed_at == 1700000000, 'the attempt time is still reported');
	assert(status.broadcast.error == 'no reply', 'the failure reason is reported');
});

test('a stale broadcast observation expires to unknown', () => {
	let reduce = fakeBroadcast(true, { upnp: true, cast: false, 'uuid:demo-1': true });
	let fresh = buildStatus({
		uciMain: { enabled: '1', interface: 'br-lan', airupnp: '1' },
		devices: [configured('upnp', 'uuid:demo-1')],
		broadcast: observed(), broadcastState: reduce.engine, broadcastDevice: reduce.device,
		now: 1700000000 + 299
	});
	assert(fresh.services.upnp.broadcasting === true, '299 seconds is still current');
	let stale = buildStatus({
		uciMain: { enabled: '1', interface: 'br-lan', airupnp: '1' },
		devices: [configured('upnp', 'uuid:demo-1')],
		broadcast: observed(), broadcastState: reduce.engine, broadcastDevice: reduce.device,
		now: 1700000000 + 301
	});
	assert(stale.services.upnp.broadcasting === null, 'a stale observation must expire to unknown');
	assert(stale.devices[0].broadcasting === null, 'a stale observation must expire per device');
	assert(stale.broadcast.observed_at === null, 'an expired observation reports no timestamp');
});

test('a broadcast observation stamped in the future is discarded', () => {
	let reduce = fakeBroadcast(true, { upnp: true, cast: false });
	let status = buildStatus({
		uciMain: { enabled: '1', interface: 'br-lan', airupnp: '1' },
		broadcast: observed(), broadcastState: reduce.engine,
		now: 1700000000 - 61
	});
	assert(status.services.upnp.broadcasting === null, 'a future stamp must not be trusted');
});

test('broadcasting and playback never imply one another', () => {
	let reduce = fakeBroadcast(true, { upnp: true, cast: true });
	let broadcasting = buildStatus({
		uciMain: { enabled: '1', interface: 'br-lan', airupnp: '1', aircast: '1' },
		broadcast: observed(), broadcastState: reduce.engine,
		now: 1700000100
	});
	// Both engines advertise, yet playback stays a constant unknown: an
	// advertisement says a receiver exists, never that audio is flowing.
	assert(broadcasting.services.upnp.broadcasting === true, 'upnp broadcasts');
	assert(broadcasting.services.cast.broadcasting === true, 'cast broadcasts');
	deepEqual(broadcasting.playback, { known: false, reason: 'no documented engine status API' });
	// And the reverse: with no observation, playback is still the same constant,
	// so it is not derived from the broadcast section either.
	let quiet = buildStatus({ uciMain: { enabled: '1', airupnp: '1' } });
	deepEqual(quiet.playback, broadcasting.playback);
});

test('a device with an invalid UDN cannot become a broadcasting true', () => {
	let reduce = fakeBroadcast(true, { upnp: true, cast: false });
	let status = buildStatus({
		uciMain: { enabled: '1', interface: 'br-lan', airupnp: '1' },
		// Both are dropped by mergeConfigured, so neither can carry a state.
		devices: [configured('upnp', ''), configured('upnp', null)],
		broadcast: observed(), broadcastState: reduce.engine, broadcastDevice: reduce.device,
		now: 1700000100
	});
	deepEqual(status.devices, []);
});

test('freshBroadcast is the only place the age rule lives', () => {
	deepEqual(freshBroadcast(null, 1700000000),
		{ scanned_at: null, complete: false, reason: null, instances: [] });
	deepEqual(freshBroadcast({}, 1700000000),
		{ scanned_at: null, complete: false, reason: null, instances: [] });
	// A completed observation keeps its instances; an incomplete one carries none,
	// so a caller cannot accidentally reduce a failed scan to false.
	let complete = freshBroadcast({ scanned_at: 1700000000, complete: true, instances: [{ name: 'x' }] }, 1700000100);
	assert(complete.complete === true && length(complete.instances) == 1, 'a completed observation keeps its instances');
	let failed = freshBroadcast({ scanned_at: 1700000000, complete: false, reason: 'unparsable reply', instances: [{ name: 'x' }] }, 1700000100);
	assert(failed.complete === false && length(failed.instances) == 0, 'a failed scan must carry no instances');
	assert(failed.reason == 'unparsable reply', 'the reason is kept');
});

// --- parsePsOutput ----------------------------------------------------------

test('parsePsOutput finds a foreign engine and ignores our own pids', () => {
	let text = [
		'  PID USER       VSZ STAT COMMAND',
		' 1400 root      1580 S    airupnp -Z -x /var/etc/airconnect-manager/airupnp.xml',
		' 1401 root      1580 S    aircast -Z -x /var/etc/airconnect-manager/aircast.xml'
	];
	text = join('\n', text) + '\n';
	deepEqual(parsePsOutput(text, [1400]), [{ pid: 1401, name: 'aircast' }]);
	deepEqual(parsePsOutput(text, []), [{ pid: 1400, name: 'airupnp' }, { pid: 1401, name: 'aircast' }]);
});

test('parsePsOutput ignores unrelated processes and look-alike arguments', () => {
	let text = [
		' 2000 root      1300 S    /bin/sh /etc/init.d/airconnect-manager reload',
		' 2001 root      1000 S    grep airupnp',
		' 2002 root       900 S    logread -e airupnp',
		' 2003 root      1200 S    /usr/libexec/airconnect/airupnp -Z',
		' 2004 root      1100 S    tail -f /var/log/airconnect-manager.log'
	];
	text = join('\n', text) + '\n';
	// Only the real executable in the command column counts; a path is reduced to
	// its basename, and the init script or a log reader is not an engine.
	deepEqual(parsePsOutput(text, []), [{ pid: 2003, name: 'airupnp' }]);
});

test('parsePsOutput accepts the procps PID USER TIME COMMAND layout', () => {
	deepEqual(parsePsOutput(' 3000 root 0:01 airupnp -Z\n', []), [{ pid: 3000, name: 'airupnp' }]);
	deepEqual(parsePsOutput(' 3001 root 0:00 aircast -Z\n', []), [{ pid: 3001, name: 'aircast' }]);
	// A row without a user column cannot be attributed, so it is not reported.
	deepEqual(parsePsOutput('3002 aircast -Z\n', []), []);
});

test('parsePsOutput ignores the header, blank lines and malformed rows', () => {
	deepEqual(parsePsOutput('  PID USER VSZ STAT COMMAND\n\nnot-a-pid airupnp\n  abc airupnp\n', []), []);
});

test('parsePsOutput bounds what it reads', () => {
	let line = ' 4000 root 1580 S airupnp -Z\n';
	let huge = repeated(line, 4000);
	assert(length(huge) > 65536, 'fixture must exceed the cap');
	let found = parsePsOutput(huge, []);
	// Every surviving row is inside the 64 KiB prefix; nothing past it is parsed.
	assert(length(found) <= 3000, 'unexpected number of rows: ' + length(found));
	for (let entry in found)
		assert(entry.pid == 4000, 'unexpected pid parsed');
	deepEqual(parsePsOutput(huge, [4000]), []);
});

test('parsePsOutput tolerates non-string input and string pids', () => {
	deepEqual(parsePsOutput(null, []), []);
	deepEqual(parsePsOutput('', []), []);
	deepEqual(parsePsOutput(' 5000 root 100 S airupnp\n', ['5000']), []);
	deepEqual(parsePsOutput(' 5001 root 100 S airupnp\n', ['bogus', null, 0]), [{ pid: 5001, name: 'airupnp' }]);
});

// --- tailLines --------------------------------------------------------------

test('tailLines keeps the last lines in file order', () => {
	let text = 'one\ntwo\nthree\nfour\n';
	deepEqual(tailLines(text, 2, 65536), { lines: ['three', 'four'], truncated: true });
	deepEqual(tailLines(text, 10, 65536), { lines: ['one', 'two', 'three', 'four'], truncated: false });
});

test('tailLines strips CR and control bytes but keeps tabs', () => {
	let text = 'a\r\nb' + chr(0) + 'c\n' + 'd' + chr(1) + chr(127) + '\te\n';
	deepEqual(tailLines(text, 200, 65536).lines, ['a', 'bc', 'd\te']);
});

test('tailLines truncates an over-long line to 512 bytes and flags it', () => {
	let long = repeated('x', 900);
	let result = tailLines(long, 200, 65536);
	assert(length(result.lines) == 1, 'expected one line');
	assert(length(result.lines[0]) == 512, 'line was not capped: ' + length(result.lines[0]));
	assert(result.truncated === true, 'truncation must be reported');
});

test('tailLines respects the byte cap from the newest line backwards', () => {
	// Four 100-byte lines; a 250-byte cap fits two of them plus separators.
	let text = [];
	for (let i = 0; i < 4; i++)
		push(text, repeated(sprintf('%d', i), 100));
	let result = tailLines(join('\n', text), 200, 250);
	deepEqual(result.lines, [repeated('2', 100), repeated('3', 100)]);
	assert(result.truncated === true, 'dropping older lines must be reported');
});

test('tailLines reports truncation only when something was actually dropped', () => {
	deepEqual(tailLines('only\n', 200, 65536), { lines: ['only'], truncated: false });
	deepEqual(tailLines('', 200, 65536), { lines: [], truncated: false });
	deepEqual(tailLines(null, 200, 65536), { lines: [], truncated: false });
});

test('tailLines clamps a single line to the byte cap', () => {
	let result = tailLines(repeated('y', 600), 200, 100);
	assert(length(result.lines) == 1 && length(result.lines[0]) == 100, 'expected a 100-byte line');
	assert(result.truncated === true, 'clamping must be reported');
});

test('tailLines rejects nonsense caps without throwing', () => {
	deepEqual(tailLines('a\nb\n', 0, 65536), { lines: [], truncated: true });
	deepEqual(tailLines('a\nb\n', 200, 0), { lines: [], truncated: true });
	// A missing cap falls back to the documented default rather than crashing.
	assert(length(tailLines('a\nb\n', null, null).lines) == 2, 'default caps must apply');
});

test('tailLines never returns a line longer than 512 bytes even with a large cap', () => {
	let result = tailLines(repeated('z', 4096), 200, 65536);
	assert(length(result.lines[0]) == 512, 'line cap is independent of the byte cap');
});

// --- clampErrors ------------------------------------------------------------

test('clampErrors caps the count at 20', () => {
	let errors = [];
	for (let i = 0; i < 40; i++)
		push(errors, 'devices[' + i + '].max_volume: expected an integer in 1..100');
	let clamped = clampErrors(errors);
	assert(length(clamped) == 20, 'expected 20 errors, got ' + length(clamped));
	assert(clamped[0] == errors[0], 'the first error must be kept');
	assert(clamped[19] == errors[19], 'the twentieth error must be kept');
});

test('clampErrors caps each message at 512 bytes', () => {
	let clamped = clampErrors([repeated('e', 2000)]);
	assert(length(clamped) == 1, 'expected one error');
	assert(length(clamped[0]) == 512, 'message was not capped: ' + length(clamped[0]));
});

test('clampErrors keeps short messages verbatim and drops empty ones', () => {
	deepEqual(clampErrors(['main.codec: pcm is supported only by UPnP', '', null]), ['main.codec: pcm is supported only by UPnP']);
});

test('clampErrors accepts error objects and rejects non-arrays', () => {
	deepEqual(clampErrors([{ message: 'main.interface: expected a Linux interface token' }]),
		['main.interface: expected a Linux interface token']);
	deepEqual(clampErrors(null), []);
	deepEqual(clampErrors('one error'), []);
});

test('clampErrors does not mutate its input', () => {
	let errors = [repeated('e', 900), 'second'];
	let before = sprintf('%J', errors);
	clampErrors(errors);
	assert(sprintf('%J', errors) == before, 'input was modified');
});

// --- actionSatisfied --------------------------------------------------------

test('actionSatisfied checks the state procd reports, not the exit code', () => {
	let enabled = { enabled: '1', airupnp: '1', aircast: '0' };
	assert(actionSatisfied('start', { upnp: true, cast: false }, enabled) === true, 'started as configured');
	assert(actionSatisfied('start', { upnp: false, cast: false }, enabled) === false, 'start that did not start');
	assert(actionSatisfied('stop', { upnp: false, cast: false }, enabled) === true, 'stopped');
	assert(actionSatisfied('stop', { upnp: true, cast: false }, enabled) === false, 'stop that did not stop');
	assert(actionSatisfied('restart', { upnp: true, cast: false }, enabled) === true, 'restarted');
});

test('actionSatisfied expects nothing to run when the service is disabled', () => {
	assert(actionSatisfied('start', { upnp: false, cast: false }, { enabled: '0', airupnp: '1' }) === true,
		'a disabled service publishes no instance, so nothing running is correct');
	assert(actionSatisfied('start', { upnp: true, cast: false }, { enabled: '0', airupnp: '1' }) === false,
		'a disabled service must not have started an engine');
});

test('actionSatisfied expects only the selected engines', () => {
	let both = { enabled: '1', airupnp: '1', aircast: '1' };
	assert(actionSatisfied('start', { upnp: true, cast: true }, both) === true, 'both engines');
	assert(actionSatisfied('start', { upnp: true, cast: false }, both) === false, 'one engine missing');
	assert(actionSatisfied('start', { upnp: false, cast: true }, { enabled: '1', airupnp: '0', aircast: '1' }) === true,
		'cast only');
});

test('actionSatisfied returns null when the answer cannot be known', () => {
	assert(actionSatisfied('start', { upnp: null, cast: false }, { enabled: '1', airupnp: '1' }) === null, 'unknown upnp');
	assert(actionSatisfied('stop', { upnp: true, cast: null }, {}) === null, 'unknown cast');
	assert(actionSatisfied('start', {}, {}) === null, 'procd unavailable');
	assert(actionSatisfied('explode', { upnp: true, cast: false }, {}) === null, 'unsupported action');
});

// --- files.uc ---------------------------------------------------------------
// These use a real temporary directory: the seek, rename and mode logic is the
// part of the backend most likely to break silently, so it is exercised for
// real instead of being mocked.

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

let sandbox = null;
let previousSandbox = null;

function newDir() {
	if (previousSandbox != null)
		removeTree(previousSandbox);
	sandbox = fs.mkdtemp('/tmp/airconnect-state.XXXXXX');
	previousSandbox = sandbox;
	return sandbox;
}

test('writeAtomic writes the exact bytes with the requested mode', () => {
	let dir = newDir();
	let path = dir + '/out.json';
	assert(writeAtomic(path, '{"a":1}\n', 0640) === true, 'write failed');
	assert(fs.readfile(path) === '{"a":1}\n', 'bytes differ');
	assert(fs.stat(path).mode == 0640, 'mode is ' + sprintf('%o', fs.stat(path).mode));
});

test('writeAtomic replaces an existing file and leaves no temporary behind', () => {
	let dir = newDir();
	let path = dir + '/out.json';
	fs.writefile(path, 'previous content');
	assert(writeAtomic(path, 'new content', 0640) === true, 'write failed');
	assert(fs.readfile(path) === 'new content', 'file was not replaced');
	let leftovers = [];
	for (let name in fs.lsdir(dir) ?? [])
		if (substr(name, 0, 1) == '.')
			push(leftovers, name);
	deepEqual(leftovers, []);
});

test('writeAtomic reports failure instead of leaving a half-written file', () => {
	let dir = newDir();
	// A directory at the destination makes rename() fail; the old contents of the
	// destination cannot be touched because it was never opened for writing.
	let path = dir + '/blocked';
	fs.mkdir(path, 0750);
	assert(writeAtomic(path, 'data', 0640) === false, 'write into a directory must fail');
	assert(fs.stat(path).type == 'directory', 'the destination was replaced');
	let leftovers = [];
	for (let name in fs.lsdir(dir) ?? [])
		if (substr(name, 0, 1) == '.')
			push(leftovers, name);
	deepEqual(leftovers, [], 'a temporary file survived a failed write');
});

test('writeAtomic rejects non-string data and an empty path', () => {
	let dir = newDir();
	assert(writeAtomic(dir + '/x', null, 0640) === false, 'null data accepted');
	assert(writeAtomic('', 'x', 0640) === false, 'empty path accepted');
});

test('readTail reads the end of a file and seeks past the rest', () => {
	let dir = newDir();
	let path = dir + '/log';
	fs.writefile(path, 'old line\nnew line\n');
	// "new line\n" is exactly 9 bytes and starts on a line boundary, so the
	// budget lands cleanly and nothing is dropped from the text.
	deepEqual(readTail(path, 9), { text: 'new line\n', truncated: true });
});

test('readTail keeps a complete first line when the budget lands on its start', () => {
	let dir = newDir();
	let path = dir + '/log';
	fs.writefile(path, 'aaaa\nbbbb\n');
	deepEqual(readTail(path, 5), { text: 'bbbb\n', truncated: true });
});

test('readTail returns the whole file when it fits, without flagging truncation', () => {
	let dir = newDir();
	let path = dir + '/log';
	fs.writefile(path, 'one\ntwo\n');
	deepEqual(readTail(path, 65536), { text: 'one\ntwo\n', truncated: false });
});

test('readTail drops a partial first line when the budget cuts into it', () => {
	let dir = newDir();
	let path = dir + '/log';
	fs.writefile(path, 'aaaaaaaaaa\nbbbb\n');
	// A 10-byte budget lands inside the first line: only the second one survives.
	deepEqual(readTail(path, 10), { text: 'bbbb\n', truncated: true });
});

test('readTail returns nothing when the budget lands in the last line only', () => {
	let dir = newDir();
	let path = dir + '/log';
	fs.writefile(path, 'no newline here at all');
	deepEqual(readTail(path, 5), { text: '', truncated: true });
});

test('readTail tolerates a missing file, a directory and a bad budget', () => {
	let dir = newDir();
	deepEqual(readTail(dir + '/missing', 100), { text: '', truncated: false });
	deepEqual(readTail(dir, 100), { text: '', truncated: false });
	deepEqual(readTail(dir + '/missing', 0), { text: '', truncated: false });
	deepEqual(readTail(dir + '/missing', null), { text: '', truncated: false });
});

test('readTail never reads more than its budget', () => {
	let dir = newDir();
	let path = dir + '/big';
	fs.writefile(path, repeated('x', 5000) + '\nlast\n');
	let tail = readTail(path, 100);
	assert(length(tail.text) <= 100, 'read ' + length(tail.text) + ' bytes with a 100-byte budget');
});

test('readText and readJson refuse oversized files', () => {
	let dir = newDir();
	let path = dir + '/data.json';
	fs.writefile(path, '{"ok":true}');
	deepEqual(readJson(path, 1024), { ok: true });
	assert(readJson(path, 4) === null, 'an oversized file must not be parsed');
	assert(readText(path, 4) === null, 'an oversized file must not be read');
	assert(readText(dir + '/missing', 1024) === null, 'a missing file must be null');
});

test('readJson rejects unparsable and non-object JSON', () => {
	let dir = newDir();
	let path = dir + '/data.json';
	fs.writefile(path, '{bad');
	assert(readJson(path, 1024) === null, 'unparsable JSON accepted');
	fs.writefile(path, '[]');
	assert(readJson(path, 1024) === null, 'an array is not a cache object');
	fs.writefile(path, 'null');
	assert(readJson(path, 1024) === null, 'null accepted');
});

test('commandTail reads a fixed command with the same bounds', () => {
	let result = commandTail('/bin/echo hello', 65536);
	deepEqual(result, { text: 'hello\n', truncated: false });
	let bounded = commandTail('/bin/echo ' + repeated('z', 200), 20);
	assert(bounded.truncated === true, 'truncation not reported');
	assert(length(bounded.text) <= 20, 'command output exceeded the budget');
});

test('commandTail tolerates a failing command and a bad budget', () => {
	// A command that writes nothing is not an error; it simply yields no text.
	deepEqual(commandTail('/bin/true', 100), { text: '', truncated: false });
	deepEqual(commandTail('/bin/echo x', 0), { text: '', truncated: false });
	deepEqual(commandTail(null, 100), { text: '', truncated: false });
});

test('ensureDir creates each missing ancestor with mode 0750', () => {
	let dir = newDir();
	let nested = dir + '/a/b/c';
	assert(ensureDir(nested) === true, 'ensureDir failed');
	for (let path in [dir + '/a', dir + '/a/b', nested])
		assert(fs.stat(path) != null && fs.stat(path).type == 'directory', path + ' was not created');
	assert(fs.stat(nested).mode == 0750, 'leaf mode is ' + sprintf('%o', fs.stat(nested).mode));
});

test('ensureDir is idempotent and refuses a file in the way', () => {
	let dir = newDir();
	assert(ensureDir(dir) === true, 'an existing directory must succeed');
	assert(ensureDir(dir + '/x/y') === true, 'nested create failed');
	fs.writefile(dir + '/file', 'x');
	assert(ensureDir(dir + '/file') === false, 'a file must not be accepted as a directory');
	assert(ensureDir(dir + '/file/below') === false, 'a path below a file must fail');
});

test('pathExists does not follow a dangling symlink into a false negative', () => {
	let dir = newDir();
	fs.writefile(dir + '/real', 'x');
	assert(pathExists(dir + '/real') === true, 'a real file must exist');
	assert(pathExists(dir + '/missing') === false, 'a missing path must not exist');
	assert(pathExists('') === false, 'an empty path must not exist');
	assert(pathExists(null) === false, 'a null path must not exist');
});

if (previousSandbox != null) {
	removeTree(previousSandbox);
	previousSandbox = null;
}

// --- stripControl -----------------------------------------------------------

test('stripControl removes every control byte but keeps tabs', () => {
	// A CR is dropped here, unlike in a log line: this value is shown as one
	// string in the page, so a bare CR has no meaning to preserve.
	deepEqual(stripControl('a\tb\r\nc' + chr(0) + 'd' + chr(1) + chr(127) + 'e', 512), 'a\tbcde');
});

test('stripControl bounds the output and tolerates non-strings', () => {
	assert(length(stripControl(repeated('x', 2000), 100)) == 100, 'output not bounded');
	deepEqual(stripControl(null, 100), '');
	deepEqual(stripControl(42, 100), '');
	// A missing cap falls back to the documented line cap.
	assert(length(stripControl(repeated('y', 2000), null)) == 512, 'default cap not applied');
});

print('1..', passed + failed, '\n', passed, ' passed; ', failed, ' failed\n');
exit(failed ? 1 : 0);
