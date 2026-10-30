#!/usr/bin/env node
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 tzzs
//
// Regenerate the gettext template and the Simplified Chinese catalogue from the
// frontend sources.
//
//   node scripts/update-i18n.mjs [--check]
//
// Why a script rather than xgettext
// -------------------------------
// The translatable strings live in JavaScript, in the shape `_('Text')`. GNU
// xgettext does not know that shape and would extract nothing useful from the
// sources, so the extraction is done here instead. The output is ordinary
// gettext: `msgfmt` compiles it into the `.lmo` that LuCI loads.
//
// What it extracts
// ----------------
// Every `_('...')` call in frontend/src/** and in the LuCI views under
// htdocs/luci-static/resources/view/**. The front-end has its own built-in
// Chinese table (frontend/src/lib/i18n.js) so the page can switch language
// without a round trip to the router; this catalogue is the translation that
// ships with the package and that the LuCI chrome uses.
//
// The Chinese strings come from that built-in table, so the two cannot drift:
// the table is the single source of truth for the translation, and this script
// copies it into the catalogue.
//
// --check
// -------
// Verifies that the checked-in POT and PO already match what this script
// would generate, and exits nonzero if they are stale. It is what CI runs.
//
// Exit status: 0 when the catalogues are current (or were regenerated), 1 when
// --check found them stale.

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const PKG = join(ROOT, 'packages/luci-app-airconnect-manager');
const FRONTEND = join(PKG, 'frontend/src');
const VIEWS = join(PKG, 'htdocs/luci-static/resources/view/airconnect-manager');
const POT = join(PKG, 'po/templates/airconnect-manager.pot');
const PO = join(PKG, 'po/zh_Hans/airconnect-manager.po');
const TABLE = join(FRONTEND, 'lib/i18n.js');

const CHECK = process.argv.includes('--check');
const STAMP = '2026-10-31 00:00+0800';

function fail(message) {
	console.error('update-i18n: ' + message);
	process.exit(1);
}

/**
 * Walk a directory and collect the translatable strings.
 *
 * The pattern only matches single-quoted arguments with no interpolation:
 * `_('Save')` yes, `_(\`Save ${x}\`)` no. A string that interpolates cannot be
 * translated anyway, because the translator would have to guess where the
 * variable goes, so the pattern deliberately excludes it.
 */
const CALL = /_\(\s*'((?:\\.|[^'\\])*)'\s*\)/g;

function collect(directory, out) {
	for (const path of listSources(directory)) {
		const source = readFileSync(path, 'utf8');
		const rel = relative(PKG, path).split('\\').join('/');
		for (const match of source.matchAll(CALL)) {
			const text = JSON.parse('"' + match[1].replace(/"/g, '\\"') + '"');
			if (!out.has(text)) out.set(text, []);
			out.get(text).push(rel);
		}
	}
	return out;
}

/** Every .js/.jsx file under a directory, recursively, in a stable order. */
function listSources(directory) {
	const files = [];
	for (const entry of readdirSorted(directory)) {
		const path = join(directory, entry);
		if (statIsDirectory(path)) files.push(...listSources(path));
		else if (/\.(js|jsx)$/.test(entry)) files.push(path);
	}
	return files;
}
// Small helpers so the script does not need node:fs's sync stat dance in a
// recursive walk; `import { readdirSync, statSync }` is enough.
const { readdirSync, statSync } = await import('node:fs');

function readdirSorted(directory) {
	return readdirSync(directory).sort();
}

function statIsDirectory(path) {
	return statSync(path).isDirectory();
}

/**
 * Read the built-in Chinese table out of lib/i18n.js.
 *
 * The table is a plain object literal, so it is evaluated rather than parsed.
 * Evaluating it is safe here: the file is part of this repository and has no
 * side effects beyond defining the table. It is imported as a module so the
 * exports stay the single source of truth.
 */
const { ZH } = await import(new URL(
	'../packages/luci-app-airconnect-manager/frontend/src/lib/i18n.js',
	import.meta.url
));

function escape(value) {
	return value
		.replace(/\\/g, '\\\\')
		.replace(/"/g, '\\"')
		.replace(/\n/g, '\\n')
		.replace(/\t/g, '\\t');
}

function renderHeader(extra) {
	return [
		'# AirConnect Manager translation template.',
		'# This file is distributed under the same license as the package.',
		'#',
		'msgid ""',
		'msgstr ""',
		'"Project-Id-Version: luci-app-airconnect-manager 0.1.0\\n"',
		`"POT-Creation-Date: ${STAMP}\\n"`,
		'"MIME-Version: 1.0\\n"',
		'"Content-Type: text/plain; charset=UTF-8\\n"',
		'"Content-Transfer-Encoding: 8bit\\n"',
		...extra
	].join('\n');
}

function renderEntries(strings) {
	const out = [];
	for (const [text, locations] of strings) {
		out.push('');
		for (const location of locations) out.push('#: ' + location);
		out.push('msgid "' + escape(text) + '"');
		out.push('msgstr ""');
	}
	return out.join('\n') + '\n';
}

const strings = collect(FRONTEND, new Map());
for (const path of readdirSorted(VIEWS)) {
	if (!path.endsWith('.js')) continue;
	const full = join(VIEWS, path);
	const source = readFileSync(full, 'utf8');
	const rel = relative(PKG, full).split('\\').join('/');
	for (const match of source.matchAll(CALL)) {
		const text = JSON.parse('"' + match[1].replace(/"/g, '\\"') + '"');
		if (!strings.has(text)) strings.set(text, []);
		strings.get(text).push(rel);
	}
}

// Sort by msgid, which is what gettext does and what makes the diff stable.
const sorted = new Map(
	[...strings.entries()].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
);

const pot = [
	renderHeader([]),
	renderEntries(sorted)
].join('\n');

let po = [
	'# Chinese translations for luci-app-airconnect-manager package.',
	'# Copyright (C) 2026 THE luci-app-airconnect-manager\'S COPYRIGHT HOLDER',
	'# This file is distributed under the same license as the luci-app-airconnect-manager package.',
	'# Automatically generated, 2026.',
	'#',
	'msgid ""',
	'msgstr ""',
	'"Project-Id-Version: luci-app-airconnect-manager 0.1.0\\n"',
	`"POT-Creation-Date: ${STAMP}\\n"`,
	`"PO-Revision-Date: ${STAMP}\\n"`,
	'"Last-Translator: Automatically generated\\n"',
	'"Language-Team: none\\n"',
	'"Language: zh_Hans\\n"',
	'"MIME-Version: 1.0\\n"',
	'"Content-Type: text/plain; charset=UTF-8\\n"',
	'"Content-Transfer-Encoding: 8bit\\n"',
	renderEntries(sorted)
].join('\n');

// The Chinese text comes from the built-in table, so the catalogue and the
// bundle cannot disagree about a translation.
let poLines = po.split('\n');
for (let i = 0; i < poLines.length - 1; i++) {
	const match = /^msgid "(.*)"$/.exec(poLines[i]);
	if (!match) continue;
	const id = JSON.parse('"' + match[1] + '"');
	const translated = ZH[id];
	if (translated === undefined) continue;
	poLines[i + 1] = 'msgstr "' + escape(translated) + '"';
}
po = poLines.join('\n');

if (CHECK) {
	const stale = [];
	for (const [path, expected] of [[POT, pot], [PO, po]]) {
		const actual = readFileSync(path, 'utf8');
		if (actual !== expected) stale.push(relative(ROOT, path));
	}
	if (stale.length) {
		console.error(
			'update-i18n: the translation catalogues are stale: ' + stale.join(', ') +
			'\nrun: node scripts/update-i18n.mjs'
		);
		process.exit(1);
	}
	console.log('update-i18n: ' + sorted.size + ' strings, catalogues are current');
	process.exit(0);
}

writeFileSync(POT, pot);
writeFileSync(PO, po);
console.log('update-i18n: wrote ' + sorted.size + ' strings to the template and the catalogue');
