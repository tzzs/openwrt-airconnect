/**
 * The settings panels as data, not markup.
 *
 * Both the Settings tab and each speaker's advanced section are rendered from
 * these descriptors, so "which control does the UI offer, for which engine, with
 * which options" lives in one place instead of being spread over JSX. The LuCI
 * test suite imports this module directly and asserts the same contract the
 * hand-written form used to carry: a Cast speaker is never offered a UPnP-only
 * control, and vice versa.
 *
 * A descriptor is one of:
 *
 *   { kind: 'flag',   name, label, description, values, inherit }
 *   { kind: 'text',   name, label, description, rule, placeholder, inherit }
 *   { kind: 'select', name, label, description, options, rule, inherit }
 *
 * `values` on a flag is the on/off order, default-first: LuCI selects the first
 * entry when a value is absent, so a configuration that predates the field shows
 * the value the engine is actually using. `inherit` marks a per-device control
 * whose empty value means "use the global setting" (config.uc's `inherited()`).
 *
 * `createFields(t)` takes the translation helper (`_` in LuCI) so the labels are
 * translated in the app and fall back to English under the host test runner.
 */

const CODEC_VALUES = ['flac', 'pcm', 'wav', 'mp3', 'aac'];
const LOG_LEVELS = ['error', 'warn', 'info', 'debug'];

export function createFields(t) {
	const _ = typeof t === 'function' ? t : function (s) { return s; };

	const codecs = CODEC_VALUES.map((value) => ({ value, label: value.toUpperCase() }));
	const logLevels = LOG_LEVELS.map((value) => ({ value, label: value }));
	const httpLength = [
		{ value: '-1', label: _('-1: no content-length (default)') },
		{ value: '-3', label: _('-3: chunked encoding') },
		{ value: '0', label: _('0: fixed dummy length') }
	];
	const upnpVersions = [];
	for (let version = 1; version <= 9; version++)
		upnpVersions.push({ value: String(version), label: String(version) });

	function flag(name, label, description, options) {
		const settings = options || {};
		const fallback = settings.fallback === '0' ? '0' : '1';
		const inherit = settings.inherit === true;
		// Default first: an absent option renders the value the engine uses.
		const values = fallback === '0' ? ['0', '1'] : ['1', '0'];
		const choices = values.map((value) => ({
			value,
			label: value === '1' ? _('On (1)') : _('Off (0)')
		}));
		return {
			name,
			kind: 'flag',
			label,
			description: description || '',
			inherit,
			values,
			// A per-device flag cannot be a plain on/off switch: empty means
			// "inherit the global setting", and a switch has no empty state. It
			// renders as a three-way select instead.
			options: inherit
				? [{ value: '', label: _('Inherit global setting') }].concat(choices)
				: choices
		};
	}

	function text(name, label, description, rule, placeholder, inherit) {
		return {
			name,
			kind: 'text',
			label,
			description: description || '',
			rule: rule || null,
			placeholder: placeholder || '',
			inherit: inherit === true
		};
	}

	function select(name, label, description, options, rule, inherit) {
		return {
			name,
			kind: 'select',
			label,
			description: description || '',
			options,
			rule: rule || null,
			inherit: inherit === true
		};
	}

	// The global panel. It is one list, used for every engine: a global value is
	// written to whichever engine reads it and ignored by the other, so the
	// fields that only one engine reads say so in their label instead of the
	// panel changing shape with whichever speaker happened to render first.
	const main = [
		flag('enabled', _('Enable AirConnect'),
			_('Changes take effect after Save & Apply. Applying briefly disconnects AirPlay.')),
		text('interface', _('LAN interface'),
			_('Bind discovery and AirPlay to your local network interface.'), 'interfaceValue'),
		flag('airupnp', _('UPnP / DLNA speakers')),
		flag('aircast', _('Chromecast speakers')),
		text('max_volume', _('UPnP volume limit'),
			_('Default maximum volume, from 1 to 100.'), 'upnpVolume', '100'),
		text('media_volume', _('Chromecast media volume'),
			_('Default media volume, from 0 to 1. This is not a volume limit.'), 'castVolume', '0.5'),
		select('codec', _('Audio format'),
			_('FLAC can use more CPU. Choose a format supported by your speaker.'), codecs),
		text('latency', _('Buffer and latency'),
			_('Format: 1000:2000. Lower values may cause audio dropouts.'), 'latency', '1000:2000'),
		flag('metadata', _('Send track information'),
			_('Sends the title and artist to the speaker. Both engines read this. A speaker may still show nothing.')),
		text('artwork', _('Cover art URL'),
			_('Optional http:// or https:// image the speaker fetches itself. Leave empty for none. The router never downloads it.'),
			'artwork', 'https://…'),
		flag('flush', _('Handle FLUSH'),
			_('Compatibility option, both engines. Turning it off can change pause and track-change behaviour, so keep it on unless a speaker misbehaves.')),
		flag('drift', _('Let the timing reference drift'),
			_('Both engines. Off adjusts timing by adding or dropping a frame, which can be audible as a click; on avoids the click but risks underruns.'),
			{ fallback: '0' }),
		select('http_length', _('HTTP transfer mode (UPnP only)'),
			_('Compatibility only. Change this when a UPnP speaker cannot play at all; the default works for most devices.'),
			httpLength, 'httpLength'),
		select('upnp_max', _('UPnP search version (UPnP only)'),
			_('Highest UPnP MediaRenderer version to search. The Chromecast engine ignores this.'),
			upnpVersions, 'upnpMax'),
		flag('stop_receiver', _('Stop the receiver (Chromecast only)'),
			_('Chromecast compatibility option. The UPnP engine ignores this.'), { fallback: '0' }),
		select('log_level', _('Log detail'), '', logLevels, 'logLevel')
	];

	// Per-speaker overrides. Every control here accepts an empty value, which is
	// what "inherit the global setting" means; the two engine-specific groups are
	// disjoint on purpose, because each engine's parser has no element for the
	// other's option and would silently ignore a value the user could set.
	const shared = [
		text('name', _('AirPlay name'),
			_('Changes only the virtual AirPlay receiver name. Leave empty to use the original name.'),
			'airplayName', '', true),
		select('codec', _('Audio format'), '', [].concat(
			[{ value: '', label: _('Inherit global setting') }], codecs), null, true),
		text('latency', _('Buffer and latency'), _('Leave empty to inherit the global setting.'),
			'latency', '', true),
		flag('metadata', _('Send track information'), _('Leave empty to inherit the global setting.'),
			{ inherit: true }),
		text('artwork', _('Cover art URL'), _('Leave empty to inherit the global setting.'),
			'artwork', '', true),
		flag('flush', _('Handle FLUSH'), _('Leave empty to inherit the global setting.'),
			{ inherit: true }),
		flag('drift', _('Let the timing reference drift'), _('Leave empty to inherit the global setting.'),
			{ inherit: true, fallback: '0' })
	];

	const upnp = [].concat(
		[
			flag('enabled', _('Enable bridging')),
			text('max_volume', _('Volume limit'),
				_('Leave empty to inherit the global UPnP limit.'), 'upnpVolume', '', true)
		],
		shared,
		[
			select('http_length', _('HTTP transfer mode'),
				_('Leave empty to inherit the global setting.'),
				[{ value: '', label: _('Inherit global setting') }].concat(httpLength), 'httpLength', true)
		]
	);

	const cast = [].concat(
		[
			flag('enabled', _('Enable bridging')),
			text('media_volume', _('Media volume'),
				_('Leave empty to inherit the global Chromecast volume.'), 'castVolume', '', true)
		],
		shared,
		[
			flag('stop_receiver', _('Stop the receiver'),
				_('Leave empty to inherit the global setting.'), { inherit: true, fallback: '0' })
		]
	);

	// Grouping is presentation only: the device panels show the everyday
	// controls first and fold the compatibility options away, and the global
	// settings page sorts the fields into named sections. It never changes
	// which fields exist, so the contract tests ignore it.
	//
	// `section` is the global page's grouping: each section becomes one card
	// with a heading, so a long list of sixteen options reads as four topics
	// instead of one wall of controls.
	const MAIN_SECTIONS = {
		enabled: 'service',
		interface: 'service',
		airupnp: 'service',
		aircast: 'service',
		max_volume: 'audio',
		media_volume: 'audio',
		codec: 'audio',
		latency: 'audio',
		metadata: 'compatibility',
		artwork: 'compatibility',
		flush: 'compatibility',
		drift: 'compatibility',
		http_length: 'compatibility',
		upnp_max: 'compatibility',
		stop_receiver: 'compatibility',
		log_level: 'diagnostics'
	};
	for (const field of main)
		field.section = MAIN_SECTIONS[field.name] || 'audio';

	const DEVICE_PRIMARY = ['enabled', 'name', 'max_volume', 'media_volume'];
	for (const field of upnp.concat(cast))
		field.group = DEVICE_PRIMARY.indexOf(field.name) >= 0 ? 'primary' : 'advanced';

	return { main, device: { upnp, cast } };
}
