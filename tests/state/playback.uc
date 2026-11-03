// Additional pure status checks for per-device playback observations.
import { buildStatus } from '../../packages/airconnect-manager/files/usr/share/airconnect-manager/state.uc';

function assert(value, message) { if (!value) die(message); }
function status(playback) {
	return buildStatus({
		uciMain: { enabled: '1', interface: 'br-lan', airupnp: '1' },
		serviceState: { upnp: true, cast: false },
		cached: { scanned_at: 1700000000, devices: [{
			engine: 'upnp', udn: 'uuid:demo', address: '192.0.2.8', online: true,
			control_url: 'http://192.0.2.8:1400/AVTransport/control',
			playback_state: playback.state, playback_observed_at: playback.observed_at
		}] },
		now: 1700000000
	}).devices[0];
}
let playing = status({ state: true, observed_at: 1700000000 });
assert(playing.playback_state === true && playing.playback_observed_at == 1700000000, 'playing status and timestamp reach device view');
let stopped = status({ state: false, observed_at: 1700000000 });
assert(stopped.playback_state === false, 'stopped status is measured false');
let unknown = status({ state: null, observed_at: null });
assert(unknown.playback_state === null && unknown.playback_observed_at === null, 'failed query remains unknown');
assert(unknown.control_url == 'http://192.0.2.8:1400/AVTransport/control', 'control endpoint is preserved');
print('Playback status shaping: 4 checks passed\n');
