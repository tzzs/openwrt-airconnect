// SPDX-License-Identifier: MIT
// Read-only UPnP AVTransport state parsing and polling.
import * as fs from 'fs';

const BODY_LIMIT = 16384;
const STATES = [
	'PLAYING', 'STOPPED', 'PAUSED_PLAYBACK', 'PAUSED_RECORDING',
	'TRANSITIONING', 'RECORDING', 'NO_MEDIA_PRESENT', 'CUSTOM'
];

function hasControl(value) {
	for (let i = 0; i < length(value); i++) {
		let c = ord(value, i);
		if (c == 0 || (c < 0x20 && c != 9 && c != 10 && c != 13) || c == 0x7f)
			return true;
	}
	return false;
}

const parseTransportInfo = function(xml) {
	if (type(xml) != 'string' || !length(xml) || length(xml) > BODY_LIMIT || hasControl(xml) ||
		index(xml, '<!') >= 0 || index(xml, '&') >= 0)
		return null;
	let open = '<CurrentTransportState>', close = '</CurrentTransportState>';
	let start = index(xml, open);
	if (start < 0 || index(substr(xml, start + length(open)), open) >= 0)
		return null;
	let valueStart = start + length(open);
	let end = index(substr(xml, valueStart), close);
	if (end < 0)
		return null;
	end += valueStart;
	if (index(substr(xml, end + length(close)), close) >= 0)
		return null;
	let state = trim(substr(xml, valueStart, end - valueStart));
	return index(STATES, state) >= 0 ? state : null;
};

const stateOf = function(state) {
	if (state == 'PLAYING') return true;
	if (state == 'STOPPED' || state == 'PAUSED_PLAYBACK' || state == 'NO_MEDIA_PRESENT') return false;
	return null;
};

function shellquote(value) {
	return "'" + replace(value, "'", "'\\''") + "'";
}

const validTarget = function(controlUrl, address, localAddress) {
	if (type(controlUrl) != 'string' || type(address) != 'string' ||
		type(localAddress) != 'string' || address == localAddress) return false;
	let addressParts = split(address, '.');
	if (length(addressParts) != 4) return false;
	for (let part in addressParts)
		if (!match(part, /^[0-9]{1,3}$/) || int(part, 10) > 255 ||
			(length(part) > 1 && substr(part, 0, 1) == '0')) return false;
	let a = int(addressParts[0], 10), b = int(addressParts[1], 10);
	if (!(a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168))) return false;
	let endpoint = match(controlUrl, /^http:\/\/([0-9.]+):([0-9]{1,5})(\/[A-Za-z0-9._~!$&'()*+,;=:@%/?-]+)$/);
	return endpoint && endpoint[1] == address && int(endpoint[2], 10) >= 1 && int(endpoint[2], 10) <= 65535;
};

const query = function(controlUrl, address, localAddress) {
	if (!validTarget(controlUrl, address, localAddress)) return null;
	let body = '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:GetTransportInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><InstanceID>0</InstanceID></u:GetTransportInfo></s:Body></s:Envelope>';
	let command = '/usr/bin/curl -q --silent --fail --globoff --noproxy ' + shellquote('*') +
		' --proto ' + shellquote('=http') + ' --max-redirs 0 --max-filesize ' + BODY_LIMIT +
		' --connect-timeout 1 --max-time 1 --interface ' + shellquote(localAddress) +
		' -H ' + shellquote('Content-Type: text/xml; charset="utf-8"') +
		' -H ' + shellquote('SOAPAction: "urn:schemas-upnp-org:service:AVTransport:1#GetTransportInfo"') +
		' --data ' + shellquote(body) + ' -- ' + shellquote(controlUrl) + ' 2>/dev/null';
	let proc = fs.popen(command, 'r');
	if (!proc) return null;
	let response = proc.read(BODY_LIMIT + 1), status = proc.close();
	return status == 0 && type(response) == 'string' && length(response) <= BODY_LIMIT
		? parseTransportInfo(response) : null;
};

export { parseTransportInfo, stateOf, validTarget, query };
