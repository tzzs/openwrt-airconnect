#!/usr/bin/env node
// SPDX-License-Identifier: MIT
// Frontend half of the validation parity contract.
//
//   node tests/parity/check-frontend.mjs
//
// Imports the frontend rule module (frontend/src/lib/rules.js, the module the
// React app validates with) and runs every case from cases.json through it,
// comparing the result with the verdicts the real backend produced in
// tests/parity/run.uc.
//
// The backend verdicts are not re-implemented here on purpose: this file shells
// out to `ucode tests/parity/run.uc --verdicts`, so there is exactly one
// authority for what config.uc accepts. Exit status is nonzero when the frontend
// and the backend disagree, or when the ucode runner cannot be executed.

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');
const CASES_PATH = join(HERE, 'cases.json');
const RULES_URL = new URL(
	'../../packages/luci-app-airconnect-manager/frontend/src/lib/rules.js',
	import.meta.url);

// `field` in cases.json -> exported rule in rules.js.
const RULES = {
	interface: 'interfaceValue',
	log_level: 'logLevel',
	latency: 'latency',
	max_volume: 'upnpVolume',
	media_volume: 'castVolume',
	name: 'airplayName',
	metadata: 'binaryFlag',
	flush: 'binaryFlag',
	drift: 'binaryFlag',
	stop_receiver: 'binaryFlag',
	http_length: 'httpLength',
	upnp_max: 'upnpMax',
	artwork: 'artwork'
};

const UCODE = process.env.UCODE || join(process.env.HOME || '', '.local/opt/ucode-host/bin/ucode');
const UCODE_LIB = process.env.UCODE_LIB || join(process.env.HOME || '', '.local/opt/ucode-host/lib/ucode');

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

// The rule module is a plain ES module, so it is imported rather than evaluated:
// `createRules(t)` returns the same ten functions for any translation helper, and
// calling it with none leaves the messages in English.
const { createRules } = await import(RULES_URL);

function loadRules(translate) {
	return createRules(translate ? function (s) { return s; } : undefined);
}

function backendVerdicts() {
	let raw;
	try {
		raw = execFileSync(UCODE, ['-L', UCODE_LIB, join(HERE, 'run.uc'), '--verdicts'], {
			cwd: ROOT,
			encoding: 'utf8',
			stdio: ['ignore', 'pipe', 'pipe']
		});
	}
	catch (error) {
		// stdout may hold the (now untrusted) verdict array, so only the TAP
		// failures on stderr are useful here.
		const detail = (error.stderr || error.message || '').toString().trim();
		throw new Error('ucode tests/parity/run.uc failed; the backend does not honour cases.json' +
			(detail ? '\n' + detail : ''));
	}
	try {
		return JSON.parse(raw);
	}
	catch (error) {
		throw new Error('could not parse backend verdicts: ' + error.message);
	}
}

function frontendVerdict(rules, entry) {
	const name = RULES[entry.field];
	if (typeof rules[name] !== 'function')
		return 'missing-rule';
	const result = rules[name](entry.value);
	// A LuCI validate callback returns `true` or a message; any non-true value
	// blocks the form, so only `true` means accept.
	return result === true ? 'accept' : 'reject';
}

function main() {
	const cases = JSON.parse(readFileSync(CASES_PATH, 'utf8'));
	if (!Array.isArray(cases) || cases.length === 0)
		throw new Error('cases.json must contain a non-empty array');

	const rules = loadRules(true);
	const verdicts = backendVerdicts();

	// --- module shape ------------------------------------------------------
	// Several fields share one rule (the four 0/1 flags), so the export count is
	// the number of distinct rule names, not the number of mapped fields.
	const exported = Object.keys(rules);
	const ruleNames = new Set(Object.values(RULES));
	for (const name of ruleNames)
		check(typeof rules[name] === 'function', 'rules.js exports ' + name);
	check(exported.length === ruleNames.size,
		'rules.js exports exactly the documented rules',
		exported.join(', '));

	// A message must be a non-empty string, not `false`, so LuCI shows text.
	for (const field of Object.keys(RULES)) {
		const rule = rules[RULES[field]];
		if (typeof rule !== 'function')
			continue;
		const sample = { interface: '-bad', log_level: 'trace', latency: '0999:1',
			max_volume: '1.5', media_volume: '.5', name: '   ',
			metadata: 'yes', flush: 'yes', drift: 'yes', stop_receiver: 'yes',
			http_length: '4096', upnp_max: '10', artwork: 'ftp://example.com/a.png' }[field];
		const result = rule(sample);
		check(typeof result === 'string' && result.length > 0,
			RULES[field] + ' returns a message string for ' + JSON.stringify(sample),
			typeof result + ' ' + JSON.stringify(result));
	}

	// --- table versus backend ---------------------------------------------
	const expected = new Map();
	for (const item of verdicts)
		expected.set(item.index + ':' + item.scope, item.verdict);

	let compared = 0;
	for (let index = 0; index < cases.length; index++) {
		const entry = cases[index];
		// Must match MAIN_ONLY/DEVICE_ONLY in run.uc: upnp_max is main-only because
		// upstream never reads a per-device value.
		const scopes = entry.scope ? [entry.scope]
			: (entry.field === 'interface' || entry.field === 'log_level' || entry.field === 'upnp_max') ? ['main']
			: entry.field === 'name' ? ['device']
			: ['main', 'device'];
		for (const scope of scopes) {
			const backend = expected.get(index + ':' + scope);
			if (!check(backend != null, 'backend verdict exists for case ' + index + ' (' + scope + ')'))
				continue;
			if (!check(backend === entry.expect,
				'case ' + index + ' (' + scope + ') matches the table',
				'backend ' + backend + ', table ' + entry.expect))
				continue;
			// The browser sees one form per field; the main/device scope only
			// changes what the backend does with an empty value, which rules.js
			// is not responsible for.
			if (scope === 'main' && entry.field !== 'interface' && entry.field !== 'log_level' && entry.value === '')
				continue;
			const frontend = frontendVerdict(rules, entry);
			compared++;
			check(frontend === entry.expect,
				'case ' + index + ' (' + entry.field + ' = ' + JSON.stringify(entry.value) + ') frontend agrees with backend',
				'frontend ' + frontend + ', backend ' + entry.expect);
		}
	}
	check(compared >= cases.length, 'every case was compared', compared + ' of ' + cases.length);

	// --- standalone load ---------------------------------------------------
	// LuCI always provides `_`, but the host runner and any future plain-page
	// use may not; the module must still load and still reject.
	let bare = null;
	try {
		bare = loadRules(false);
	}
	catch (error) {
		check(false, 'rules.js loads without a translation helper', error.message);
	}
	if (bare != null) {
		check(bare.upnpVolume('1.5') !== true, 'rules still validate without _()');
		check(bare.interfaceValue('br-lan') === true, 'rules still accept without _()');
	}

	console.log(passed + ' passed; ' + failed + ' failed');
	process.exitCode = failed === 0 ? 0 : 1;
}

try {
	main();
}
catch (error) {
	console.error('check-frontend: ' + (error && error.message ? error.message : error));
	process.exitCode = 1;
}
