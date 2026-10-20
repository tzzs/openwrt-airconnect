// SPDX-License-Identifier: MIT
// Run: ucode tests/discovery/run.uc (imports resolve relative to this file).
import { parseSsdp, parseDescription, privateAddress, validateLocation, deduplicate, discover } from '../../packages/airconnect-manager/files/usr/share/airconnect-manager/discovery.uc';

let checks = 0;
function check(ok, name) { checks++; assert(ok, name); }
const peer = '192.168.20.10';
const url = 'http://192.168.20.10:1400/xml/device_description.xml';
const udn = 'uuid:test-renderer';
const target = 'urn:schemas-upnp-org:device:MediaRenderer:1';
function response(location, extra) {
	return 'HTTP/1.1 200 OK\r\nST: ' + target + '\r\nUSN: ' + udn + '::' + target + '\r\nLOCATION: ' + location + '\r\n' + (extra ?? '') + '\r\n';
}
function description(fields) {
	return '<?xml version="1.0"?><root xmlns="urn:schemas-upnp-org:device-1-0"><device><deviceType>' + target +
		'</deviceType><UDN>' + udn + '</UDN>' + (fields ?? '<friendlyName>Living &amp; Dining</friendlyName><modelName>Speaker 2</modelName><manufacturer>Example</manufacturer>') + '</device></root>';
}
let candidate = parseSsdp(response(url), peer);
check(candidate != null && candidate.udn == udn && candidate.address == peer, 'normal SSDP response');
check(parseSsdp(response(url), { address: peer }) != null, 'socket peer object');
check(parseSsdp(lc(response(url)), peer) == null, 'HTTP status and target stay strict');
check(parseSsdp(replace(response(url), 'LOCATION:', 'lOcAtIoN:'), peer) != null, 'case insensitive header name');
check(parseSsdp(response(url, 'LOCATION: ' + url + '\r\n'), peer) == null, 'duplicate location rejected');
check(parseSsdp(response(url, 'ST: ' + target + '\r\n'), peer) == null, 'duplicate target rejected');
check(parseSsdp(replace(response(url), 'ST:', ' ST:'), peer) == null, 'folded headers rejected');
check(parseSsdp(replace(response(url), '200 OK', '404 Missing'), peer) == null, 'non-success rejected');
check(parseSsdp(replace(response(url), 'USN: ' + udn, 'USN: other'), peer) == null, 'invalid USN rejected');
check(parseSsdp(replace(response(url), 'ST: ' + target, 'ST: upnp:rootdevice'), peer) == null, 'non renderer rejected');
check(parseSsdp(response(url) + sprintf('%09000d', 1), peer) == null, 'oversize datagram rejected');
check(parseSsdp(response(url) + chr(0), peer) == null, 'NUL rejected');

for (let bad in [
	'http://127.0.0.1/private', 'http://169.254.169.254/latest/meta-data/',
	'http://8.8.8.8/', 'http://192.168.20.11/', 'https://192.168.20.10/',
	'file:///etc/shadow', 'ftp://192.168.20.10/', 'http://localhost/',
	'http://192.168.20.10.evil.test/', 'http://192.168.20.10@evil.test/',
	'http://evil.test@192.168.20.10/', 'http://3232240650/', 'http://0xc0a8140a/',
	'http://192.168.020.10/', 'http://[::1]/', 'http://192.168.20.10:0/',
	'http://192.168.20.10:65536/', 'http://192.168.20.10:80:90/',
	'http://192.168.20.10/\r\nX: injected', 'http://192.168.20.10\\@evil.test/',
	'http://192.168.20.10/#fragment', 'http://192.168.20.10/{1,2}'
]) check(validateLocation(bad, peer) == null, 'unsafe LOCATION: ' + bad);
check(validateLocation('http://192.168.20.10', peer) != null, 'implicit port and path');
check(validateLocation("http://192.168.20.10/path?q=a'b&x=%20", peer) != null, 'quoted URL characters are data');
check(privateAddress('10.0.0.1') && privateAddress('172.16.1.1') && privateAddress('172.31.1.1'), 'private ranges');
for (let bad in ['172.15.0.1', '172.32.0.1', '127.0.0.1', '169.254.1.1', '224.0.0.1', '0.0.0.0', '192.168.1.256', '192.168.01.2', '1.2.3', ''])
	check(!privateAddress(bad), 'invalid or unsafe peer: ' + bad);

let normal = parseDescription(description(), candidate, 1234);
check(normal != null && normal.original_name == 'Living & Dining' && normal.last_seen == 1234, 'XML fields decoded');
check(normal.engine == 'upnp' && normal.online && normal.model == 'Speaker 2' && normal.manufacturer == 'Example', 'truthful device output');
check(parseDescription(chr(239, 187, 191) + description(), candidate, 1) != null, 'UTF8 BOM accepted');
check(parseDescription(replace(description(), target, 'urn:schemas-upnp-org:device:MediaRenderer:2'), candidate, 1) != null, 'newer MediaRenderer device version');
let missing = parseDescription(description(''), candidate, 1);
check(missing != null && missing.original_name == null && missing.model == null && missing.manufacturer == null, 'optional missing fields stay null');
check(parseDescription(replace(description(), '<UDN>' + udn + '</UDN>', ''), candidate, 1) == null, 'missing UDN rejected');
check(parseDescription(replace(description(), udn, 'uuid:other'), candidate, 1) == null, 'UDN must match SSDP');
check(parseDescription(replace(description(), target, 'urn:schemas-upnp-org:device:MediaServer:1'), candidate, 1) == null, 'description must be renderer');
let entities = parseDescription(description('<friendlyName>&lt;A&gt; &quot;B&quot; &apos;C&apos; &#65; &#x4e2d;</friendlyName>'), candidate, 1);
check(entities != null && entities.original_name == '<A> "B" \'C\' A 中', 'standard and numeric entities decoded once');
let double = parseDescription(description('<friendlyName>&amp;lt;</friendlyName>'), candidate, 1);
check(double != null && double.original_name == '&lt;', 'entity decoding is not recursive');

for (let xml in [
	'<!DOCTYPE root SYSTEM "file:///etc/shadow">' + description(),
	'<!DOCTYPE root [<!ENTITY x SYSTEM "http://169.254.169.254/">]>' + description(),
	description('<friendlyName>&unknown;</friendlyName>'),
	description('<friendlyName>bad & name</friendlyName>'),
	description('<friendlyName>&#0;</friendlyName>'),
	description('<friendlyName>&#xD800;</friendlyName>'),
	description('<friendlyName>&#1114112;</friendlyName>'),
	description('<friendlyName><b>Name</b></friendlyName>'),
	description('<friendlyName><![CDATA[Name]]></friendlyName>'),
	description('<friendlyName>One</friendlyName><friendlyName>Two</friendlyName>'),
	description('<friendlyName>' + sprintf('%0300d', 1) + '</friendlyName>'),
	replace(description(), '</device>', '</wrong>'),
	replace(description(), '</root>', ''),
	description() + '<root/>',
	'prefix' + description(),
	description() + 'tail',
	'<?evil command?>' + description(),
	'<?xml-stylesheet href="http://169.254.169.254/"?>' + description(),
	replace(description(), 'xmlns=', 'invalid-attribute '),
	description('<friendlyName>N' + chr(0) + '</friendlyName>'),
	sprintf('%066000d', 1)
]) check(parseDescription(xml, candidate, 1) == null, 'unsafe or malformed description');
let comment = replace(description(), '<device>', '<!-- safe comment --><device>');
check(parseDescription(comment, candidate, 1) != null, 'ordinary XML comments');
check(parseDescription(replace(description(), '<device>', '<!-- bad -- comment --><device>'), candidate, 1) == null, 'malformed XML comment');
let nested = replace(description(), '<device>', '<device><deviceList><device><deviceType>other</deviceType></device></deviceList>');
check(parseDescription(nested, candidate, 1) != null, 'embedded non renderer does not supply parent fields');
check(length(deduplicate([normal, normal, null, missing])) == 1, 'duplicate UDN collapsed');
let deep = description();
for (let i = 0; i < 40; i++) deep = replace(deep, '<device>', '<device><extra>');
check(parseDescription(deep, candidate, 1) == null, 'depth bounded');

// Regression: the control-byte scan must reject NUL/0x01/0x7f in the raw
// response and description, while a legitimate tab/LF inside an XML comment
// (which is skipped) is still accepted.
check(parseSsdp(response(url) + chr(0), peer) == null, 'NUL in SSDP response rejected');
check(parseSsdp(response(url) + chr(1), peer) == null, '0x01 in SSDP response rejected');
check(parseSsdp(response(url) + chr(127), peer) == null, '0x7f in SSDP response rejected');
check(parseDescription(description('<friendlyName>N' + chr(0) + '</friendlyName>'), candidate, 1) == null, 'NUL in description rejected');
check(parseDescription(description('<friendlyName>N' + chr(1) + '</friendlyName>'), candidate, 1) == null, '0x01 in description rejected');
check(parseDescription(description('<friendlyName>N' + chr(127) + '</friendlyName>'), candidate, 1) == null, '0x7f in description rejected');
let tabLfComment = replace(description(), '<device>', '<!--\tindented\nsecond line-->\t<device>');
check(parseDescription(tabLfComment, candidate, 1) != null, 'tab/LF inside XML comment accepted');

// The interface allowlist is config.uc's, re-checked here because this module is
// imported and called directly: a value discover() accepts but the backend
// rejects would only surface after the SSDP socket exists. The die() is caught
// and compared, since reaching the socket is not observable on a host.
function discoveredInterface(interfaceName) {
	try {
		discover('192.168.20.10', interfaceName);
		return 'accepted';
	}
	catch (error) {
		let message = error != null && error.message != null ? error.message : '';
		return message != 'Discovery requires a private IPv4 address and a valid network interface'
			? 'accepted' : 'rejected';
	}
}
for (let bad in ['eth0:1', '-bad', '.x', '.', '..', '', 'aaaaaaaaaaaaaaaa', 'br lan', 'eth0\n'])
	check(discoveredInterface(bad) == 'rejected', 'interface rejected: ' + sprintf('%J', bad));
for (let good in ['br-lan', 'wlan0', 'eth0.100', 'demo_01'])
	check(discoveredInterface(good) == 'accepted', 'interface accepted: ' + sprintf('%J', good));

// One summary, after every check above: printing the running total twice made
// CI report two different numbers.
printf('Discovery parser: %d checks passed\n', checks);
