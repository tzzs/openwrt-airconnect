// SPDX-License-Identifier: MIT
// Run: ucode tests/playback/run.uc
import { parseTransportInfo, stateOf, validTarget, query } from '../../packages/airconnect-manager/files/usr/share/airconnect-manager/playback.uc';

let checks = 0;
function check(value, name) { checks++; assert(value, name); }
function response(state) {
	return '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:GetTransportInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><CurrentTransportState>' + state + '</CurrentTransportState><CurrentTransportStatus>OK</CurrentTransportStatus><CurrentSpeed>1</CurrentSpeed></u:GetTransportInfoResponse></s:Body></s:Envelope>';
}

check(parseTransportInfo(response('PLAYING')) == 'PLAYING', 'playing response parsed');
check(parseTransportInfo('<html>PLAYING</html>') == null, 'state text outside SOAP field rejected');
check(parseTransportInfo('<CurrentTransportState>PLAYING</CurrentTransportState><CurrentTransportState>STOPPED</CurrentTransportState>') == null, 'duplicate standalone state fields rejected');
check(parseTransportInfo(response('STOPPED')) == 'STOPPED', 'stopped response parsed');
check(parseTransportInfo(response('PAUSED_PLAYBACK')) == 'PAUSED_PLAYBACK', 'paused response parsed');
check(parseTransportInfo(response('TRANSITIONING')) == 'TRANSITIONING', 'transition response parsed');
check(parseTransportInfo(response('NO_MEDIA_PRESENT')) == 'NO_MEDIA_PRESENT', 'empty transport response parsed');
check(parseTransportInfo(response('vendor-state')) == null, 'unknown transport state rejected');
check(parseTransportInfo('') == null, 'empty response rejected');
check(parseTransportInfo(response('PLAYING') + '<!DOCTYPE x>') == null, 'trailing markup rejected');
check(parseTransportInfo(replace(response('PLAYING'), '<CurrentTransportState>', '<CurrentTransportState>PLAYING</CurrentTransportState><CurrentTransportState>')) == null, 'duplicate state rejected');
check(parseTransportInfo(replace(response('PLAYING'), 'PLAYING', 'PLAY' + chr(1) + 'ING')) == null, 'control byte rejected');
check(stateOf('PLAYING') === true, 'playing maps true');
check(stateOf('STOPPED') === false, 'stopped maps false');
check(stateOf('PAUSED_PLAYBACK') === false, 'paused maps false');
check(stateOf('NO_MEDIA_PRESENT') === false, 'no media maps false');
check(stateOf('TRANSITIONING') == null, 'transition maps unknown');
check(stateOf(null) == null, 'missing state maps unknown');
check(stateOf('RECORDING') == null && stateOf('CUSTOM') == null, 'unsupported recording and custom states remain unknown');

check(!validTarget('http://192.168.20.11:1400/AVTransport', '192.168.20.10', '192.168.20.1'), 'target validation rejects a mismatched host');
check(!validTarget('http://127.0.0.1:1400/AVTransport', '127.0.0.1', '192.168.20.1'), 'target validation rejects loopback');
check(!validTarget('http://192.168.20.1:1400/AVTransport', '192.168.20.1', '192.168.20.1'), 'target validation rejects router address');
check(query('http://192.168.20.11:1400/AVTransport', '192.168.20.10', '192.168.20.1') == null, 'query refuses a different device IP');
check(query('http://192.168.20.10:1400/AVTransport', '192.168.20.10', '192.168.20.1') == null, 'query refuses a different LAN host instead of attempting a request');
check(query('http://192.168.20.10:1400/AVTransport', '127.0.0.1', '192.168.20.1') == null, 'query refuses loopback/router-local addresses');
check(query('http://192.168.20.1:1400/AVTransport', '192.168.20.1', '192.168.20.1') == null, 'query refuses the router local address');
printf('Playback parser: %d checks passed\n', checks);
