import { spawnSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, resolve } from 'node:path';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const mode = process.argv[2];
if (!['lint', 'format', 'format:check'].includes(mode)) {
  console.error('usage: node scripts/check-shell.mjs <lint|format|format:check>');
  process.exit(2);
}

const tool = mode.startsWith('format') ? 'shfmt' : 'shellcheck';
const toolArgs =
  mode === 'format'
    ? ['-ln', 'bash', '-w', '-i', '0', '-ci']
    : mode === 'format:check'
      ? ['-ln', 'bash', '-d', '-i', '0', '-ci']
      : ['--shell=bash', '--severity=error'];

function collectShellFiles(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    if (entry.isDirectory() && entry.name === 'node_modules') return [];
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return collectShellFiles(path);
    return entry.isFile() && entry.name.endsWith('.sh') ? [path] : [];
  });
}

const files = ['scripts', 'tests', 'packages'].flatMap((directory) =>
  collectShellFiles(join(root, directory)),
);

if (files.length === 0) {
  console.log('No shell scripts found.');
  process.exit(0);
}

const result = spawnSync(tool, [...toolArgs, ...files], {
  cwd: root,
  stdio: 'inherit',
});

if (result.error) {
  console.error(`${tool} is required; install it and retry.`);
  process.exit(2);
}
process.exit(result.status ?? 1);
