#!/usr/bin/env node
// SPDX-License-Identifier: MIT
// The polling contract of the LuCI view.
//
//   node tests/performance/poll-contract.mjs
//
// docs/PERFORMANCE.zh-CN.md and docs/ARCHITECTURE.zh-CN.md both promise, in
// prose, that the page polls every 10 seconds, pauses while the tab is hidden,
// never has two requests in flight, backs off to 60 seconds after repeated
// failures, and does not repaint the form when a status reply arrives. Those are
// the four claims that decide whether opening a second tab doubles the router's
// RPC load, and until now nothing executed them.
//
// This file loads the real, unmodified production view
// (packages/luci-app-airconnect-manager/htdocs/luci-static/resources/view/airconnect-manager/overview.js)
// through the same `new Function` module shim tests/parity/check-frontend.mjs
// uses, and drives its polling entry point with fake `rpc`, `uci`, `poll`,
// `form`, `E` and `document` objects. There is no browser, no LuCI, no npm
// dependency and no network access.
//
// What is deliberately NOT asserted here: that a real browser honours
// document.hidden (that is the browser's contract), that a real LuCI loads the
// view, or what an RPC costs. This suite proves the view's own decisions, which
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

// --- a DOM shim ------------------------------------------------------------
//
// Only what the view touches. The one property that is not merely a container
// is `writes`: every mutation records itself, so a test can prove that a code
// path did not write to a node at all. That is how "a status update never
// repaints the form" becomes an assertion instead of a comment.

const FORM_CONTROLS = new Set(['INPUT', 'SELECT', 'TEXTAREA']);

class FakeNode {
	constructor(tag) {
		this.tagName = String(tag).toUpperCase();
		this.children = [];
		this.attributes = new Map();
		this.listeners = new Map();
		this.dataset = Object.create(null);
		this.writes = [];
		this.tabIndex = 0;
		this._text = '';
		this._class = '';
		this._value = '';
		this._hidden = false;
		this._disabled = false;
		this._checked = false;
	}

	get isFormControl() { return FORM_CONTROLS.has(this.tagName); }

	get textContent() { return this._text; }
	set textContent(value) {
		this._text = value == null ? '' : String(value);
		this.children = [];
		this.writes.push('textContent');
	}

	get className() { return this._class; }
	set className(value) { this._class = String(value); this.writes.push('className'); }

	get value() { return this._value; }
	set value(value) { this._value = String(value); this.writes.push('value'); }

	get checked() { return this._checked; }
	set checked(value) { this._checked = !!value; this.writes.push('checked'); }

	get hidden() { return this._hidden; }
	set hidden(value) { this._hidden = !!value; this.writes.push('hidden'); }

	get disabled() { return this._disabled; }
	set disabled(value) { this._disabled = !!value; this.writes.push('disabled'); }

	setAttribute(name, value) {
		this.attributes.set(name, String(value));
		this.writes.push('setAttribute:' + name);
	}

	removeAttribute(name) {
		this.attributes.delete(name);
		this.writes.push('removeAttribute:' + name);
	}

	getAttribute(name) {
		return this.attributes.has(name) ? this.attributes.get(name) : null;
	}

	addEventListener(type, fn) { this.listeners.set(type, fn); }
	removeEventListener(type) { this.listeners.delete(type); }
	focus() { }
	blur() { }

	appendChild(node) {
		this.children.push(node);
		this.writes.push('appendChild');
		return node;
	}

	append(...nodes) {
		for (const node of nodes) this.appendChild(node);
	}

	replaceChildren(...args) {
		const kept = [];
		for (const item of args.flat()) {
			if (item == null || item === false) continue;
			kept.push(typeof item === 'object' ? item : String(item));
		}
		this.children = kept;
		this._text = '';
		this.writes.push('replaceChildren');
	}

	click() {
		const handler = this.listeners.get('click');
		if (handler) handler({ preventDefault() { }, key: '' });
	}
}

// LuCI's element helper: `E(tag, attrs, children)`. A function attribute is a
// listener, `true` is a boolean attribute, null/false/undefined are dropped.
function E(tag, attrs, children) {
	const node = new FakeNode(tag);
	for (const [key, value] of Object.entries(attrs || {})) {
		if (typeof value === 'function') node.listeners.set(key, value);
		else if (key === 'hidden' || key === 'disabled' || key === 'checked') node[key] = value === true || value === '';
		else if (value === true) node.setAttribute(key, '');
		else if (value === false || value === null || value === undefined) continue;
		else if (key === 'class') node.className = String(value);
		else if (key === 'value') node.value = String(value);
		else node.setAttribute(key, value);
	}
	const add = (child) => {
		if (child === null || child === undefined || child === false) return;
		if (Array.isArray(child)) { child.forEach(add); return; }
		node.appendChild(child instanceof FakeNode ? child : String(child));
	};
	add(children);
	// Child construction is not a later mutation: reset the log so `writes`
	// means "something wrote to this node after it was built".
	return node;
}

function collectControls(node, out = []) {
	if (!node || typeof node !== 'object') return out;
	if (node.isFormControl) out.push(node);
	for (const child of node.children || []) collectControls(child, out);
	return out;
}

// --- the LuCI stand-ins ----------------------------------------------------

const FORM_TYPES = { Flag: 'flag', Value: 'value', ListValue: 'listvalue', NamedSection: 'namedsection' };

function createUci(data) {
	const configName = 'airconnect-manager';
	return {
		loaded: 0,
		load() { this.loaded++; return Promise.resolve(); },
		get(name, section, key) {
			const target = section === 'main' ? data.main : data.section(section);
			if (!target) return null;
			return key === undefined ? target : (target[key] ?? null);
		},
		set() { },
		unset() { },
		add() { return 'new-section'; },
		save() { return Promise.resolve(); },
		sections(name, type, callback) {
			const list = type === 'device' ? data.devices : [];
			if (callback) list.forEach(callback);
			return list;
		}
	};
}

// A form.Map stand-in that produces real FakeNodes with real INPUT/SELECT
// controls, because the assertion about form values is only meaningful when
// there is a form to touch.
function createForm() {
	class FakeMap {
		constructor(config) { this.config = config; this.sections = []; }

		section(type, id, kind, title) {
			const section = {
				id,
				kind,
				title,
				addremove: true,
				options: [],
				option(optionType, name, label, description) {
					const option = { type: optionType, name, label, description, values: [], rmempty: true };
					option.value = (value, text) => { option.values.push([value, text]); return option; };
					section.options.push(option);
					return option;
				}
			};
			this.sections.push(section);
			return section;
		}

		render() {
			const node = E('div', { 'class': 'cbi-map' });
			for (const section of this.sections) {
				const fieldset = E('fieldset', { 'class': 'cbi-section' });
				if (section.title) fieldset.appendChild(E('legend', {}, section.title));
				for (const option of section.options) {
					const id = 'field-' + section.id + '-' + option.name;
					let control;
					if (option.type === FORM_TYPES.Flag) {
						control = E('input', { type: 'checkbox', id });
					}
					else if (option.type === FORM_TYPES.ListValue) {
						control = E('select', { id });
						for (const [value, text] of option.values)
							control.appendChild(E('option', { value }, text));
					}
					else {
						control = E('input', { type: 'text', id, value: option.current ?? '' });
					}
					const error = E('div', { 'class': 'cbi-input-error', role: 'alert' });
					const row = E('div', { 'class': 'cbi-value' }, [
						E('label', { 'class': 'cbi-value-title', for: id }, option.label),
						E('div', { 'class': 'cbi-value-field' }, [control, error])
					]);
					fieldset.appendChild(row);
				}
				node.appendChild(fieldset);
			}
			// Constructing the controls is not a write; only a later mutation is.
			for (const control of collectControls(node)) control.writes.length = 0;
			return Promise.resolve(node);
		}

		parse() { return Promise.resolve(); }
	}
	return { Map: FakeMap, ...FORM_TYPES };
}

function createRpc() {
	const calls = { status: 0, logs: 0, scan: 0, validate: 0, action: 0 };
	const handlers = {};
	const rpc = {
		declare(spec) {
			return function () {
				calls[spec.method]++;
				const handler = handlers[spec.method];
				return handler ? handler.apply(null, arguments) : Promise.resolve({});
			};
		}
	};
	return { rpc, calls, handlers };
}

function createPoll() {
	const registrations = [];
	return {
		registrations,
		poll: {
			add(fn, seconds) { registrations.push({ fn, seconds }); return String(registrations.length); },
			remove() { },
			start() { },
			stop() { }
		}
	};
}

function statusPayload(overrides = {}) {
	return {
		enabled: true,
		interface: 'br-lan',
		version: '0.1.0-test',
		services: { upnp: { enabled: true, running: true }, cast: { enabled: false, running: false } },
		scan: { running: false, last_scan: 1700000000, error: null },
		conflicts: [],
		devices: [{
			engine: 'upnp', udn: 'uuid:demo-1', original_name: 'Demo Speaker',
			name: null, model: 'Demo Model', manufacturer: 'Demo Manufacturer',
			address: '192.0.2.10', last_seen: 1700000000, online: true, configured: false
		}],
		...overrides
	};
}

// --- loading the production view -------------------------------------------

function loadView(env) {
	const source = readFileSync(VIEW_PATH, 'utf8');
	const factory = new Function(
		'view', 'form', 'uci', 'rpc', 'ui', 'poll', 'L', 'E', '_', 'rules',
		source + '\nreturn view.extend({});\n');
	const instance = factory(
		{ extend: (definition) => definition },
		env.form,
		env.uci,
		env.rpc,
		env.ui,
		env.poll,
		env.L,
		E,
		(text) => text,
		env.rules
	);
	if (instance == null || typeof instance.refresh !== 'function')
		throw new Error('overview.js did not return a view with a refresh method');
	return instance;
}

// rules.js is a LuCI class factory, not a module with exports: LuCI's `require`
// demands `Class.isSubclass(factory())` and then instantiates it, so this builds
// the class through the same minimal `L.Class` shim as
// tests/parity/check-frontend.mjs and returns the instance LuCI would hand the
// view - a stub of this test's own making would hide a broken contract.
function LuCIBaseClass() {}

LuCIBaseClass.extend = function(properties) {
	const Subclass = function() {};
	Subclass.prototype = Object.create(LuCIBaseClass.prototype);
	for (const name of Object.keys(properties))
		Subclass.prototype[name] = properties[name];
	Subclass.extend = LuCIBaseClass.extend;
	return Subclass;
};

const LUCI = { Class: LuCIBaseClass };

function loadRules() {
	const source = readFileSync(join(ROOT,
		'packages/luci-app-airconnect-manager/htdocs/luci-static/resources/airconnect-manager/rules.js'), 'utf8');
	const Rules = new Function('_', 'L', source)((text) => text, LUCI);
	if (typeof Rules !== 'function' || !(Rules.prototype instanceof LUCI.Class))
		throw new Error('rules.js did not return a LuCI class; the router would abort the view');
	return new Rules();
}

// Every scenario gets its own instance, its own fake RPC and its own fake clock.
//
// The clock and `document` are process-wide because the view reads the bare
// globals `Date.now` and `document`; they are installed once, at module load,
// and resolve through `ACTIVE`, the controller of the scenario currently being
// driven. That keeps a deterministic clock available to every later call of a
// poll callback, which is what makes the backoff assertion exact instead of
// timing-dependent.
let ACTIVE = null;

const REAL_NOW = Date.now;
const realDocument = globalThis.document;

Date.now = function now() {
	return ACTIVE ? ACTIVE.clock : REAL_NOW();
};

globalThis.document = {
	get hidden() { return ACTIVE ? ACTIVE.hidden : false; },
	set hidden(value) { if (ACTIVE) ACTIVE.hidden = !!value; },
	addEventListener() { },
	removeEventListener() { }
};

globalThis.window = globalThis.window || { location: { reload() { } } };

async function scenario(setup = {}) {
	const controller = {
		clock: 1_700_000_000_000,
		hidden: false,
		notifications: []
	};

	const data = {
		main: {
			enabled: '1', interface: 'br-lan', airupnp: '1', aircast: '0', codec: 'flac',
			latency: '1000:2000', max_volume: '100', media_volume: '0.5', log_level: 'warn'
		},
		devices: [{
			'.name': 'cfg_demo', '.type': 'device', engine: 'upnp', udn: 'uuid:demo-1',
			enabled: '1', name: ''
		}],
		// A device section is looked up by its UCI name, not by position, because
		// the view builds one form per stored speaker via findSection().
		section(name) { return this.devices.find((entry) => entry['.name'] === name) || null; }
	};

	const uci = createUci(data);
	const rpcBundle = createRpc();
	const pollBundle = createPoll();
	const ui = {
		addNotification(title, node) { controller.notifications.push(node); return node; },
		changes: { init: () => Promise.resolve(), apply: () => Promise.resolve() }
	};
	const L = {
		bind: (fn, context) => fn.bind(context),
		resource: (path) => '/luci-static/resources/' + path
	};

	rpcBundle.handlers.status = setup.status || (() => Promise.resolve(statusPayload()));
	rpcBundle.handlers.logs = () => Promise.resolve({ lines: [], truncated: false });
	rpcBundle.handlers.scan = () => Promise.resolve({ ok: true, running: true });
	rpcBundle.handlers.validate = () => Promise.resolve({ ok: true, errors: [] });
	rpcBundle.handlers.action = () => Promise.resolve({ ok: true });

	const env = {
		uci,
		rpc: rpcBundle.rpc,
		poll: pollBundle.poll,
		ui,
		L,
		form: createForm(),
		rules: loadRules()
	};

	const instance = loadView(env);
	ACTIVE = controller;
	const loaded = await instance.load();
	const node = await instance.render(loaded);
	// The view starts several forms asynchronously; let those promises settle
	// before anything is measured.
	await new Promise((done) => setImmediate(done));
	return { instance, node, controller, calls: rpcBundle.calls, handlers: rpcBundle.handlers, Poll: pollBundle };
}

// --- assertions ------------------------------------------------------------

async function main() {
	// --- the interval ------------------------------------------------------
	section('poll interval');
	const base = await scenario();
	check(base.Poll.registrations.length === 1,
		'the view registers exactly one poll', String(base.Poll.registrations.length));

	const registration = base.Poll.registrations[0];
	// LuCI's poll.add(interval) takes SECONDS; the design target is 10 seconds,
	// which is 10000 ms on the wire timer.
	check(registration != null && registration.seconds === 10,
		'the poll interval is 10 seconds (10000 ms)',
		registration ? registration.seconds + ' s = ' + registration.seconds * 1000 + ' ms' : 'no registration');
	check(registration != null && registration.seconds * 1000 === 10000,
		'the poll interval is exactly 10000 ms',
		registration ? String(registration.seconds * 1000) : 'no registration');
	// The registered callback must already carry the view as its receiver: LuCI
	// calls it as a bare function, and a lost `this` would make every tick throw.
	check(registration != null && typeof registration.fn === 'function',
		'the poll callback is a function');
	let boundOk = true;
	try {
		registration.fn();
	}
	catch (error) {
		boundOk = false;
	}
	check(boundOk, 'the poll callback is bound to the view and runs without a receiver');
	await new Promise((done) => setImmediate(done));

	// --- hidden tab --------------------------------------------------------
	section('hidden tab');
	const hidden = await scenario();
	const beforeHidden = hidden.calls.status;
	hidden.controller.hidden = true;
	await hidden.Poll.registrations[0].fn();
	check(hidden.calls.status === beforeHidden,
		'a refresh is skipped while document.hidden is true',
		'status calls went from ' + beforeHidden + ' to ' + hidden.calls.status);
	// Twice, so the skip is a decision and not a one-off guard.
	await hidden.Poll.registrations[0].fn();
	check(hidden.calls.status === beforeHidden, 'a second hidden refresh is also skipped',
		String(hidden.calls.status));
	// Becoming visible again must resume polling, or the page would stay stale
	// forever after the user returns to the tab.
	hidden.controller.hidden = false;
	await hidden.Poll.registrations[0].fn();
	check(hidden.calls.status === beforeHidden + 1,
		'a visible refresh polls again', String(hidden.calls.status));

	// --- serialized requests ----------------------------------------------
	section('one request in flight');
	// The view's own load() consumes the first status call, so the deferred is
	// armed for the second call - the one the poll under test makes.
	let release = null;
	let served = 0;
	const busy = await scenario({
		status: () => {
			served++;
			// Only the second call - the one the poll under test makes - is held
			// open; load() and every later call resolve immediately.
			if (served !== 2) return Promise.resolve(statusPayload());
			return new Promise((resolve) => { release = resolve; });
		}
	});
	check(served === 1, 'load() consumed exactly one status call', String(served));
	const afterFirst = busy.calls.status;
	const inFlight = busy.Poll.registrations[0].fn();
	check(busy.calls.status === afterFirst + 1,
		'the poll under test made its request', String(busy.calls.status));
	const second = busy.Poll.registrations[0].fn();
	check(busy.calls.status === afterFirst + 1,
		'a second refresh is skipped while one is in flight',
		'status calls: ' + (afterFirst + 1) + ' -> ' + busy.calls.status);
	await second;
	check(typeof release === 'function', 'the in-flight request is still pending', String(typeof release));
	release(statusPayload());
	await inFlight;
	const afterSettled = busy.calls.status;
	await busy.Poll.registrations[0].fn();
	check(busy.calls.status === afterSettled + 1,
		'polling resumes once the in-flight request settles', String(busy.calls.status));

	// --- backoff -----------------------------------------------------------
	section('backoff after repeated failures');
	let failNow = true;
	const failing = await scenario({
		status: () => failNow ? Promise.reject(new Error('rpc unavailable')) : Promise.resolve(statusPayload())
	});
	const view = failing.instance;
	const expectedDelays = [10000, 20000, 40000, 60000, 60000];
	const observedDelays = [];
	for (let attempt = 0; attempt < expectedDelays.length; attempt++) {
		// Advance the clock past the previous backoff, which is what a real page
		// does between two poll ticks. Without this the second iteration would be
		// skipped by the previous delay and only prove the guard, not the growth.
		if (attempt > 0) failing.controller.clock += expectedDelays[attempt - 1];
		const before = failing.calls.status;
		await failing.Poll.registrations[0].fn();
		check(failing.calls.status === before + 1,
			'failure ' + (attempt + 1) + ' actually made a request', String(failing.calls.status));
		observedDelays.push(view.nextRetry - failing.controller.clock);
	}
	check(JSON.stringify(observedDelays) === JSON.stringify(expectedDelays),
		'the delay doubles and stops at 60000 ms',
		'observed ' + JSON.stringify(observedDelays));
	check(observedDelays.every((delay) => delay <= 60000),
		'no delay exceeds 60000 ms', JSON.stringify(observedDelays));
	for (let index = 1; index < observedDelays.length; index++) {
		if (observedDelays[index] < observedDelays[index - 1])
			check(false, 'the delay never shrinks while failures continue', JSON.stringify(observedDelays));
	}

	// The delay must actually suppress requests, not just be recorded.
	const beforeWait = failing.calls.status;
	failing.controller.clock += 60000 - 1;
	await failing.Poll.registrations[0].fn();
	check(failing.calls.status === beforeWait,
		'no request is made before the backoff expires', String(failing.calls.status));
	failing.controller.clock += 1;
	await failing.Poll.registrations[0].fn();
	check(failing.calls.status === beforeWait + 1,
		'a request resumes when the backoff expires', String(failing.calls.status));

	// A success must clear the failure count, or one outage would leave the page
	// on the 60 second timer for the rest of the session.
	failNow = false;
	failing.controller.clock += 60000;
	await failing.Poll.registrations[0].fn();
	check(view.failures === 0, 'a successful refresh resets the failure count', String(view.failures));
	check(typeof view.lastSuccess === 'number' && view.lastSuccess === failing.controller.clock,
		'a successful refresh records the last success time', String(view.lastSuccess));
	const afterRecovery = failing.calls.status;
	await failing.Poll.registrations[0].fn();
	check(failing.calls.status === afterRecovery + 1,
		'polling is immediate again after recovery', String(failing.calls.status));

	// --- updateStatus never repaints the form ------------------------------
	section('status updates leave the form alone');
	const formScenario = await scenario();
	const controlsBefore = collectControls(formScenario.node);
	check(controlsBefore.length > 0,
		'the rendered page contains form controls to protect', String(controlsBefore.length));
	// A form control is only worth protecting if the values are real, so the
	// snapshot records the value and the number of writes at the time of render.
	const snapshot = controlsBefore.map((control) => ({
		control,
		value: control.value,
		checked: control.checked,
		writes: control.writes.length
	}));

	// Three replies that differ in every field a status update renders: service
	// state, conflicts, the scan block, and the discovered device facts.
	formScenario.instance.updateStatus(statusPayload({
		services: { upnp: { enabled: true, running: false }, cast: { enabled: true, running: true } },
		conflicts: ['Legacy binaries found in /usr/bin.'],
		scan: { running: true, last_scan: 1700000100, error: null },
		devices: [{
			engine: 'upnp', udn: 'uuid:demo-1', original_name: 'Demo Speaker',
			name: 'Kitchen', model: 'Other Model', manufacturer: 'Other Manufacturer',
			address: '192.0.2.99', last_seen: 1700000200, online: false, configured: true
		}]
	}));
	formScenario.instance.updateStatus(statusPayload({
		services: { upnp: { enabled: false, running: false }, cast: { enabled: false, running: false } },
		scan: { running: false, last_scan: 1700000300, error: 'Discovery timed out' },
		devices: []
	}));
	await new Promise((done) => setImmediate(done));

	const controlsAfter = collectControls(formScenario.node);
	check(controlsAfter.length === controlsBefore.length,
		'the status updates did not replace any form control',
		controlsBefore.length + ' -> ' + controlsAfter.length);

	let touched = 0;
	const details = [];
	for (const item of snapshot) {
		if (!controlsAfter.includes(item.control)) {
			touched++;
			details.push('control replaced');
			continue;
		}
		const newWrites = item.control.writes.slice(item.writes);
		if (newWrites.length !== 0) {
			touched++;
			details.push('wrote ' + newWrites.join(',') + ' to #' + item.control.getAttribute('id'));
		}
		if (item.control.value !== item.value) {
			touched++;
			details.push('value changed on #' + item.control.getAttribute('id'));
		}
		if (item.control.checked !== item.checked) {
			touched++;
			details.push('checked changed on #' + item.control.getAttribute('id'));
		}
	}
	check(touched === 0, 'updateStatus never writes to any input element', details.join('; '));
	console.log('#   ' + controlsBefore.length + ' form controls, 0 writes from 2 status updates');

	// The assertion above is only worth something if it can fail. Deliberately
	// write to a control and confirm the same comparison reports it, so a future
	// refactor cannot quietly turn this test into a no-op.
	const canary = controlsBefore[0];
	const canaryWrites = canary.writes.length;
	canary.value = 'mutated';
	const detectorSaw = canary.writes.length !== canaryWrites;
	check(detectorSaw, 'the untouched-input assertion can detect a write (self-check)',
		'the shim did not record a mutation');

	console.log('');
	console.log(passed + ' passed; ' + failed + ' failed');
	process.exitCode = failed === 0 ? 0 : 1;
}

try {
	await main();
}
catch (error) {
	console.error('poll-contract: ' + (error && error.stack ? error.stack : error));
	process.exitCode = 1;
}
