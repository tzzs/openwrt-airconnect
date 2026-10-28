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

	console.log(passed + ' passed; ' + failed + ' failed');
	process.exitCode = failed === 0 ? 0 : 1;
}

try {
	main();
}
catch (error) {
	console.error('luci: ' + (error && error.stack ? error.stack : error));
	process.exitCode = 1;
}
