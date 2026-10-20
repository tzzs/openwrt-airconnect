// SPDX-License-Identifier: MIT
// Deliberately synthetic identities; no live device inventory belongs in tests.

export function defaults() {
	return {
		main: {
			enabled: false, interface: 'br-lan', airupnp: true, aircast: false,
			codec: 'flac', latency: '1000:2000', max_volume: 100,
			media_volume: 0.5, log_level: 'warn'
		},
		devices: []
	};
}

export function overrides() {
	return {
		main: { enabled: '1', aircast: '1', max_volume: '80', media_volume: '0.4', codec: 'aac:128', latency: '0:500' },
		devices: [
			{ section: 'device_demo_upnp', engine: 'upnp', udn: 'uuid:demo-upnp', name: 'Studio & <East> "One\'s"', enabled: '0', max_volume: '30', codec: 'flac:5', latency: '100:1000' },
			{ engine: 'cast', udn: 'demo-cast', name: '演示音箱', media_volume: '0.25', codec: 'mp3:192', latency: '500:2000' },
			{ engine: 'upnp', udn: 'uuid:demo-inherited', name: '', max_volume: '', media_volume: '', codec: '', latency: '' }
		]
	};
}

export function defaultXml(engine) {
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
	push(lines, '  </common>', '</' + root + '>');
	return join('\n', lines) + '\n';
}
