// SPDX-License-Identifier: MIT
// Deliberately synthetic identities; no live device inventory belongs in tests.
//
// `const f = function () {}` plus a trailing `export { }` list, not
// `export function`: the ucode shipped by iStoreOS 25.12.5
// (libucode.so.20230711) rejects the latter, so a fixture written that way
// could not run on the target even though newer host interpreters accept it.

const defaults = function() {
	return {
		main: {
			enabled: false, interface: 'br-lan', airupnp: true, aircast: false,
			codec: 'flac', latency: '1000:2000', max_volume: 100,
			media_volume: 0.5, log_level: 'warn',
			// Upstream glMRConfig defaults: metadata/flush on, drift off, no
			// artwork, no content-length, UPnP search version 1, receiver kept.
			metadata: true, flush: true, drift: false, artwork: '',
			http_length: -1, upnp_max: 1, stop_receiver: false
		},
		devices: []
	};
};

const overrides = function() {
	return {
		main: {
			enabled: '1', aircast: '1', max_volume: '80', media_volume: '0.4',
			codec: 'aac:128', latency: '0:500',
			metadata: '0', flush: '0', drift: '1', artwork: 'https://example.com/demo.png',
			http_length: '-3', upnp_max: '3', stop_receiver: '1'
		},
		devices: [
			{
				section: 'device_demo_upnp', engine: 'upnp', udn: 'uuid:demo-upnp',
				name: 'Studio & <East> "One\'s"', enabled: '0', max_volume: '30',
				codec: 'flac:5', latency: '100:1000',
				metadata: '1', flush: '1', drift: '0', artwork: 'http://192.0.2.11/upnp-cover.png',
				http_length: '0'			},
			{
				engine: 'cast', udn: 'demo-cast', name: '演示音箱', media_volume: '0.25',
				codec: 'mp3:192', latency: '500:2000',
				metadata: '0', flush: '0', drift: '1', artwork: 'http://192.0.2.10:8080/demo.jpg',
				stop_receiver: '1'
			},
			{
				engine: 'upnp', udn: 'uuid:demo-inherited', name: '', max_volume: '',
				media_volume: '', codec: '', latency: '', metadata: '', flush: '',
				drift: '', artwork: '', http_length: '', stop_receiver: ''
			}
		]
	};
};

const defaultXml = function(engine) {
	let root = engine == 'upnp' ? 'airupnp' : 'aircast';
	let lines = [
		'<?xml version="1.0" encoding="UTF-8"?>', '<' + root + '>',
		'  <binding>br-lan</binding>', '  <main_log>warn</main_log>',
		'  <' + engine + '_log>warn</' + engine + '_log>', '  <util_log>warn</util_log>'
	];
	if (engine == 'upnp')
		push(lines, '  <raop_log>warn</raop_log>');
	push(lines, '  <common>', '    <enabled>1</enabled>', '    <codec>flac</codec>', '    <latency>1000:2000</latency>');
	push(lines, engine == 'upnp' ? '    <max_volume>100</max_volume>' : '    <media_volume>0.5</media_volume>');
	push(lines, '    <metadata>1</metadata>', '    <flush>1</flush>', '    <drift>0</drift>');
	if (engine == 'upnp')
		push(lines, '    <http_length>-1</http_length>', '    <upnp_max>1</upnp_max>');
	else
		push(lines, '    <stop_receiver>0</stop_receiver>');
	push(lines, '  </common>', '</' + root + '>');
	return join('\n', lines) + '\n';
};

export { defaults, overrides, defaultXml };
