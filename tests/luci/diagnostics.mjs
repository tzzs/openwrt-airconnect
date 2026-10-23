#!/usr/bin/env node
// SPDX-License-Identifier: MIT
// How the Diagnostics panel renders the four states.
//
//   node tests/luci/diagnostics.mjs
//
// The product rule this suite exists to defend: service running, discovered,
// broadcasting and playing are four different facts, each decided by its own
// source, and a state that was not measured must render as unknown - never as a
// positive, and never as a negative either. The previous implementation hardcoded
// "Unknown - not measured" for both broadcast and playback; broadcast is now a
// real measurement, so the risk moved from "no value" to "a value that implies
// another state".
//
// This loads the real, unmodified production view through the same `new
// Function` shim tests/performance/poll-contract.mjs uses, feeds it status
// replies, and reads back the rendered diagnostics rows and device badges.
//
// What is deliberately NOT asserted: that a real browser renders these strings,
// or that a real rpcd returns these replies. This proves the view's own
// decisions, which is what a code change can break.
//
// Exit status: 0 when every assertion holds, 1 otherwise.

import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');
const VIEW_PATH = join(ROOT,
	'packages/luci-app-airconnect-manager/htdocs/luci-static/resources/view/airconnect-manager/overview.js');

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

// --- minimal DOM shim ------------------------------------------------------
// Only what updateStatus() touches. `E` keeps attributes and children; text is
// kept as-is so the assertions can read the exact string the page would show.

class FakeNode {
	constructor(tag) {
		this.tagName = String(tag).toUpperCase();
		this.attributes = new Map();
		this.listeners = new Map();
		this.children = [];
		this.dataset = Object.create(null);
		this._text = '';
		this._hidden = false;
		this._disabled = false;
		this._class = '';
		this.tabIndex = 0;
	}
	get textContent() { return this._text; }
	set textContent(value) { this._text = value == null ? '' : String(value); this.children = []; }
	get className() { return this._class; }
	set className(value) { this._class = String(value); }
	get hidden() { return this._hidden; }
	set hidden(value) { this._hidden = !!value; }
	get disabled() { return this._disabled; }
	set disabled(value) { this._disabled = !!value; }
	getAttribute(name) { return this.attributes.has(name) ? this.attributes.get(name) : null; }
	setAttribute(name, value) { this.attributes.set(name, String(value)); }
	removeAttribute(name) { this.attributes.delete(name); }
	addEventListener(type, fn) { this.listeners.set(type, fn); }
	removeEventListener() { }
	focus() { }
	appendChild(node) { this.children.push(node); return node; }
	append(...nodes) { for (const node of nodes) this.appendChild(node); }
	replaceChildren(...items) {
		this.children = items.flat().filter((item) => item != null && item !== false);
		this._text = '';
	}
	click() { }
}

function E(tag, attributes, children) {
	const node = new FakeNode(tag);
	for (const [key, value] of Object.entries(attributes || {})) {
		if (typeof value === 'function') node.listeners.set(key, value);
		else if (key === 'hidden' || key === 'disabled') node[key] = value === true || value === '';
		else if (value === true) node.setAttribute(key, '');
		else if (value === false || value == null) continue;
		else if (key === 'class') node.className = String(value);
		else node.setAttribute(key, value);
	}
	const add = (child) => {
		if (child == null || child === false) return;
		if (Array.isArray(child)) { child.forEach(add); return; }
		node.appendChild(child instanceof FakeNode ? child : String(child));
	};
	add(children);
	return node;
}

// Collect the text of a subtree, so an assertion can say what the user sees.
function render(node) {
	if (node == null) return '';
	if (typeof node !== 'object') return String(node);
	const own = node._text || '';
	const inner = (node.children || []).map(render).join('');
	return own + inner;
}

// A <dl> is a flat list of <dt>/<dd>; turn it back into an ordered map so a test
// can assert one row without depending on the overall row order.
function facts(node) {
	const rows = [];
	let pending = null;
	for (const child of node.children || []) {
		if (typeof child !== 'object') continue;
		if (child.tagName === 'DT') pending = render(child);
		else if (child.tagName === 'DD' && pending != null) { rows.push([pending, render(child)]); pending = null; }
	}
	return rows;
}

function row(node, label) {
	const found = facts(node).filter(([key]) => key === label);
	return found.length ? found[0][1] : null;
}

// --- LuCI stand-ins --------------------------------------------------------

const FORM_TYPES = { Flag: 'flag', Value: 'value', ListValue: 'listvalue', NamedSection: 'namedsection' };

function createForm() {
	class FakeMap {
		constructor() { this.sections = []; }
		section(type, id, kind, title) {
			const record = {
				id, kind, title, addremove: true, options: [],
				option(optionType, name, label, description) {
					const option = { type: optionType, name, label, description, values: [], rmempty: true, validate: null, placeholder: null };
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
	return { Map: FakeMap, ...FORM_TYPES };
}

function createUci(devices) {
	const main = { enabled: '1', interface: 'br-lan', airupnp: '1', aircast: '1', max_volume: '100', media_volume: '0.5' };
	return {
		load: () => Promise.resolve(),
		get(name, sectionId, key) {
			if (sectionId === 'main') return key == null ? main : (main[key] ?? null);
			return null;
		},
		set() { }, unset() { }, add() { return 'demo'; },
		sections(name, type, callback) {
			const list = devices.filter((device) => device['.type'] === type);
			if (callback) list.forEach(callback);
			return list;
		},
		save: () => Promise.resolve()
	};
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

// Build a rendered view instance and push one status reply through it. Returns
// the instance so a test can read its diagnostics list and device cards.
async function renderStatus(status) {
	let resolveStatus;
	const statusPromise = new Promise((resolve) => { resolveStatus = resolve; });
	const rpc = {
		declare(spec) {
			if (spec.method === 'status') return () => statusPromise;
			return () => Promise.resolve({});
		}
	};
	const instance = loadView({
		uci: createUci([{
			'.name': 'cfg_demo', '.type': 'device', engine: 'upnp',
			udn: 'uuid:demo-1', enabled: '1', name: ''
		}]),
		form: createForm(),
		rpc,
		ui: { addNotification() { }, changes: { init: () => Promise.resolve(), apply: () => Promise.resolve() } },
		poll: { add() { }, remove() { }, start() { }, stop() { } },
		L: { bind: (fn, context) => fn.bind(context), resource: (path) => path },
		rules: { airplayName: () => true, upnpVolume: () => true, castVolume: () => true, latency: () => true, interfaceValue: () => true, logLevel: () => true }
	});
	// render() wires the panel nodes and then calls updateStatus with the loaded
	// reply. Passing the status through the load promise is what makes the real
	// code path run, rather than calling updateStatus directly with a hand object.
	const node = await instance.render([{}, { data: null }]);
	resolveStatus(status);
	await new Promise((resolve) => setImmediate(resolve));
	// The view stores its last reply, which is also what updateDevice reads for
	// the observation timestamp.
	instance.updateStatus(status);
	return { instance, node };
}

function baseStatus(overrides) {
	return Object.assign({
		enabled: true,
		interface: 'br-lan',
		version: '0.1.0-test',
		services: {
			upnp: { enabled: true, running: true, broadcasting: null },
			cast: { enabled: false, running: false, broadcasting: null }
		},
		scan: { running: false, last_scan: 1700000000, error: null },
		broadcast: { observed_at: null, error: null },
		playback: { known: false, reason: 'no documented engine status API' },
		conflicts: [],
		devices: [{
			engine: 'upnp', udn: 'uuid:demo-1', original_name: 'Demo Speaker',
			name: null, model: 'Demo Model', manufacturer: 'Demo Manufacturer',
			address: '192.0.2.10', last_seen: 1700000000, online: true, configured: true,
			broadcasting: null
		}]
	}, overrides);
}

const BROADCAST_UPNP = 'AirPlay broadcast (UPnP)';
const BROADCAST_CAST = 'AirPlay broadcast (Chromecast)';

// --- assertions ------------------------------------------------------------

async function main() {
	section('an unmeasured broadcast renders as unknown, never as a positive');
	{
		const { instance } = await renderStatus(baseStatus());
		const text = row(instance.diagnosticFacts, BROADCAST_UPNP);
		check(text != null, 'the UPnP broadcast row exists');
		check(/Unknown/.test(text), 'the row says Unknown', text);
		check(!/^Yes/.test(text), 'the row does not start with a positive', text);
		// It must also explain what would make the state knowable.
		check(/mDNS/.test(text), 'the row names the measurement that is missing', text);
		// And the per-device badge must agree.
		const badgeText = render(instance.cards['upnp\nuuid:demo-1'].status);
		check(/AirPlay broadcast unknown/.test(badgeText), 'the device badge is unknown', badgeText);
	}

	section('a measured positive shows the value and the observation time');
	{
		const { instance } = await renderStatus(baseStatus({
			services: {
				upnp: { enabled: true, running: true, broadcasting: true },
				cast: { enabled: false, running: false, broadcasting: false }
			},
			broadcast: { observed_at: 1700000000, error: null },
			devices: [Object.assign({}, baseStatus().devices[0], { broadcasting: true })]
		}));
		const upnp = row(instance.diagnosticFacts, BROADCAST_UPNP);
		const cast = row(instance.diagnosticFacts, BROADCAST_CAST);
		check(/^Yes/.test(upnp), 'the UPnP row is a positive', upnp);
		check(/observed/.test(upnp), 'the row carries an observation time', upnp);
		// A measured negative is NOT unknown and must not read as a positive.
		check(/^No/.test(cast), 'the Chromecast row is a measured negative', cast);
		check(!/Unknown/.test(cast), 'a measured negative is not Unknown', cast);
		const badgeText = render(instance.cards['upnp\nuuid:demo-1'].status);
		check(/AirPlay advertised/.test(badgeText), 'the device badge is positive', badgeText);
		const deviceRow = row(instance.cards['upnp\nuuid:demo-1'].facts, 'AirPlay broadcast');
		check(/^Yes/.test(deviceRow), 'the device row is a positive', deviceRow);
		check(/observed/.test(deviceRow), 'the device row carries the observation time', deviceRow);
	}

	section('a measured negative is a value, not Unknown');
	{
		const { instance } = await renderStatus(baseStatus({
			services: {
				upnp: { enabled: true, running: true, broadcasting: false },
				cast: { enabled: false, running: false, broadcasting: null }
			},
			broadcast: { observed_at: 1700000000, error: null },
			devices: [Object.assign({}, baseStatus().devices[0], { broadcasting: false })]
		}));
		const upnp = row(instance.diagnosticFacts, BROADCAST_UPNP);
		check(/^No/.test(upnp), 'the row is a negative', upnp);
		check(/scan found no advertisement/.test(upnp), 'the row says the scan ran', upnp);
		const badgeText = render(instance.cards['upnp\nuuid:demo-1'].status);
		check(/No AirPlay advertisement/.test(badgeText), 'the device badge is a negative', badgeText);
	}

	section('a failed observation is unknown and shows why');
	{
		const { instance } = await renderStatus(baseStatus({
			broadcast: { observed_at: 1700000000, error: 'no reply' },
			devices: [Object.assign({}, baseStatus().devices[0], { broadcasting: null })]
		}));
		const text = row(instance.diagnosticFacts, BROADCAST_UPNP);
		check(/Unknown/.test(text), 'a failed observation is Unknown', text);
		check(/no reply/.test(text), 'the failure reason is shown', text);
	}

	section('playback is never implied by a broadcast positive');
	{
		const { instance } = await renderStatus(baseStatus({
			services: {
				upnp: { enabled: true, running: true, broadcasting: true },
				cast: { enabled: false, running: false, broadcasting: true }
			},
			broadcast: { observed_at: 1700000000, error: null },
			devices: [Object.assign({}, baseStatus().devices[0], { broadcasting: true })]
		}));
		const playback = row(instance.diagnosticFacts, 'Playback');
		check(playback != null, 'the Playback row exists');
		check(/^Unknown/.test(playback), 'playback stays Unknown while broadcasting is true', playback);
		check(/never inferred/.test(playback), 'the row says it is not inferred from broadcast', playback);
		// The two rows must be distinguishable text, not the same string.
		check(playback !== row(instance.diagnosticFacts, BROADCAST_UPNP),
			'playback and broadcast are not the same string');
	}

	section('playback is the same constant whatever the broadcast state');
	{
		const texts = [];
		for (const value of [null, true, false]) {
			const { instance } = await renderStatus(baseStatus({
				services: {
					upnp: { enabled: true, running: true, broadcasting: value },
					cast: { enabled: false, running: false, broadcasting: value }
				},
				broadcast: { observed_at: value === null ? null : 1700000000, error: null }
			}));
			texts.push(row(instance.diagnosticFacts, 'Playback'));
		}
		check(texts[0] === texts[1] && texts[1] === texts[2],
			'playback does not change with the broadcast state', JSON.stringify(texts));
	}

	section('service running is not rendered as broadcasting');
	{
		const { instance } = await renderStatus(baseStatus({
			services: {
				upnp: { enabled: true, running: true, broadcasting: null },
				cast: { enabled: true, running: true, broadcasting: null }
			}
		}));
		check(/Running/.test(render(instance.serviceStatus)), 'the service badge says Running');
		check(/Unknown/.test(row(instance.diagnosticFacts, BROADCAST_UPNP)),
			'a running service does not make the broadcast row positive');
	}

	section('discovered is not rendered as broadcasting');
	{
		const { instance } = await renderStatus(baseStatus({
			devices: [Object.assign({}, baseStatus().devices[0], { online: true, broadcasting: null })]
		}));
		const badgeText = render(instance.cards['upnp\nuuid:demo-1'].status);
		check(/Discovered/.test(badgeText), 'the device is discovered', badgeText);
		check(/AirPlay broadcast unknown/.test(badgeText),
			'being discovered does not make it broadcast', badgeText);
	}

	console.log(`\n${passed} passed; ${failed} failed`);
	process.exit(failed === 0 ? 0 : 1);
}

main().catch((error) => {
	console.error('not ok - the suite threw: ' + (error && error.stack ? error.stack : error));
	process.exit(1);
});
