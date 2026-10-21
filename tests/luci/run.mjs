#!/usr/bin/env node
// SPDX-License-Identifier: MIT
// Which advanced controls the LuCI view offers, per engine.
//
//   node tests/luci/run.mjs
//
// config.uc already refuses to render a Cast-only element into <airupnp> and
// vice versa (tests/config/run.uc asserts that). This suite covers the other
// half of the same requirement: the form must not offer a control that the
// engine the user is editing will silently ignore. It loads the real, unmodified
// production view through the same `new Function` module shim
// tests/parity/check-frontend.mjs uses, and inspects the options the two form
// builders create.
//
// What is deliberately NOT asserted: that a real LuCI renders these options, or
// that a real browser submits them. This proves the view's own decisions, which
// is what a code change can break.
//
// Exit status: 0 when every assertion holds, 1 otherwise.

import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');
const VIEW_PATH = join(ROOT,
	'packages/luci-app-airconnect-manager/htdocs/luci-static/resources/view/airconnect-manager/overview.js');
const RULES_PATH = join(ROOT,
	'packages/luci-app-airconnect-manager/htdocs/luci-static/resources/airconnect-manager/rules.js');

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

// --- minimal DOM and LuCI shims -------------------------------------------
//
// Only what the two form builders touch. `E` returns a node-like object with the
// attributes and children it was given; nothing here interprets CSS or layout.

function E(tag, attributes, children) {
	const node = {
		tagName: String(tag).toUpperCase(),
		attributes: Object.assign({}, attributes || {}),
		children: [],
		textContent: '',
		hidden: false,
		appendChild(child) { this.children.push(child); return child; },
		replaceChildren(...items) { this.children = items.flat(); }
	};
	for (const child of [].concat(children == null ? [] : children)) {
		if (child == null) continue;
		node.children.push(typeof child === 'object' ? child : String(child));
	}
	return node;
}

// A form.Map that records every option instead of building controls. `option()`
// is the same signature the real LuCI form API uses.
function createForm() {
	class FakeMap {
		constructor(config) { this.config = config; this.sections = []; }

		section(type, id, kind, title) {
			const record = {
				id, kind, title, addremove: true, options: [],
				option(optionType, name, label, description) {
					const option = {
						type: optionType, name, label, description,
						values: [], rmempty: true, validate: null, placeholder: null
					};
					option.value = (value, text) => { option.values.push([value, text]); return option; };
					record.options.push(option);
					return option;
				}
			};
			this.sections.push(record);
			return record;
		}

		render() { return Promise.resolve(E('div', { 'class': 'cbi-map' })); }
		parse() { return Promise.resolve(); }
	}
	return {
		Map: FakeMap,
		NamedSection: 'namedsection',
		Flag: 'flag',
		Value: 'value',
		ListValue: 'listvalue'
	};
}

function createUci(data) {
	return {
		load: () => Promise.resolve(),
		get(packageName, section, key) {
			const entry = data[section];
			if (entry == null) return null;
			return key == null ? entry : (entry[key] ?? null);
		},
		set() { },
		unset() { },
		add() { return 'demo'; },
		sections(packageName, type, callback) {
			const sections = Object.values(data).filter((entry) => entry['.type'] === type);
			if (callback) sections.forEach(callback);
			return sections;
		},
		save() { return Promise.resolve(); }
	};
}

// rules.js ends with a top-level `return {...}`, so the factory's own return
// value is the module. (LuCI wraps it differently; the shim mirrors
// tests/parity/check-frontend.mjs, which is the established pattern here.)
function loadRules() {
	const source = readFileSync(RULES_PATH, 'utf8');
	const factory = new Function('_', 'module', source + '\nreturn module.exports;\n');
	const module = { exports: {} };
	const exported = factory((text) => text, module);
	if (exported == null || typeof exported !== 'object')
		throw new Error('rules.js did not return an exports object');
	return exported;
}

function loadView(env) {
	const source = readFileSync(VIEW_PATH, 'utf8');
	const factory = new Function(
		'view', 'form', 'uci', 'rpc', 'ui', 'poll', 'L', 'E', '_', 'rules',
		source + '\nreturn view.extend({});\n');
	return factory(
		{ extend: (definition) => definition },
		env.form, env.uci, env.rpc, env.ui, env.poll, env.L, E, (text) => text, env.rules);
}

const MAIN_KEYS = {
	'.name': 'main', '.type': 'main', enabled: '1', interface: 'br-lan',
	airupnp: '1', aircast: '1', codec: 'flac', latency: '1000:2000',
	max_volume: '100', media_volume: '0.5', log_level: 'warn',
	metadata: '1', artwork: '', flush: '1', drift: '0',
	http_length: '-1', upnp_max: '1', stop_receiver: '0'
};

// Build a view instance with one configured device of the given engine, run the
// two form builders, and describe the options each produced.
async function optionsFor(engine) {
	const uci = createUci({
		main: MAIN_KEYS,
		cfg_demo: {
			'.name': 'cfg_demo', '.type': 'device', engine,
			udn: 'uuid:demo-' + engine, enabled: '1', name: ''
		}
	});
	const instance = loadView({
		uci,
		form: createForm(),
		rpc: { declare: () => () => Promise.resolve({}) },
		ui: { addNotification() { }, changes: { init: () => Promise.resolve(), apply: () => Promise.resolve() } },
		poll: { add() { }, remove() { }, start() { }, stop() { } },
		L: { bind: (fn, context) => fn.bind(context), resource: (path) => path },
		rules: loadRules()
	});
	instance.maps = [];
	instance.deviceMaps = [];
	instance.cards = {};

	await instance.makeMainForm();
	await instance.makeDeviceForm(
		{ engine, udn: 'uuid:demo-' + engine, original_name: 'Demo Speaker' }, 'cfg_demo');

	// makeMainForm() pushes the general map first and the advanced map second.
	const globalOptions = instance.maps[1].sections[0].options;
	// makeDeviceForm() pushes the primary map, then the advanced map.
	const deviceOptions = instance.deviceMaps[instance.deviceMaps.length - 1].sections[0].options;
	return {
		main: describe(globalOptions),
		device: describe(deviceOptions)
	};
}

// name -> { label, values, validate }. `validate` is LuCI's callback, called as
// validate(sectionId, value); an empty value is what "inherit" submits.
function describe(options) {
	const result = {};
	for (const option of options) {
		result[option.name] = {
			label: String(option.label == null ? '' : option.label),
			values: option.values.map((pair) => pair[0]),
			rmempty: option.rmempty,
			acceptsEmpty: typeof option.validate === 'function' ? option.validate('cfg_demo', '') === true : null
		};
	}
	return result;
}

const SHARED_ADVANCED = ['metadata', 'artwork', 'flush', 'drift'];
const UPNP_ONLY = ['http_length', 'upnp_max'];
const CAST_ONLY = ['stop_receiver'];

async function main() {
	section('global advanced panel');
	const upnp = await optionsFor('upnp');
	const cast = await optionsFor('cast');

	for (const name of SHARED_ADVANCED)
		check(upnp.main[name] != null, 'the global advanced panel offers ' + name);
	// The global panel is shared by both engines, so the engine-specific fields
	// are present but labelled as such: a global value is written to whichever
	// engine reads it and ignored by the other.
	for (const name of UPNP_ONLY)
		check(upnp.main[name] != null, 'the global advanced panel offers ' + name);
	check(upnp.main.stop_receiver != null, 'the global advanced panel offers stop_receiver');
	// Both engines must build the same global panel; a field missing on one side
	// would make the panel depend on whichever device happened to be rendered.
	check(JSON.stringify(Object.keys(upnp.main)) === JSON.stringify(Object.keys(cast.main)),
		'the global advanced panel is engine independent',
		Object.keys(upnp.main).join(',') + ' vs ' + Object.keys(cast.main).join(','));

	section('UPnP device advanced panel');
	for (const name of SHARED_ADVANCED)
		check(upnp.device[name] != null, 'a UPnP device offers ' + name);
	check(upnp.device.http_length != null, 'a UPnP device offers http_length');
	for (const name of CAST_ONLY)
		check(upnp.device[name] == null, 'a UPnP device does NOT offer ' + name);

	section('Chromecast device advanced panel');
	for (const name of SHARED_ADVANCED)
		check(cast.device[name] != null, 'a Chromecast device offers ' + name);
	check(cast.device.stop_receiver != null, 'a Chromecast device offers stop_receiver');
	for (const name of UPNP_ONLY)
		check(cast.device[name] == null, 'a Chromecast device does NOT offer ' + name);
	// upnp_max is global-only in the backend (airupnp never reads a per-device
	// value), so it must not appear per device even on a UPnP speaker: that would
	// be a control which saves something the engine never reads.
	check(upnp.device.upnp_max == null, 'a UPnP device does NOT offer the global-only upnp_max');

	section('device overrides can inherit');
	// Every per-device advanced control must accept an empty value, which is what
	// "inherit the global setting" means in config.uc's inherited().
	for (const built of [upnp, cast]) {
		const engine = built === upnp ? 'UPnP' : 'Chromecast';
		for (const name of Object.keys(built.device))
			if (SHARED_ADVANCED.includes(name) || name === 'http_length' || name === 'stop_receiver')
				check(built.device[name].acceptsEmpty === true,
					'a ' + engine + ' device ' + name + ' accepts an empty (inherit) value');
	}

	section('enum values match config.uc');
	// The select must offer exactly the values the backend accepts, otherwise the
	// user can pick something that is rejected on save.
	check(JSON.stringify(upnp.main.http_length.values) === JSON.stringify(['-1', '-3', '0']),
		'the http_length select offers -1, -3 and 0',
		JSON.stringify(upnp.main.http_length.values));
	const versions = upnp.main.upnp_max.values;
	check(versions.length === 9 && versions[0] === '1' && versions[8] === '9',
		'the upnp_max select offers 1 through 9', JSON.stringify(versions));
	check(JSON.stringify(upnp.main.metadata.values) === JSON.stringify(['1', '0']),
		'the metadata select offers 1 and 0', JSON.stringify(upnp.main.metadata.values));
	check(JSON.stringify(upnp.main.drift.values) === JSON.stringify(['0', '1']),
		'the drift select lists its default (0) first', JSON.stringify(upnp.main.drift.values));

	section('engine-specific labels');
	// The user has to be told which engine a global field belongs to, because the
	// panel is shared. A label without the engine name would read as if both
	// engines used it.
	check(/UPnP/.test(upnp.main.http_length.label), 'http_length is labelled UPnP only',
		upnp.main.http_length.label);
	check(/UPnP/.test(upnp.main.upnp_max.label), 'upnp_max is labelled UPnP only',
		upnp.main.upnp_max.label);
	check(/Chromecast/.test(upnp.main.stop_receiver.label), 'stop_receiver is labelled Chromecast only',
		upnp.main.stop_receiver.label);
	// The shared fields must NOT claim to belong to one engine.
	for (const name of SHARED_ADVANCED) {
		const label = upnp.main[name].label;
		check(!/UPnP only|Chromecast only/.test(label),
			'the shared field ' + name + ' is not labelled as engine specific', label);
	}

	console.log(passed + ' passed; ' + failed + ' failed');
	process.exitCode = failed === 0 ? 0 : 1;
}

try {
	await main();
}
catch (error) {
	console.error('luci: ' + (error && error.stack ? error.stack : error));
	process.exitCode = 1;
}
