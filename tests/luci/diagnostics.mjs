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
// Every string the page shows about state comes from
// frontend/src/lib/presentation.js, so this file asserts the wording directly.
// The components can only render what that module decides, which is why the
// contract is testable without a DOM.
//
// What is deliberately NOT asserted: that a browser paints these strings, or
// that rpcd returns these replies. This proves the page's own decisions, which
// is what a code change can break.
//
// Exit status: 0 when every assertion holds, 1 otherwise.

const { createPresentation } = await import(
  new URL(
    '../../packages/luci-app-airconnect-manager/frontend/src/lib/presentation.js',
    import.meta.url,
  )
);

const p = createPresentation(function (text) {
  return text;
});

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

const OBSERVED_AT = 1700000000;

function status(overrides) {
  return Object.assign(
    {
      enabled: true,
      interface: 'br-lan',
      version: '0.1.0-test',
      services: {
        upnp: { enabled: true, running: true, broadcasting: null },
        cast: { enabled: false, running: false, broadcasting: null },
      },
      scan: { running: false, last_scan: OBSERVED_AT, error: null },
      broadcast: { observed_at: null, error: null },
      playback: { known: false, reason: 'no documented engine status API' },
      conflicts: [],
      devices: [],
    },
    overrides,
  );
}

function main() {
  section('an unmeasured broadcast renders as unknown, never as a positive');
  {
    check(p.broadcastStatus(null) === 'Unknown', 'the row says Unknown', p.broadcastStatus(null));
    check(
      p.deviceBroadcastBadge(null).label === 'AirPlay: Unknown',
      'the device badge uses the same label set',
      p.deviceBroadcastBadge(null).label,
    );
    check(
      p.deviceBroadcastBadge(null).tone !== 'positive',
      'the unknown badge is not painted as a positive',
      p.deviceBroadcastBadge(null).tone,
    );
    // A scan that never ran has no observation time and no failure reason.
    check(p.broadcastCheckedAt(null) === null, 'an unmeasured state has no check time');
    check(p.broadcastError(null) === null, 'an unmeasured state has no error row');
  }

  section('a measured positive uses the same label as the badge');
  {
    check(
      p.broadcastStatus(true) === 'Broadcasting',
      'the UPnP row is a positive',
      p.broadcastStatus(true),
    );
    check(
      p.deviceBroadcastBadge(true).label === 'AirPlay: Broadcasting',
      'the device badge is the same three-state label',
      p.deviceBroadcastBadge(true).label,
    );
    check(
      p.deviceBroadcastBadge(true).tone === 'positive',
      'the positive badge is painted as a positive',
    );
    // The observation time is a separate row shared by both engines.
    const checkedAt = p.broadcastCheckedAt(OBSERVED_AT);
    check(/^Last broadcast check: /.test(checkedAt), 'the check time is its own row', checkedAt);
    // A measured negative is NOT unknown and must not read as a positive.
    const negative = p.broadcastStatus(false);
    check(negative === 'Not broadcasting', 'the Chromecast row is a measured negative', negative);
    check(!/Unknown/.test(negative), 'a measured negative is not Unknown', negative);
  }

  section('a measured negative is a value, not Unknown');
  {
    check(
      p.broadcastStatus(false) === 'Not broadcasting',
      'the row is a negative',
      p.broadcastStatus(false),
    );
    check(
      p.deviceBroadcastBadge(false).label === 'AirPlay: Not broadcasting',
      'the device badge is a negative',
      p.deviceBroadcastBadge(false).label,
    );
  }

  section('a failed observation is unknown and shows why once');
  {
    check(
      p.broadcastStatus(null) === 'Unknown',
      'a failed observation is Unknown',
      p.broadcastStatus(null),
    );
    check(
      p.broadcastError('no reply') === 'Last check error: no reply',
      'the failure reason is one shared row',
      p.broadcastError('no reply'),
    );
    check(p.broadcastError(null) === null, 'a completed scan has no error row');
  }

  section('playback is never implied by a broadcast positive');
  {
    const playback = p.playbackText(
      status({
        services: {
          upnp: { enabled: true, running: true, broadcasting: true },
          cast: { enabled: false, running: false, broadcasting: true },
        },
        broadcast: { observed_at: OBSERVED_AT, error: null },
      }),
    );
    check(/^Unknown/.test(playback), 'playback stays Unknown while broadcasting is true', playback);
    check(
      /never inferred/.test(playback),
      'the row says it is not inferred from broadcast',
      playback,
    );
    // The two rows must be distinguishable text, not the same string.
    check(playback !== p.broadcastStatus(true), 'playback and broadcast are not the same string');
  }

  section('playback is the same constant whatever the broadcast state');
  {
    const texts = [];
    for (const value of [null, true, false]) {
      texts.push(
        p.playbackText(
          status({
            services: {
              upnp: { enabled: true, running: true, broadcasting: value },
              cast: { enabled: false, running: false, broadcasting: value },
            },
            broadcast: { observed_at: value === null ? null : OBSERVED_AT, error: null },
          }),
        ),
      );
    }
    check(
      texts[0] === texts[1] && texts[1] === texts[2],
      'playback does not change with the broadcast state',
      JSON.stringify(texts),
    );
  }

  section('service running is not rendered as broadcasting');
  {
    const service = { enabled: true, running: true, broadcasting: null };
    check(
      p.serviceLabel(service) === 'Running',
      'the service badge says Running',
      p.serviceLabel(service),
    );
    check(
      p.broadcastStatus(service.broadcasting) === 'Unknown',
      'a running service does not make the broadcast row positive',
    );
  }

  section('discovered is not rendered as broadcasting');
  {
    check(p.onlineLabel(true) === 'Discovered', 'the device is discovered', p.onlineLabel(true));
    check(
      p.deviceBroadcastBadge(null).label === 'AirPlay: Unknown',
      'being discovered does not make it broadcast',
    );
  }

  section('scan state');
  {
    check(p.scanStatus({ error: 'boom' }).role === 'alert', 'a failed scan is an alert');
    check(
      /^Scan failed: boom/.test(p.scanStatus({ error: 'boom' }).text),
      'a failed scan shows the reason',
      p.scanStatus({ error: 'boom' }).text,
    );
    check(
      p.scanStatus({ running: true }).text === 'Discovery is in progress.',
      'a running scan says so',
      p.scanStatus({ running: true }).text,
    );
    check(
      /^Last scan: /.test(p.scanStatus({ last_scan: OBSERVED_AT }).text),
      'a completed scan shows when',
      p.scanStatus({ last_scan: OBSERVED_AT }).text,
    );
    check(
      p.scanStatus({}).text === 'No scan has been completed.',
      'no scan says so',
      p.scanStatus({}).text,
    );
    check(
      p.scanDisabled({}, { upnp: { enabled: false }, cast: { enabled: false } }) === true,
      'scan is disabled when neither engine is enabled',
    );
    check(
      p.scanDisabled({}, { upnp: { enabled: true }, cast: { enabled: false } }) === false,
      'scan is enabled when one engine is enabled',
    );
    check(
      p.scanDisabled({ running: true }, { upnp: { enabled: true } }) === true,
      'scan is disabled while one is running',
    );
  }

  console.log(`\n${passed} passed; ${failed} failed`);
  process.exit(failed === 0 ? 0 : 1);
}

main();
