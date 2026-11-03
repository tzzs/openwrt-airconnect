#!/usr/bin/env node
// SPDX-License-Identifier: MIT
// Behavior tests for the pure frontend modules that do not need a browser.

import assert from 'node:assert/strict';
import { buildCanonicalConfig } from '../../packages/luci-app-airconnect-manager/frontend/src/lib/config.js';
import {
  trimTrailing,
  readState,
  deviceKey,
  effectiveNames,
  duplicateNames,
  mergeDevices,
} from '../../packages/luci-app-airconnect-manager/frontend/src/lib/model.js';
import { createServices } from '../../packages/luci-app-airconnect-manager/frontend/src/lib/services.js';
import {
  THEMES,
  detectTheme,
  writeTheme,
  resolveTheme,
  applyTheme,
  watchSystemTheme,
} from '../../packages/luci-app-airconnect-manager/frontend/src/lib/theme.js';
import { cn } from '../../packages/luci-app-airconnect-manager/frontend/src/lib/utils.js';

let passed = 0;
function test(name, fn) {
  fn();
  passed++;
  console.log(`ok - ${name}`);
}

function fakeClassList(initial = []) {
  const values = new Set(initial);
  return {
    values,
    add(value) {
      values.add(value);
    },
    remove(...items) {
      for (const item of items) values.delete(item);
    },
  };
}

test('canonical config copies known values and separates removed sections', () => {
  const calls = [];
  const result = buildCanonicalConfig({
    get(pkg, section, key) {
      calls.push([pkg, section, key]);
      return key === 'enabled' ? '1' : null;
    },
    sections(pkg, type, callback) {
      assert.equal(pkg, 'airconnect-manager');
      assert.equal(type, 'device');
      callback({ '.name': 'device_a', engine: 'upnp', udn: 'uuid:a', ignored: 'x' });
      callback({ '.name': 'device_b', '.removed': true });
    },
  });
  assert.equal(calls.length, 16);
  assert.deepEqual(result.main, { enabled: '1' });
  assert.deepEqual(result.devices, [{ section: 'device_a', engine: 'upnp', udn: 'uuid:a' }]);
  assert.deepEqual(result.removed, ['device_b']);
});

test('model reads UCI state without leaking unknown fields', () => {
  const state = readState({
    get(section, key) {
      return section === 'main' && key === 'enabled' ? '1' : null;
    },
    sections(type, callback) {
      assert.equal(type, 'device');
      callback({
        '.name': 'speaker',
        engine: 'cast',
        udn: 'uuid:one',
        name: 'Room',
        extra: 'ignored',
      });
      callback({ '.name': 'deleted', '.removed': true, engine: 'upnp' });
    },
  });
  assert.equal(state.main.enabled, '1');
  assert.deepEqual(state.devices.speaker, { engine: 'cast', udn: 'uuid:one', name: 'Room' });
  assert.equal(state.sections[1].removed, true);
  assert.equal(trimTrailing(null), '');
  assert.equal(trimTrailing('Room  \n'), 'Room');
  assert.equal(deviceKey('upnp', 'uuid:a'), 'upnp\nuuid:a');
});

test('effective names honor overrides, discovery fallback and removed entries', () => {
  const state = {
    status: {
      devices: [
        { engine: 'upnp', udn: 'uuid:a', original_name: ' Discovered  ' },
        { engine: 'cast', udn: 'uuid:b', original_name: 'Kitchen' },
      ],
    },
    configured: [
      { name: 'a', engine: 'upnp', udn: 'uuid:a' },
      { name: 'b', engine: 'cast', udn: 'uuid:b' },
      { name: 'gone', engine: 'cast', udn: 'uuid:c', removed: true },
      { name: 'empty', engine: 'cast', udn: 'uuid:d' },
    ],
    deviceValues: { a: { name: 'Override  ' }, b: { name: '' } },
  };
  assert.deepEqual(effectiveNames(state), ['Override', 'Kitchen']);
});

test('duplicate names preserve first-seen order and safe object-like names', () => {
  const configured = ['constructor', '__proto__', 'Echo', 'Echo', 'constructor'].map((name, i) => ({
    name: String(i),
    engine: 'upnp',
    udn: `uuid:${i}`,
  }));
  const deviceValues = Object.fromEntries(
    configured.map((item, i) => [
      item.name,
      { name: ['constructor', '__proto__', 'Echo', 'Echo', 'constructor'][i] },
    ]),
  );
  assert.deepEqual(duplicateNames({ configured, deviceValues }), ['constructor', 'Echo']);
});

test('device merge attaches configured sections, keeps offline devices and filters invalid entries', () => {
  const result = mergeDevices({
    status: {
      devices: [
        { engine: 'upnp', udn: 'uuid:seen', online: true },
        null,
        { engine: 'bogus', udn: 'uuid:bad' },
        { engine: 'cast', udn: '' },
      ],
    },
    configured: [
      { name: 'seen', engine: 'upnp', udn: 'uuid:seen' },
      { name: 'offline', engine: 'cast', udn: 'uuid:offline' },
      { name: 'removed', engine: 'cast', udn: 'uuid:removed', removed: true },
      { name: 'bad', engine: 'bogus', udn: 'uuid:bad' },
    ],
    deviceValues: { offline: { name: 'Away' } },
  });
  assert.deepEqual(result, [
    { engine: 'upnp', udn: 'uuid:seen', online: true, section: 'seen' },
    {
      engine: 'cast',
      udn: 'uuid:offline',
      name: 'Away',
      original_name: null,
      online: false,
      configured: true,
      section: 'offline',
    },
  ]);
});

test('service adapter forwards UCI and RPC calls with the package contract', async () => {
  const declarations = [];
  const invocations = [];
  const uci = {
    async load(...args) {
      invocations.push(['load', ...args]);
    },
    get(...args) {
      invocations.push(['get', ...args]);
      return 'v';
    },
    sections(...args) {
      invocations.push(['sections', ...args.slice(0, 2)]);
    },
    set(...args) {
      invocations.push(['set', ...args]);
    },
    add(...args) {
      invocations.push(['add', ...args]);
      return 'new';
    },
    remove(...args) {
      invocations.push(['remove', ...args]);
    },
    save() {
      invocations.push(['save']);
    },
  };
  const rpc = {
    declare(spec) {
      declarations.push(spec);
      return (...args) => {
        invocations.push([spec.method, ...args]);
        return Promise.resolve(spec.method);
      };
    },
  };
  const services = createServices({ uci, rpc, ui: null, poll: null });
  assert.equal(services.t('hello'), 'hello');
  await services.loadConfig();
  assert.equal(services.get('main', 'enabled'), 'v');
  services.sections('device', () => {});
  services.set('main', 'enabled', '1');
  assert.equal(services.add('device'), 'new');
  services.remove('x');
  services.save();
  assert.deepEqual(
    await Promise.all([
      services.status(),
      services.interfaces(),
      services.scan(),
      services.logs(),
      services.validate({}),
      services.action('start'),
    ]),
    ['status', 'dump', 'scan', 'logs', 'validate', 'action'],
  );
  assert.equal(declarations.length, 6);
  assert.deepEqual(invocations.slice(0, 6), [
    ['load', 'airconnect-manager'],
    ['get', 'airconnect-manager', 'main', 'enabled'],
    ['sections', 'airconnect-manager', 'device'],
    ['set', 'airconnect-manager', 'main', 'enabled', '1'],
    ['add', 'airconnect-manager', 'device'],
    ['remove', 'airconnect-manager', 'x'],
  ]);
});

test('service adapter handles optional UI and polling hooks safely', () => {
  const notifications = [];
  const pollCalls = [];
  globalThis.document = { createElement: () => ({ textContent: '' }) };
  const services = createServices({
    uci: {},
    rpc: { declare: () => () => Promise.resolve() },
    ui: {
      addNotification(_title, node, kind) {
        notifications.push([node.textContent, kind]);
      },
      changes: {
        init: () => 'init',
        apply: (rollback) => rollback,
      },
    },
    poll: {
      add: (...args) => pollCalls.push(['add', ...args]),
      remove: (...args) => pollCalls.push(['remove', ...args]),
    },
    translate: (text) => `t:${text}`,
  });
  assert.equal(services.t('x'), 't:x');
  services.notify('<safe text>', 'warning');
  assert.deepEqual(notifications, [['<safe text>', 'warning']]);
  assert.equal(services.changesInit(), 'init');
  assert.equal(services.changesApply(true), true);
  const fn = () => {};
  services.pollAdd(fn, 10);
  services.pollRemove(fn);
  assert.deepEqual(pollCalls, [
    ['add', fn, 10],
    ['remove', fn],
  ]);
  delete globalThis.document;

  const optional = createServices({
    uci: {},
    rpc: { declare: () => () => {} },
    ui: null,
    poll: null,
  });
  optional.notify('ignored');
  optional.pollAdd(fn, 1);
  optional.pollRemove(fn);
  assert.equal(optional.changesInit() instanceof Promise, true);
  assert.equal(optional.changesApply() instanceof Promise, true);
});

test('theme storage and resolution fall back safely in a headless runtime', () => {
  assert.deepEqual(
    THEMES.map((theme) => theme.value),
    ['system', 'light', 'dark'],
  );
  assert.equal(detectTheme(), 'system');
  writeTheme('dark');
  writeTheme('invalid');
  assert.equal(resolveTheme('dark'), 'dark');
  assert.equal(resolveTheme('invalid'), 'light');
  assert.equal(resolveTheme('system'), 'light');
  assert.equal(watchSystemTheme(() => {}) instanceof Function, true);
});

test('theme applies classes and watches modern and legacy media query events', () => {
  const classes = fakeClassList(['ac-theme-dark', 'other']);
  const root = { classList: classes };
  applyTheme(root, 'light');
  assert.deepEqual([...classes.values].sort(), ['ac-theme-light', 'other']);
  applyTheme(root, 'system');
  assert.deepEqual([...classes.values], ['other']);
  applyTheme(null, 'dark');

  let modernHandler;
  let modernRemoved;
  globalThis.window = {
    matchMedia: () => ({
      matches: true,
      addEventListener(_name, handler) {
        modernHandler = handler;
      },
      removeEventListener(_name, handler) {
        modernRemoved = handler;
      },
    }),
  };
  assert.equal(resolveTheme('system'), 'dark');
  let calls = 0;
  const stop = watchSystemTheme(() => {
    calls++;
  });
  modernHandler();
  assert.equal(calls, 1);
  stop();
  assert.equal(modernRemoved, modernHandler);

  let legacyHandler;
  globalThis.window = {
    matchMedia: () => ({
      addListener(handler) {
        legacyHandler = handler;
      },
      removeListener(handler) {
        assert.equal(handler, legacyHandler);
      },
    }),
  };
  const stopLegacy = watchSystemTheme(() => {
    throw new Error('callback is isolated');
  });
  assert.doesNotThrow(() => legacyHandler());
  stopLegacy();
  delete globalThis.window;
  assert.doesNotThrow(() =>
    applyTheme(
      {
        classList: {
          remove() {
            throw new Error('readonly');
          },
        },
      },
      'dark',
    ),
  );
});

test('theme storage and media query failures degrade without throwing', () => {
  globalThis.localStorage = {
    getItem() {
      throw new Error('blocked');
    },
    setItem() {
      throw new Error('blocked');
    },
  };
  assert.equal(detectTheme(), 'system');
  assert.doesNotThrow(() => writeTheme('light'));
  globalThis.window = {
    matchMedia() {
      throw new Error('unavailable');
    },
  };
  assert.equal(resolveTheme('system'), 'light');
  delete globalThis.window;
  delete globalThis.localStorage;
});

test('class names combine conditionals and later Tailwind utilities win', () => {
  assert.equal(cn('p-2 text-sm', false && 'hidden', 'p-4'), 'text-sm p-4');
  assert.equal(
    cn(['flex', ['items-center']], { hidden: true, block: false }),
    'items-center hidden',
  );
});

console.log(`${passed} passed; 0 failed`);
