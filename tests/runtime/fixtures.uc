// SPDX-License-Identifier: MIT
// Synthetic fixtures only: RFC 5737 addresses and uuid:demo-* identities.
// No live device name, UDN or address belongs in a test fixture.

// A UCI-shaped main section as the uci cursor returns it: every value is a
// string and the metadata keys start with a dot.
const uciMain = function(overrides) {
	let main = {
		'.anonymous': false,
		'.type': 'main',
		'.name': 'main',
		enabled: '1',
		interface: 'br-lan',
		airupnp: '1',
		aircast: '1',
		codec: 'flac',
		latency: '1000:2000',
		max_volume: '100',
		media_volume: '0.5',
		log_level: 'warn',
		metadata: '1',
		artwork: 'https://example.com/demo.png',
		flush: '1',
		drift: '0',
		http_length: '-1',
		upnp_max: '1',
		stop_receiver: '0'
	};
	for (let key in overrides ?? {})
		main[key] = overrides[key];
	return main;
};

// One UPnP and one Cast device, mirroring the two-engine default configuration.
const uciDevices = function() {
	return [
		{
			'.anonymous': false,
			'.type': 'device',
			'.name': 'device_demo_upnp',
			engine: 'upnp',
			udn: 'uuid:demo-upnp',
			name: 'Demo UPnP Speaker',
			enabled: '1',
			max_volume: '60',
			codec: 'flac:5',
			latency: '100:1000'
		},
		{
			'.anonymous': false,
			'.type': 'device',
			'.name': 'device_demo_cast',
			engine: 'cast',
			udn: 'uuid:demo-cast',
			name: 'Demo Cast Speaker',
			enabled: '1',
			media_volume: '0.4',
			codec: 'mp3:192',
			latency: '500:2000'
		}
	];
};

// A cursor stand-in for the uci module. It records the calls it receives so the
// tests can assert that loadConfig asks for the documented names.
const fakeCursor = function(main, devices) {
	let calls = [];
	return {
		calls: calls,
		get_all: function(name, section) {
			push(calls, 'get_all ' + name + ' ' + section);
			return main ?? null;
		},
		foreach: function(name, type, callback) {
			push(calls, 'foreach ' + name + ' ' + type);
			for (let device in devices ?? []) {
				// The real cursor stops when the callback returns false.
				if (callback(device) === false)
					break;
			}
			return true;
		}
	};
};

// The raw (un-normalized) configuration matching uciMain()/uciDevices(), which
// is what loadConfig() is expected to produce.
const rawConfig = function(overrides) {
	return { main: uciMain(overrides), devices: uciDevices() };
};

// A configuration written before the advanced options existed: the shipped
// file from an older install simply lacks them. normalizeConfig must give the
// same effective settings as the current default file, which is the backwards
// compatibility promise for this change.
const legacyRawConfig = function() {
	let main = uciMain();
	for (let key in ['metadata', 'artwork', 'flush', 'drift', 'http_length', 'upnp_max', 'stop_receiver'])
		delete main[key];
	return { main: main, devices: [] };
};

const currentDefaultRawConfig = function() {
	// The shipped default file's advanced options, i.e. the upstream defaults.
	let main = uciMain({ artwork: '' });
	return { main: main, devices: [] };
};

// A normalized configuration with a PCM default for the UPnP engine only. This
// is the asymmetric-render fixture: renderXml(config, 'upnp') succeeds while
// renderXml(config, 'cast') throws, because Cast cannot use PCM and main.codec
// is the Cast default. Cast is disabled so normalizeConfig accepts the object.
const pcmUpnpOnly = function() {
	return {
		main: {
			enabled: true, interface: 'br-lan', airupnp: true, aircast: false,
			codec: 'pcm', latency: '1000:2000', max_volume: 100,
			media_volume: 0.5, log_level: 'warn',
			metadata: true, flush: true, drift: false, artwork: '',
			http_length: -1, upnp_max: 1, stop_receiver: false
		},
		devices: [
			{
				engine: 'upnp', udn: 'uuid:demo-upnp', enabled: true, name: 'Demo UPnP Speaker',
				max_volume: 60, media_volume: 0.5, codec: 'pcm', latency: '100:1000',
				metadata: true, flush: true, drift: false, artwork: '', http_length: -1,
				stop_receiver: false
			},
			{
				engine: 'cast', udn: 'uuid:demo-cast', enabled: true, name: 'Demo Cast Speaker',
				max_volume: 100, media_volume: 0.4, codec: 'flac', latency: '500:2000',
				metadata: true, flush: true, drift: false, artwork: '', http_length: -1,
				stop_receiver: false
			}
		]
	};
};

// A previously written, still valid runtime file. "keep last good" is only
// provable against bytes that exist before the failing apply runs.
const previousXml = function(engine) {
	return '<?xml version="1.0" encoding="UTF-8"?>\n<' + (engine == 'upnp' ? 'airupnp' : 'aircast') +
		'>\n  <binding>previous-good</binding>\n</' + (engine == 'upnp' ? 'airupnp' : 'aircast') + '>\n';
};

export { uciMain, uciDevices, fakeCursor, rawConfig, legacyRawConfig, currentDefaultRawConfig, pcmUpnpOnly, previousXml };
