#!/usr/bin/env node
// SPDX-License-Identifier: MIT
// Check V8's actual line ranges against every frontend pure-logic module.

import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(fileURLToPath(new URL('..', import.meta.url)));
const SOURCE_DIR = join(ROOT, 'packages/luci-app-airconnect-manager/frontend/src/lib');
const coverageDir = process.argv[2];
const threshold = Number(process.env.COVERAGE_THRESHOLD || 80);

if (!coverageDir) {
  console.error('usage: node scripts/check-coverage.mjs <v8-coverage-directory>');
  process.exit(2);
}

function executableLines(source) {
  const result = [];
  let inBlockComment = false;
  for (const [index, original] of source.split('\n').entries()) {
    let line = original.trim();
    if (inBlockComment) {
      if (line.includes('*/')) inBlockComment = false;
      continue;
    }
    if (!line || line.startsWith('//')) continue;
    if (line.startsWith('/*')) {
      if (!line.includes('*/', 2)) inBlockComment = true;
      continue;
    }
    if (line.startsWith('*') || line.startsWith('*/')) continue;
    if (line.startsWith('import ')) continue;
    if (/^export\s*\{/.test(line)) continue;
    result.push(index);
  }
  return result;
}

const coverageByPath = new Map();
for (const entry of readdirSync(coverageDir)) {
  if (!entry.endsWith('.json')) continue;
  const record = JSON.parse(readFileSync(join(coverageDir, entry), 'utf8'));
  for (const script of record.result || []) {
    if (!script.url.startsWith('file:')) continue;
    const path = resolve(fileURLToPath(script.url));
    if (!path.startsWith(SOURCE_DIR + '/')) continue;
    const source = readFileSync(path, 'utf8');
    const offsets = [0];
    for (let i = 0; i < source.length; i++) if (source[i] === '\n') offsets.push(i + 1);
    const ranges = (script.functions || []).flatMap((fn) => fn.ranges || []);
    const hits = new Set();
    for (let line = 0; line < offsets.length; line++) {
      const start = offsets[line];
      let low = 0;
      let high = offsets.length;
      while (low < high) {
        const mid = (low + high) >> 1;
        if (offsets[mid] <= start) low = mid + 1;
        else high = mid;
      }
      const end = low < offsets.length ? offsets[low] : source.length;
      let smallest = Infinity;
      let count = 0;
      for (const range of ranges) {
        if (range.startOffset <= start && range.endOffset > start && range.endOffset >= end) {
          const size = range.endOffset - range.startOffset;
          if (size < smallest) {
            smallest = size;
            count = range.count;
          }
        }
      }
      if (smallest < Infinity && count > 0) hits.add(line);
    }
    const previous = coverageByPath.get(path) || new Set();
    for (const line of hits) previous.add(line);
    coverageByPath.set(path, previous);
  }
}

const files = readdirSync(SOURCE_DIR)
  .filter((name) => name.endsWith('.js'))
  .sort();
let totalLines = 0;
let coveredLines = 0;
let failed = false;
for (const name of files) {
  const path = join(SOURCE_DIR, name);
  const source = readFileSync(path, 'utf8');
  const lines = executableLines(source);
  const hits = coverageByPath.get(path) || new Set();
  const covered = lines.filter((line) => hits.has(line)).length;
  const percent = lines.length ? (covered / lines.length) * 100 : 100;
  const status = percent >= threshold ? 'PASS' : 'FAIL';
  console.log(`${status} ${covered}/${lines.length} ${percent.toFixed(1)}% ${name}`);
  if (percent < threshold) failed = true;
  totalLines += lines.length;
  coveredLines += covered;
}
const overall = totalLines ? (coveredLines / totalLines) * 100 : 100;
console.log(
  `${failed ? 'FAIL' : 'PASS'} total ${coveredLines}/${totalLines} ${overall.toFixed(1)}% (per-file minimum ${threshold}%)`,
);
assert(!failed, `frontend core line coverage must be at least ${threshold}% in every module`);
