// SPDX-License-Identifier: MIT
// Run from any working directory; imports are relative to this file.
import { normalizeConfig, renderXml } from '../../packages/airconnect-manager/files/usr/share/airconnect-manager/config.uc';
import { defaults, overrides, defaultXml } from './fixtures.uc';

let passed = 0;
let failed = 0;

function assert(condition, message) {
	if (!condition)
		die(message || 'assertion failed');
}

function deepEqual(actual, expected, path) {
	path = path || 'value';
	assert(type(actual) == type(expected), path + ': type mismatch');
	if (type(actual) == 'array') {
		assert(length(actual) == length(expected), path + ': array size mismatch');
		for (let i = 0; i < length(expected); i++)
			deepEqual(actual[i], expected[i], path + '[' + i + ']');
	}
	else if (type(actual) == 'object') {
		assert(length(actual) == length(expected), path + ': object size mismatch');
		for (let key in keys(expected)) {
			assert(exists(actual, key), path + '.' + key + ': missing key');
			deepEqual(actual[key], expected[key], path + '.' + key);
		}
	}
	else
		assert(actual === expected, path + ': unexpected value');
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

function rejects(label, callback, path) {
	test(label, () => {
		let error_message = null;
		try { callback(); }
		catch (error) { error_message = error.message; }
		assert(type(error_message) == 'string', 'expected validation error');
		assert(index(error_message, path + ':') == 0, 'missing field path: ' + error_message);
	});
}

function mainConfig(key, value) {
	let main = {};
	main[key] = value;
	return { main: main };
}

function deviceConfig(key, value) {
	let device = { engine: 'upnp', udn: 'uuid:demo-validation' };
	device[key] = value;
	return { devices: [device] };
}

function repeated(value, count) {
	let result = '';
	for (let i = 0; i < count; i++) result += value;
	return result;
}

test('empty config gets complete typed defaults', () => deepEqual(normalizeConfig({}), defaults()));
test('normalization is idempotent', () => {
	let config = normalizeConfig(overrides());
	deepEqual(normalizeConfig(config), config);
});
test('does not mutate input or share mutable state', () => {
	let source = overrides();
	let before = sprintf('%J', source);
	let result = normalizeConfig(source);
	result.main.max_volume = 1;
	result.devices[0].name = 'Changed';
	assert(sprintf('%J', source) == before, 'input was mutated');
	deepEqual(normalizeConfig({}), defaults());
});
test('unknown UCI metadata ignored', () => {
	deepEqual(normalizeConfig({ '.name': 'ignored', main: { '.type': 'main', future: {} }, devices: [] }), defaults());
});
test('overrides and empty-value inheritance are engine independent', () => {
	let value = normalizeConfig(overrides());
	assert(value.main.enabled === true && value.main.aircast === true);
	assert(value.devices[0].enabled === false && value.devices[0].max_volume === 30);
	assert(value.devices[0].codec == 'flac:5' && value.devices[0].latency == '100:1000');
	assert(value.devices[0].section == 'device_demo_upnp');
	assert(value.devices[1].media_volume === 0.25);
	assert(value.devices[2].enabled === true && value.devices[2].name === '');
	assert(value.devices[2].max_volume === 80 && value.devices[2].media_volume === 0.4);
	assert(value.devices[2].codec == 'aac:128' && value.devices[2].latency == '0:500');
});

for (let value in [null, [], 'bad', 1, true])
	rejects('reject root ' + sprintf('%J', value), () => normalizeConfig(value), 'config');
for (let value in [null, [], 'bad', 1, false])
	rejects('reject main ' + sprintf('%J', value), () => normalizeConfig({ main: value }), 'main');
for (let value in [null, {}, 'bad', 1, false])
	rejects('reject devices ' + sprintf('%J', value), () => normalizeConfig({ devices: value }), 'devices');
for (let value in [null, [], 'bad', 1, false])
	rejects('reject device entry ' + sprintf('%J', value), () => normalizeConfig({ devices: [value] }), 'devices[0]');

for (let key in ['enabled', 'airupnp', 'aircast']) {
	for (let value in ['0', '1', 0, 1, false, true])
		test('accept main boolean ' + key + '=' + sprintf('%J', value), () => {
			let result = normalizeConfig(mainConfig(key, value));
			assert(type(result.main[key]) == 'bool');
			assert(result.main[key] === (value === '1' || value === 1 || value === true));
		});
	for (let value in ['false', 'true', '', 'yes', '01', ' 1', '1\n', 2, -1, [], {}, null])
		rejects('reject main boolean ' + key + '=' + sprintf('%J', value), () => normalizeConfig(mainConfig(key, value)), 'main.' + key);
}
for (let value in ['0', '1', 0, 1, false, true])
	test('accept device boolean ' + sprintf('%J', value), () => assert(type(normalizeConfig(deviceConfig('enabled', value)).devices[0].enabled) == 'bool'));
for (let value in ['false', 'true', '', null, [], {}, 2])
	rejects('reject device boolean ' + sprintf('%J', value), () => normalizeConfig(deviceConfig('enabled', value)), 'devices[0].enabled');

for (let value in ['br-lan', 'eth0.100', 'wlan0', 'demo_01', repeated('a', 15)])
	test('accept interface ' + value, () => assert(normalizeConfig(mainConfig('interface', value)).main.interface == value));
for (let value in ['', '.', '..', '-bad', 'br lan', 'br-lan;id', '$(id)', 'eth0/1', 'eth0:1', 'eth0\n', '音箱', repeated('a', 16), null, []])
	rejects('reject interface ' + sprintf('%J', value), () => normalizeConfig(mainConfig('interface', value)), 'main.interface');

for (let value in [1, 100, '1', '100', '30'])
	test('accept UPnP volume ' + sprintf('%J', value), () => assert(normalizeConfig(mainConfig('max_volume', value)).main.max_volume == +value));
for (let value in [0, 101, -1, 1.5, '1.0', '01', '30x', '30;id', ' 30', '', null, true, [], {}, '1e2', 'NaN', 'Infinity']) {
	rejects('reject main UPnP volume ' + sprintf('%J', value), () => normalizeConfig(mainConfig('max_volume', value)), 'main.max_volume');
	if (value !== '')
		rejects('reject device UPnP volume ' + sprintf('%J', value), () => normalizeConfig(deviceConfig('max_volume', value)), 'devices[0].max_volume');
}
for (let value in [0, 1, 0.25, '0', '1', '0.125', '1.000'])
	test('accept Cast volume ' + sprintf('%J', value), () => assert(normalizeConfig(mainConfig('media_volume', value)).main.media_volume == +value));
for (let value in [-0.1, 1.1, '0.5foo', '.5', '01', '1e0', '+0.5', '0x1', ' 0.5', '0.5 ', '', null, true, [], {}, 'NaN', 'Infinity', '0.5;id']) {
	rejects('reject main Cast volume ' + sprintf('%J', value), () => normalizeConfig(mainConfig('media_volume', value)), 'main.media_volume');
	if (value !== '')
		rejects('reject device Cast volume ' + sprintf('%J', value), () => normalizeConfig(deviceConfig('media_volume', value)), 'devices[0].media_volume');
}
for (let key in ['max_volume', 'media_volume']) {
	for (let value in [+'NaN', +'Infinity', -('1e999' + 0)])
		rejects('reject nonfinite ' + key + ' ' + value, () => normalizeConfig(mainConfig(key, value)), 'main.' + key);
}

for (let value in ['wav', 'pcm', 'flac', 'flac:0', 'flac:9', 'mp3', 'mp3:32', 'mp3:192', 'mp3:320', 'aac', 'aac:16', 'aac:128', 'aac:320'])
	test('accept codec ' + value, () => assert(normalizeConfig(mainConfig('codec', value)).main.codec == value));
for (let value in ['', 'FLAC', 'flac:10', 'flac:-1', 'flac:5/4096', 'mp3:31', 'mp3:321', 'mp3:0192', 'mp3:192.0', 'aac:15', 'aac:321', 'aac:0', 'aac:128 -Z', 'flac;id', '$(id)', 'wav\n', null, []]) {
	rejects('reject main codec ' + sprintf('%J', value), () => normalizeConfig(mainConfig('codec', value)), 'main.codec');
	if (value !== '')
		rejects('reject device codec ' + sprintf('%J', value), () => normalizeConfig(deviceConfig('codec', value)), 'devices[0].codec');
}
rejects('Cast enabled cannot inherit PCM common', () => normalizeConfig({ main: { aircast: '1', codec: 'pcm' } }), 'main.codec');
rejects('Cast device cannot use PCM override', () => normalizeConfig({ devices: [{ engine: 'cast', udn: 'demo', codec: 'pcm' }] }), 'devices[0].codec');
rejects('Cast render cannot emit PCM default even with Cast disabled', () => renderXml(normalizeConfig({ main: { codec: 'pcm' } }), 'cast'), 'main.codec');

for (let value in ['0:0', '1000:2000', '10000:10000', '0:10000'])
	test('accept latency ' + value, () => assert(normalizeConfig(mainConfig('latency', value)).main.latency == value));
for (let value in ['', '1000', ':2000', '1000:', '01:2', '0:0:f', '-1:0', '0:10001', '10001:0', '0.5:1', 'NaN:1', 'Infinity:1', '0:0;id', '0:0\n', ' 0:0', null, 1000, []]) {
	rejects('reject main latency ' + sprintf('%J', value), () => normalizeConfig(mainConfig('latency', value)), 'main.latency');
	if (value !== '')
		rejects('reject device latency ' + sprintf('%J', value), () => normalizeConfig(deviceConfig('latency', value)), 'devices[0].latency');
}
for (let value in ['error', 'warn', 'info', 'debug'])
	test('accept log level ' + value, () => assert(normalizeConfig(mainConfig('log_level', value)).main.log_level == value));
for (let value in ['', 'WARN', 'trace', 'warn;id', null, []])
	rejects('reject log level ' + sprintf('%J', value), () => normalizeConfig(mainConfig('log_level', value)), 'main.log_level');

for (let value in ['', 'dlna', 'airupnp', null, 1])
	rejects('reject device engine ' + sprintf('%J', value), () => normalizeConfig(deviceConfig('engine', value)), 'devices[0].engine');
for (let value in ['', ' ', '　', null, 1, [], repeated('u', 256)])
	rejects('reject UDN ' + sprintf('%J', value), () => normalizeConfig(deviceConfig('udn', value)), 'devices[0].udn');
test('UDN accepts 255-byte boundary', () => assert(length(normalizeConfig(deviceConfig('udn', repeated('u', 255))).devices[0].udn) == 255));
rejects('duplicate same engine UDN rejected', () => normalizeConfig({ devices: [{ engine: 'upnp', udn: 'same-demo' }, { engine: 'upnp', udn: 'same-demo' }] }), 'devices[1].udn');
test('same UDN in separate engines is independent', () => assert(length(normalizeConfig({ devices: [{ engine: 'upnp', udn: 'same-demo' }, { engine: 'cast', udn: 'same-demo' }] }).devices) == 2));
test('UDN object-key-like strings remain valid', () => assert(length(normalizeConfig({ devices: [{ engine: 'upnp', udn: '__proto__' }, { engine: 'upnp', udn: 'constructor' }] }).devices) == 2));
for (let value in ['', 'Demo', '演示音箱', repeated('a', 63), repeated('中', 21), repeated('🎵', 15) + 'abc'])
	test('accept name bytes=' + length(value), () => assert(normalizeConfig(deviceConfig('name', value)).devices[0].name == value));
for (let value in [' ', '　', ' ', repeated('a', 64), repeated('中', 22), repeated('🎵', 16), null, [], 1])
	rejects('reject name ' + sprintf('%J', value), () => normalizeConfig(deviceConfig('name', value)), 'devices[0].name');
for (let key in ['name', 'udn']) {
	for (let value in ['a' + chr(0) + 'b', 'a\nb', 'a\tb', 'a\rb', 'a' + chr(31), 'a' + chr(127), 'a' + chr(0xc2, 0x85), chr(0xff), chr(0xc0, 0xaf), chr(0xe2, 0x82), chr(0xed, 0xa0, 0x80), chr(0xf4, 0x90, 0x80, 0x80), chr(0xef, 0xbf, 0xbe)])
		rejects('reject invalid/control ' + key + ' hex=' + hexenc(value), () => normalizeConfig(deviceConfig(key, value)), 'devices[0].' + key);
}
rejects('section metadata must be string', () => normalizeConfig(deviceConfig('section', {})), 'devices[0].section');

for (let engine in ['upnp', 'cast'])
	test('exact default XML for ' + engine, () => assert(renderXml(normalizeConfig({}), engine) == defaultXml(engine), 'XML does not match fixture'));
test('XML escapes all five metacharacters in name and UDN', () => {
	let source = deviceConfig('name', 'A & <B> "C\'s"');
	source.devices[0].udn = 'uuid:demo&<"\'>';
	let xml = renderXml(normalizeConfig(source), 'upnp');
	assert(index(xml, '<name>A &amp; &lt;B&gt; &quot;C&apos;s&quot;</name>') >= 0);
	assert(index(xml, '<udn>uuid:demo&amp;&lt;&quot;&apos;&gt;</udn>') >= 0);
});
test('XML separates engine volumes and device identities', () => {
	let value = normalizeConfig(overrides());
	let upnp = renderXml(value, 'upnp');
	let cast = renderXml(value, 'cast');
	assert(index(upnp, '<max_volume>30</max_volume>') >= 0 && index(upnp, '<media_volume>') < 0);
	assert(index(cast, '<media_volume>0.25</media_volume>') >= 0 && index(cast, '<max_volume>') < 0);
	assert(index(upnp, '<udn>demo-cast</udn>') < 0 && index(cast, '<udn>uuid:demo-upnp</udn>') < 0);
	assert(index(upnp, '<enabled>0</enabled>') >= 0 && index(upnp, '<codec>flac:5</codec>') >= 0);
	assert(index(cast, '<name>演示音箱</name>') >= 0);
});
test('empty device name omits XML override', () => {
	let xml = renderXml(normalizeConfig(deviceConfig('name', '')), 'upnp');
	assert(index(xml, '<name>') < 0 && index(xml, '<device>') >= 0);
});
test('master off does not disable discovered devices in XML', () => {
	let xml = renderXml(normalizeConfig({ main: { enabled: '0' } }), 'upnp');
	assert(index(xml, '<enabled>1</enabled>') >= 0);
});
rejects('renderer revalidates name limits', () => renderXml(deviceConfig('name', repeated('x', 64)), 'upnp'), 'devices[0].name');
for (let value in ['', 'airupnp', 'upnp;id', null])
	rejects('reject render engine ' + sprintf('%J', value), () => renderXml(defaults(), value), 'engine');

// Regression: anchored patterns must reject trailing whitespace/control bytes,
// because ucode's `$` also matches before a trailing newline. interface is a
// main-only field, so its trailing-byte cases are not repeated per device.
for (let key in ['interface']) {
	for (let suffix in ['\n', '\r', '\t', '\n\n']) {
		let value = 'eth0' + suffix;
		rejects('reject main ' + key + ' trailing ' + hexenc(suffix), () => normalizeConfig(mainConfig(key, value)), 'main.' + key);
	}
}
for (let key in ['latency', 'codec']) {
	for (let suffix in ['\n', '\r', '\t', '\n\n']) {
		let value = '0:0' + suffix;
		if (key == 'codec') value = 'flac:1' + suffix;
		rejects('reject main ' + key + ' trailing ' + hexenc(suffix), () => normalizeConfig(mainConfig(key, value)), 'main.' + key);
		rejects('reject device ' + key + ' trailing ' + hexenc(suffix), () => normalizeConfig(deviceConfig(key, value)), 'devices[0].' + key);
	}
}
for (let key in ['max_volume', 'media_volume']) {
	for (let suffix in ['\n', '\r', '\t', '\n\n']) {
		let value = '100' + suffix;
		if (key == 'media_volume') value = '1' + suffix;
		rejects('reject main ' + key + ' trailing ' + hexenc(suffix), () => normalizeConfig(mainConfig(key, value)), 'main.' + key);
		rejects('reject device ' + key + ' trailing ' + hexenc(suffix), () => normalizeConfig(deviceConfig(key, value)), 'devices[0].' + key);
	}
}

print('1..', passed + failed, '\n', passed, ' passed; ', failed, ' failed\n');
exit(failed ? 1 : 0);
