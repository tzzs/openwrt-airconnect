#!/usr/bin/env node
// SPDX-License-Identifier: MIT
// Which advanced controls the page offers, per engine.
//
//   node tests/luci/run.mjs
//
// config.uc already refuses to render a Cast-only element into <airupnp> and
// vice versa (tests/config/run.uc asserts that). This suite covers the other
// half of the same requirement: the form must not offer a control that the
// engine the user is editing will silently ignore.
//
// The panels are rendered from frontend/src/lib/fields.js, so the contract is a
// plain data structure and this file asserts it directly - no DOM, no LuCI, no
// bundler. A field's descriptor decides the control, its options and its rule;
// if a descriptor is wrong, the page is wrong, and this fails.
//
// Exit status: 0 when every assertion holds, 1 otherwise.

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');
const FRONTEND_SRC = join(ROOT, 'packages/luci-app-airconnect-manager/frontend/src');
const { createFields } = await import(new URL(
	'../../packages/luci-app-airconnect-manager/frontend/src/lib/fields.js', import.meta.url));
const INTERFACES = await import(new URL(
	'../../packages/luci-app-airconnect-manager/frontend/src/lib/interfaces.js', import.meta.url));
const NAVIGATION = await import(new URL(
	'../../packages/luci-app-airconnect-manager/frontend/src/lib/navigation.js', import.meta.url));

let passed = 0;
let failed = 0;

function check(ok, label, detail) {
	if (ok) {
		passed++;
		return true;
	}
	failed++;
	console.error('not ok - ' + label + (detail ? ': ' + detail : ''));
	return false;
}

function section(title) {
	console.log('# ' + title);
}

/** name -> descriptor, preserving order. */
function index(fields) {
	const result = {};
	for (const field of fields) result[field.name] = field;
	return result;
}

function sourceFiles(directory) {
	const found = [];
	for (const entry of readdirSync(directory, { withFileTypes: true })) {
		const path = join(directory, entry.name);
		if (entry.isDirectory()) found.push(...sourceFiles(path));
		else if (/\.(js|jsx)$/.test(entry.name)) found.push(path);
	}
	return found;
}

const SHARED_ADVANCED = ['metadata', 'artwork', 'flush', 'drift'];
const UPNP_ONLY = ['http_length', 'upnp_max'];
const CAST_ONLY = ['stop_receiver'];

function main() {
	const fields = createFields(function (text) { return text; });
	const mainPanel = index(fields.main);
	const upnp = index(fields.device.upnp);
	const cast = index(fields.device.cast);

	section('theme-safe markup');
	// Argon, the iStoreOS theme, styles a bare `header` as the site header:
	// `color: #fff` plus a `header::after` bar painted with the theme's primary
	// colour. A <header> inside this page therefore renders its heading
	// white-on-white with a stray blue band across the page. No host shim
	// reproduces a theme, so the markup itself is the contract here: `section`
	// and `article` have no bare theme rule, `header` does.
	const offenders = [];
	for (const path of sourceFiles(FRONTEND_SRC)) {
		const source = readFileSync(path, 'utf8');
		if (/<header[\s>]/.test(source)) offenders.push(path.slice(ROOT.length + 1));
	}
	check(offenders.length === 0, 'the page never renders a <header> element',
		offenders.join(', ') + '; use a <div> with the same styling instead');

	section('global panel');
	for (const name of SHARED_ADVANCED)
		check(mainPanel[name] != null, 'the global panel offers ' + name);
	// The global panel is shared by both engines, so the engine-specific fields
	// are present but labelled as such: a global value is written to whichever
	// engine reads it and ignored by the other.
	for (const name of UPNP_ONLY)
		check(mainPanel[name] != null, 'the global panel offers ' + name);
	check(mainPanel.stop_receiver != null, 'the global panel offers stop_receiver');
	// One list, not one per engine: a field missing on one side would make the
	// panel depend on whichever speaker happened to be rendered.
	check(Array.isArray(fields.main), 'the global panel is a single engine-independent list');
	check(JSON.stringify(createFields().main.map((f) => f.name)) ===
		JSON.stringify(createFields(function (s) { return s; }).main.map((f) => f.name)),
		'the global panel does not depend on the translation helper');

	section('UPnP device panel');
	for (const name of SHARED_ADVANCED)
		check(upnp[name] != null, 'a UPnP speaker offers ' + name);
	check(upnp.http_length != null, 'a UPnP speaker offers http_length');
	for (const name of CAST_ONLY)
		check(upnp[name] == null, 'a UPnP speaker does NOT offer ' + name);

	section('Chromecast device panel');
	for (const name of SHARED_ADVANCED)
		check(cast[name] != null, 'a Chromecast speaker offers ' + name);
	check(cast.stop_receiver != null, 'a Chromecast speaker offers stop_receiver');
	for (const name of UPNP_ONLY)
		check(cast[name] == null, 'a Chromecast speaker does NOT offer ' + name);
	// upnp_max is global-only in the backend (airupnp never reads a per-device
	// value), so it must not appear per speaker even on a UPnP device: that would
	// be a control which saves something the engine never reads.
	check(upnp.upnp_max == null, 'a UPnP speaker does NOT offer the global-only upnp_max');

	section('device overrides can inherit');
	// Every per-speaker advanced control must accept an empty value, which is
	// what "inherit the global setting" means in config.uc's inherited().
	for (const [engine, panel] of [['UPnP', upnp], ['Chromecast', cast]]) {
		for (const name of Object.keys(panel)) {
			if (!(SHARED_ADVANCED.includes(name) || name === 'http_length' || name === 'stop_receiver'))
				continue;
			check(panel[name].inherit === true,
				'a ' + engine + ' speaker ' + name + ' accepts an empty (inherit) value');
		}
	}
	// An inheriting flag cannot be a two-state switch: it needs the empty choice
	// in its option list or the user can never get back to "inherit".
	for (const panel of [upnp, cast]) {
		for (const field of Object.values(panel)) {
			if (field.kind !== 'flag' || field.inherit !== true) continue;
			check(field.options[0].value === '',
				'the inheriting flag ' + field.name + ' lists "inherit" first');
		}
	}

	section('enum values match config.uc');
	// The select must offer exactly the values the backend accepts, otherwise the
	// user can pick something that is rejected on save.
	check(JSON.stringify(mainPanel.http_length.options.map((o) => o.value)) ===
		JSON.stringify(['-1', '-3', '0']),
		'the http_length select offers -1, -3 and 0',
		JSON.stringify(mainPanel.http_length.options.map((o) => o.value)));
	const versions = mainPanel.upnp_max.options.map((o) => o.value);
	check(versions.length === 9 && versions[0] === '1' && versions[8] === '9',
		'the upnp_max select offers 1 through 9', JSON.stringify(versions));
	check(JSON.stringify(mainPanel.metadata.values) === JSON.stringify(['1', '0']),
		'the metadata flag writes 1 then 0', JSON.stringify(mainPanel.metadata.values));
	check(JSON.stringify(mainPanel.drift.values) === JSON.stringify(['0', '1']),
		'the drift flag lists its default (0) first', JSON.stringify(mainPanel.drift.values));
	// A device-level http_length must offer the inherit entry before the values.
	check(upnp.http_length.options[0].value === '' &&
		upnp.http_length.options.length === 4,
		'the device http_length select offers inherit plus the three modes',
		JSON.stringify(upnp.http_length.options.map((o) => o.value)));

	section('engine-specific labels');
	// The user has to be told which engine a global field belongs to, because the
	// panel is shared. A label without the engine name would read as if both
	// engines used it.
	check(/UPnP/.test(mainPanel.http_length.label), 'http_length is labelled UPnP only',
		mainPanel.http_length.label);
	check(/UPnP/.test(mainPanel.upnp_max.label), 'upnp_max is labelled UPnP only',
		mainPanel.upnp_max.label);
	check(/Chromecast/.test(mainPanel.stop_receiver.label),
		'stop_receiver is labelled Chromecast only', mainPanel.stop_receiver.label);
	// The shared fields must NOT claim to belong to one engine.
	for (const name of SHARED_ADVANCED) {
		check(!/UPnP only|Chromecast only/.test(mainPanel[name].label),
			'the shared field ' + name + ' is not labelled as engine specific',
			mainPanel[name].label);
	}

	section('every field names a real rule');
	// A typo here would silently drop validation: the control would render and
	// accept anything.
	const rules = ['interfaceValue', 'upnpVolume', 'castVolume', 'latency',
		'airplayName', 'logLevel', 'binaryFlag', 'httpLength', 'upnpMax', 'artwork'];
	const all = [].concat(fields.main, fields.device.upnp, fields.device.cast);
	for (const field of all) {
		if (field.rule == null) continue;
		check(rules.includes(field.rule),
			field.name + ' names a documented rule', String(field.rule));
	}

	interfaceSection(fields);
	navigationSection();
	portalSection();

	console.log(passed + ' passed; ' + failed + ' failed');
	process.exitCode = failed === 0 ? 0 : 1;
}

/**
 * The settings page is a second LuCI view, so it needs its own way back. Both
 * URLs are derived from the current one because the dispatcher prefix
 * (`/cgi-bin/luci` by default) is not something the app may hardcode.
 */
function navigationSection() {
	section('moving between the two pages');
	const { parentPageUrl, settingsPageUrl } = NAVIGATION;
	const base = 'http://192.168.100.1/cgi-bin/luci/admin/services/airconnect-manager';

	check(settingsPageUrl(base) === base + '/settings',
		'global settings is the workspace URL plus one segment', settingsPageUrl(base));
	check(settingsPageUrl(base + '/') === base + '/settings',
		'a trailing slash does not produce a double slash');
	check(settingsPageUrl(base + '/settings') === base + '/settings',
		'the settings URL is not appended to itself');

	check(parentPageUrl(base + '/settings') === base,
		'back returns to the device workspace', parentPageUrl(base + '/settings'));
	check(parentPageUrl(base + '/settings/') === base,
		'a trailing slash is ignored');
	const custom = 'http://router/foo/bar/airconnect-manager';
	check(parentPageUrl(custom + '/settings') === custom,
		'a custom dispatcher prefix is kept', parentPageUrl(custom + '/settings'));
	check(parentPageUrl(base) === base,
		'a URL that is not the settings page is returned unchanged');
	check(parentPageUrl('http://router/settings') === 'http://router/',
		'a bare /settings goes to the root', parentPageUrl('http://router/settings'));
	check(parentPageUrl(base + '/settings?x=1#top') === base,
		'the query and the hash do not follow the user back');
}

/**
 * The drawer and the select menu are portalled into <body>, which is outside
 * `.ac-root` - the element that carries the palette, the button reset and the
 * scope every generated utility is written against. Without its own marker the
 * portal content lost all three: the interface dropdown rendered with no
 * background, Argon's text colour and a currentColor border, and it was
 * invisible in dark mode.
 *
 * These are source-level assertions because the failure is a cascade problem,
 * not a function's return value: no host test runner renders CSS.
 */
function portalSection() {
	section('portalled content keeps the theme');
	const uiDir = join(FRONTEND_SRC, 'components');
	const portalled = sourceFiles(uiDir).filter((path) =>
		/\.Portal>/.test(readFileSync(path, 'utf8')));
	check(portalled.length > 0, 'at least one component portals its content');
	for (const path of portalled) {
		const source = readFileSync(path, 'utf8');
		check(/ac-portal/.test(source),
			path.slice(ROOT.length + 1) + ' marks its portal content with ac-portal');
	}

	// The utilities are scoped to a selector prefix, so the scope has to list
	// the portal marker too or the portalled markup receives none of them.
	const tailwind = readFileSync(join(FRONTEND_SRC, '..', 'tailwind.config.mjs'), 'utf8');
	const important = (tailwind.match(/important:\s*'([^']+)'/) || [])[1] || '';
	check(important.includes('.ac-root') && important.includes('.ac-portal'),
		'generated utilities are scoped to .ac-root and .ac-portal', important);

	// The palette has three blocks: light, the explicit dark class, and the
	// prefers-color-scheme fallback. A portal marker missing from one of them
	// makes the drawer light on a dark page (or the reverse).
	const css = readFileSync(join(FRONTEND_SRC, 'styles.css'), 'utf8');
	check(/\.ac-root,\s*\n\.ac-portal\s*\{/.test(css),
		'the light palette is declared for .ac-portal as well as .ac-root');
	check(/\.ac-portal\.ac-theme-dark\s*\{/.test(css),
		'the explicit dark palette covers .ac-portal');
	check(/\.ac-portal:not\(\.ac-theme-light\):not\(\.ac-theme-dark\)/.test(css),
		'the system dark palette covers .ac-portal');

	// The reset has to stay at Argon's specificity. A plain `.ac-root button`
	// rule (0,1,1) outranks the generated utilities (0,1,0), which silently
	// dropped `text-primary-foreground` from Save & Apply.
	check(/:where\(\.ac-root, \.ac-portal\) button\s*\{/.test(css),
		'the button reset uses :where() so utilities still win over it');
}

/**
 * The LAN interface select.
 *
 * The value has to be a Linux device name because the engines bind with
 * SO_BINDTODEVICE; the logical UCI name is only what the router's pages call
 * it. The two cases that used to break the control are covered here: a device
 * whose logical name differs, and a configured interface that is currently
 * down (so it is absent from the dump and would otherwise render blank).
 */
function interfaceSection(fields) {
	const { DEFAULT_INTERFACE, interfaceOptionsFrom, interfaceValue, withInterfaceSelect } =
		INTERFACES;

	section('LAN interface select');
	const dump = {
		interface: [
			{ interface: 'lan', l3_device: 'br-lan', device: 'br-lan', up: true },
			{ interface: 'wan', l3_device: 'eth1', device: 'eth1', up: true },
			{ interface: 'loopback', l3_device: 'lo', device: 'lo', up: true },
			{ interface: 'guest', l3_device: '', device: 'br-guest', up: false },
			{ interface: 'wan6', l3_device: '', device: '', up: false }
		]
	};
	const options = interfaceOptionsFrom(dump, 'br-lan');
	const values = options.map((o) => o.value);
	check(values.join(',') === 'br-lan,eth1,br-guest',
		'the select lists the Linux devices of the up and down interfaces',
		values.join(','));
	check(options[0].label === 'lan (br-lan)',
		'a device whose logical name differs is labelled with both', options[0].label);
	check(options[1].label === 'wan (eth1)',
		'the logical name is kept next to the device', options[1].label);
	check(values.indexOf('lo') < 0, 'loopback is not offered as a LAN interface');

	// A down interface with no l3_device still reports its device; skipping it
	// would hide the one interface the user is trying to configure.
	check(values.includes('br-guest'),
		'a down interface is still offered through its device name');
	// An interface with neither l3_device nor device carries no usable value.
	check(values.indexOf('') < 0, 'an interface without a device is dropped');

	const down = interfaceOptionsFrom(dump, 'pppoe-wan');
	check(down[0].value === 'pppoe-wan',
		'the configured interface is kept when the dump does not list it', down[0].value);
	check(down.filter((o) => o.value === 'br-lan').length === 1,
		'keeping the configured value does not duplicate a listed one');
	check(interfaceOptionsFrom(dump, 'eth1').filter((o) => o.value === 'eth1').length === 1,
		'a listed configured interface is not prepended twice');

	const asObject = interfaceOptionsFrom({
		interface: {
			lan: { l3_device: 'br-lan', device: 'br-lan' },
			guest: { device: 'br-guest' }
		}
	}, 'br-lan');
	check(asObject.map((o) => o.value).join(',') === 'br-lan,br-guest',
		'the object form of the dump is accepted too',
		asObject.map((o) => o.value).join(','));

	// The select is only as good as its options: with none, the field must stay
	// a text input rather than become an empty dropdown that cannot be saved.
	check(interfaceOptionsFrom({ interface: [] }, 'br-lan') === null,
		'an empty dump yields no options, so the field stays a text input');
	check(interfaceOptionsFrom(null, '') === null, 'a missing dump yields no options');

	const select = withInterfaceSelect(fields.main, options);
	const interfaceField = select.find((f) => f.name === 'interface');
	check(interfaceField.kind === 'select', 'the interface field becomes a select');
	check(interfaceField.rule === 'interfaceValue',
		'the select keeps the same validation rule as the text input');
	check(interfaceField.options === options, 'the select uses the dumped devices');
	check(select.filter((f) => f.name !== 'interface').every((f) =>
		fields.main.find((m) => m.name === f.name) === f),
		'no other field descriptor is rebuilt');
	check(withInterfaceSelect(fields.main, null) === fields.main,
		'without options the original descriptors are returned untouched');

	// The form shows what the service will actually bind to, so an unset uci
	// option must not render as an empty select.
	check(interfaceValue(undefined) === DEFAULT_INTERFACE,
		'an unset interface shows the backend default', DEFAULT_INTERFACE);
	check(interfaceValue('') === DEFAULT_INTERFACE, 'an empty interface shows the default');
	check(interfaceValue('eth1') === 'eth1', 'a configured interface is shown as it is');

	// The default is not ours to choose: it is config.uc's, and the form must
	// agree with the file that decides it.
	const configSource = readFileSync(
		join(ROOT, 'packages/airconnect-manager/files/usr/share/airconnect-manager/config.uc'),
		'utf8');
	check(configSource.includes("'interface', '" + DEFAULT_INTERFACE + "'"),
		'the frontend default interface matches config.uc', DEFAULT_INTERFACE);
}


try {
	main();
}
catch (error) {
	console.error('luci: ' + (error && error.stack ? error.stack : error));
	process.exitCode = 1;
}
