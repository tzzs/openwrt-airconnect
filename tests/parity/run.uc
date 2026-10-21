// SPDX-License-Identifier: MIT
// Frontend/backend validation parity: cases.json is the contract.
//
// Run from the repository root:
//   ucode -L ~/.local/opt/ucode-host/lib/ucode tests/parity/run.uc
//
// This runner decides every case with the real backend (normalizeConfig from
// config.uc) and asserts the hand-maintained table in cases.json still matches
// it. tests/parity/check-frontend.mjs runs the same table through rules.js, so
// a value the browser accepts but the router rejects (or the reverse) fails a
// host test instead of costing the user a round trip.
//
// The optional `--verdicts` argument prints one JSON array of backend verdicts
// for check-frontend.mjs, so the node runner never re-implements backend
// validation and cannot drift from it.
import * as fs from 'fs';
import { normalizeConfig } from '../../packages/airconnect-manager/files/usr/share/airconnect-manager/config.uc';

const HERE = fs.dirname(sourcepath());
const CASES_PATH = HERE + '/cases.json';
const VERDICTS_ONLY = index(ARGV, '--verdicts') >= 0;

// Every field the table may use. The two section lists name the fields that
// exist in only one place; everything else is checked in both, unless a case
// says `scope` explicitly, because device overrides must follow the same rules.
//
// upnp_max is main-only for a source-level reason, not a UI choice: upstream
// parses it into the device struct but only ever reads glMRConfig.UPnPMax when
// it builds the search topics (airupnp.c:599, 1159), so a per-device value
// would be dead XML and is deliberately not part of the device contract.
const FIELDS = [
	'interface', 'log_level', 'latency', 'max_volume', 'media_volume', 'name',
	'metadata', 'flush', 'drift', 'stop_receiver', 'http_length', 'upnp_max', 'artwork'
];
const MAIN_ONLY = ['interface', 'log_level', 'upnp_max'];
const DEVICE_ONLY = ['name'];

let passed = 0;
let failed = 0;

function assert(condition, message) {
	if (!condition)
		die(message || 'assertion failed');
}

function test(label, callback) {
	try {
		callback();
		passed++;
		if (!VERDICTS_ONLY)
			print('ok ', passed + failed, ' - ', label, '\n');
	}
	catch (error) {
		failed++;
		if (!VERDICTS_ONLY)
			print('not ok ', passed + failed, ' - ', label, ': ', error.message, '\n');
	}
}

function scopesOf(entry) {
	if (exists(entry, 'scope'))
		return [entry.scope];
	if (index(MAIN_ONLY, entry.field) >= 0)
		return ['main'];
	if (index(DEVICE_ONLY, entry.field) >= 0)
		return ['device'];
	return ['main', 'device'];
}

function payloadFor(entry, scope) {
	if (scope == 'main') {
		let main = {};
		main[entry.field] = entry.value;
		return { main: main };
	}
	let device = { engine: 'upnp', udn: 'uuid:demo-parity' };
	device[entry.field] = entry.value;
	return { devices: [device] };
}

// Returns 'accept', 'reject' or 'error' (a payload the backend cannot even
// build, which is a bug in this runner rather than a verdict).
function backendVerdict(entry, scope) {
	try {
		normalizeConfig(payloadFor(entry, scope));
		return 'accept';
	}
	catch (error) {
		let message = type(error) == 'object' && error != null ? error.message : '' + error;
		// normalizeConfig reports every rejection as "<path>: <reason>", so a
		// message without a colon is not a validation verdict.
		return index(message, ':') > 0 ? 'reject' : 'error';
	}
}

function label(entry, scope) {
	return entry.field + '[' + scope + '] = ' + sprintf('%J', entry.value);
}

function loadCases() {
	let text = fs.readfile(CASES_PATH);
	assert(type(text) == 'string', 'cannot read ' + CASES_PATH);
	let cases = json(text);
	assert(type(cases) == 'array', 'cases.json must contain an array');
	return cases;
}

let cases = loadCases();

// --- schema ----------------------------------------------------------------
test('cases.json is non-empty', () => assert(length(cases) > 0));

for (let i = 0; i < length(cases); i++) {
	let entry = cases[i];
	let where = 'case ' + i;
	if (type(entry) != 'object' || entry == null) {
		test(where + ' is an object', () => assert(false, 'not an object'));
		continue;
	}
	test(where + ' names a known field', () => assert(index(FIELDS, entry.field) >= 0, 'unknown field ' + sprintf('%J', entry.field)));
	test(where + ' has a supported expectation', () => assert(entry.expect == 'accept' || entry.expect == 'reject', 'expect must be accept or reject'));
	test(where + ' has a supported scope', () => assert(!exists(entry, 'scope') || entry.scope == 'main' || entry.scope == 'device', 'scope must be main or device'));
	test(where + ' has a string or number value', () => assert(type(entry.value) == 'string' || type(entry.value) == 'int' || type(entry.value) == 'double', 'value must be a string or a number'));
	test(where + ' scopes a field only where it exists', () => {
		assert(!(entry.scope == 'device' && index(MAIN_ONLY, entry.field) >= 0), entry.field + ' does not exist on a device');
		assert(!(entry.scope == 'main' && index(DEVICE_ONLY, entry.field) >= 0), entry.field + ' does not exist in the main section');
	});
}

// Every field and every scope must appear, otherwise the table could quietly
// stop covering a rule while still passing.
for (let field in FIELDS)
	test('cases.json covers ' + field, () => {
		let seen = 0;
		for (let entry in cases)
			if (entry.field == field)
				seen++;
		assert(seen > 0, 'no case for ' + field);
	});
for (let scope in ['main', 'device'])
	test('cases.json covers the ' + scope + ' scope', () => {
		for (let entry in cases)
			for (let value in scopesOf(entry))
				if (value == scope)
					return;
		die('no case for scope ' + scope);
	});

// --- the contract ----------------------------------------------------------
let verdicts = [];

for (let i = 0; i < length(cases); i++) {
	let entry = cases[i];
	for (let scope in scopesOf(entry)) {
		let actual = backendVerdict(entry, scope);
		push(verdicts, { index: i, scope: scope, verdict: actual });
		test(label(entry, scope) + ' is ' + entry.expect, () => {
			assert(actual != 'error', 'backend raised a non-validation error');
			assert(actual == entry.expect, 'backend says ' + actual + ', the table says ' + entry.expect);
		});
	}
}

// --- both scopes must agree ------------------------------------------------
// A field the backend validates identically in `main` and in a device override
// is a documented property of config.uc; the table relies on it. Empty device
// values are excluded: there they mean "inherit", so the two scopes differ by
// design rather than by rule.
for (let i = 0; i < length(cases); i++) {
	let entry = cases[i];
	if (exists(entry, 'scope') || index(MAIN_ONLY, entry.field) >= 0 ||
		index(DEVICE_ONLY, entry.field) >= 0 || entry.value === '')
		continue;
	test(label(entry, 'device') + ' agrees with the main section', () => {
		assert(backendVerdict(entry, 'main') == backendVerdict(entry, 'device'), 'main and device verdicts differ');
	});
}

if (VERDICTS_ONLY) {
	print(sprintf('%J\n', verdicts));
	exit(failed ? 1 : 0);
}

print('1..', passed + failed, '\n', passed, ' passed; ', failed, ' failed\n');
exit(failed ? 1 : 0);
