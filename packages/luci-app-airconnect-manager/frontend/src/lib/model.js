/**
 * Derived page state: which speakers to show, what their effective AirPlay name
 * is, and which names collide.
 *
 * These are pure functions of three inputs - the last status reply, the UCI
 * device sections and the values the user has typed - so the app never has to
 * derive them from the DOM, and the test suite can drive them directly.
 *
 * The `values` maps are read, never written: a status reply must not overwrite
 * what the user is editing.
 */

import { DEVICE_KEYS, MAIN_KEYS } from './config.js';

const ENGINES = ['upnp', 'cast'];

/** The engines strip trailing whitespace before publishing a name. */
export function trimTrailing(value) {
	return value == null ? '' : String(value).replace(/\s+$/, '');
}

/** Read the current main values and every device section from a uci-like handle. */
export function readState(access) {
	const main = {};
	for (const key of MAIN_KEYS) {
		const item = access.get('main', key);
		if (item != null) main[key] = item;
	}
	const devices = {};
	const sections = [];
	access.sections('device', (section) => {
		sections.push({
			name: section['.name'],
			engine: section.engine,
			udn: section.udn,
			removed: !!section['.removed']
		});
		const values = {};
		for (const key of DEVICE_KEYS) {
			if (section[key] != null) values[key] = section[key];
		}
		devices[section['.name']] = values;
	});
	return { main, devices, sections };
}

/** engine + newline + udn, the identity a speaker keeps across a rename. */
export function deviceKey(engine, udn) {
	return engine + '\n' + udn;
}

/**
 * The AirPlay name each configured speaker will broadcast: an explicit override,
 * otherwise the name discovery reported. A speaker with neither has nothing to
 * collide on and is skipped.
 */
export function effectiveNames(state) {
	const discovered = Object.create(null);
	for (const device of (state.status && state.status.devices) || []) {
		if (device && device.udn) discovered[deviceKey(device.engine, device.udn)] = device.original_name;
	}
	const names = [];
	for (const item of state.configured) {
		if (item.removed) continue;
		const values = state.deviceValues[item.name] || {};
		const name = trimTrailing(values.name) ||
			trimTrailing(discovered[deviceKey(item.engine, item.udn)]);
		if (name !== '') names.push(name);
	}
	return names;
}

/**
 * Names used by more than one speaker, in the order they were first seen.
 * `Object.create(null)` keeps a speaker named "constructor" or "__proto__" an
 * ordinary key instead of a prototype lookup.
 */
export function duplicateNames(state) {
	const counts = Object.create(null);
	const order = [];
	const duplicates = [];
	for (const name of effectiveNames(state)) {
		if (counts[name] === undefined) {
			counts[name] = 1;
			order.push(name);
		} else {
			counts[name] = counts[name] + 1;
		}
	}
	for (const name of order) {
		if (counts[name] > 1) duplicates.push(name);
	}
	return duplicates;
}

/**
 * The speaker list: everything discovery reported, then every configured speaker
 * discovery has not (yet) reported, each carrying the section that overrides it.
 */
export function mergeDevices(state) {
	const list = [];
	const seen = new Set();
	for (const device of (state.status && state.status.devices) || []) {
		if (!device || !device.udn) continue;
		if (ENGINES.indexOf(device.engine) < 0) continue;
		const section = state.configured.find(
			(item) => item.engine === device.engine && item.udn === device.udn);
		seen.add(deviceKey(device.engine, device.udn));
		list.push(Object.assign({}, device, { section: section ? section.name : null }));
	}
	for (const item of state.configured) {
		if (item.removed) continue;
		if (!item.udn || ENGINES.indexOf(item.engine) < 0) continue;
		const key = deviceKey(item.engine, item.udn);
		if (seen.has(key)) continue;
		const values = state.deviceValues[item.name] || {};
		list.push({
			engine: item.engine,
			udn: item.udn,
			name: values.name,
			original_name: null,
			online: false,
			configured: true,
			section: item.name
		});
	}
	return list;
}
