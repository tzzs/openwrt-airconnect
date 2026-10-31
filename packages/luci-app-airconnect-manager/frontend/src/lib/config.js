/**
 * Config shape shared by the LuCI form and the backend (`config.uc`).
 *
 * `mainKeys` are the top-level options of the single `main` section.
 * `deviceKeys` are the per-speaker options, where an empty value means
 * "inherit the global value" (config.uc's `inherited()`).
 *
 * `buildCanonicalConfig(uci)` assembles the `{ main, devices, removed }`
 * payload that `airconnect.manager validate` expects from the form, from a UCI
 * accessor that mirrors LuCI's `uci` object. Keeping this here means the test
 * suites can drive it with a fake `uci` and the app uses the real one.
 */
export const MAIN_KEYS = [
	'enabled', 'interface', 'airupnp', 'aircast', 'codec', 'latency',
	'max_volume', 'media_volume', 'log_level', 'metadata', 'flush', 'drift',
	'artwork', 'http_length', 'upnp_max', 'stop_receiver'
];

export const DEVICE_KEYS = [
	'engine', 'udn', 'enabled', 'name', 'max_volume', 'media_volume', 'codec',
	'latency', 'metadata', 'flush', 'drift', 'artwork', 'http_length', 'stop_receiver'
];

export const ENGINE_VALUES = ['upnp', 'cast'];

/**
 * Build the canonical config object the manager validates.
 *
 * @param {object} uci A LuCI-like uci handle: `get(pkg, section, key)` and
 *   `sections(pkg, type, cb)`. `cb` receives each section record with its
 *   `.name`. A real `window.uci` satisfies this; the test shims do too.
 */
export function buildCanonicalConfig(uci) {
	const main = {};
	for (const field of MAIN_KEYS) {
		const v = uci.get('airconnect-manager', 'main', field);
		if (v != null) main[field] = v;
	}
	const devices = [];
	const removed = [];
	uci.sections('airconnect-manager', 'device', (s) => {
		if (s['.removed']) {
			removed.push(s['.name']);
			return;
		}
		const item = { section: s['.name'] };
		for (const field of DEVICE_KEYS) {
			if (s[field] != null) item[field] = s[field];
		}
		devices.push(item);
	});
	return { main, devices, removed };
}
