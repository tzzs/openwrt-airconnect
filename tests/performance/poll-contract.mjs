#!/usr/bin/env node
// SPDX-License-Identifier: MIT
// The polling contract of the page.
//
//   node tests/performance/poll-contract.mjs
//
// docs/PERFORMANCE.zh-CN.md and docs/ARCHITECTURE.zh-CN.md both promise, in
// prose, that the page polls every 10 seconds, pauses while the tab is hidden,
// never has two requests in flight, backs off to 60 seconds after repeated
// failures, and does not repaint the form when a status reply arrives. Those are
// the four claims that decide whether opening a second tab doubles the router's
// RPC load, and nothing else executes them.
//
// The polling loop lives in frontend/src/lib/polling.js - a plain object the
// React tree drives - so this file exercises it directly with a fake clock and a
// fake status call. There is no browser, no LuCI, no npm dependency and no
// network access.
//
// What is deliberately NOT asserted here: that a real browser honours
// document.hidden (that is the browser's contract), that a real LuCI loads the
// view, or what an RPC costs. This suite proves the page's own decisions, which
// is what a code change can break.
//
// Exit status: 0 when every assertion holds, 1 otherwise.

const { createPoller, applySnapshot, POLL_SECONDS } = await import(new URL(
	'../../packages/luci-app-airconnect-manager/frontend/src/lib/polling.js',
	import.meta.url));
const { nextRetryDelayMs } = await import(new URL(
	'../../packages/luci-app-airconnect-manager/frontend/src/lib/backoff.js',
	import.meta.url));

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

function statusPayload(overrides) {
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
		devices: []
	}, overrides);
}

/** A poller with a controllable clock and visibility, plus call counters. */
function harness(options) {
	const settings = options || {};
	const state = { clock: 1000000, hidden: false, calls: 0, snapshots: 0, errors: 0 };
	const poller = createPoller({
		fetch: () => {
			state.calls++;
			return settings.status ? settings.status(state) : Promise.resolve(statusPayload());
		},
		onSnapshot: () => { state.snapshots++; },
		onError: () => { state.errors++; },
		now: () => state.clock,
		isHidden: () => state.hidden
	});
	return { poller, state };
}

async function main() {
	// --- the interval ------------------------------------------------------
	section('poll interval');
	// LuCI's poll.add(interval) takes SECONDS; the design target is 10 seconds,
	// which is 10000 ms on the wire timer.
	check(POLL_SECONDS === 10, 'the poll interval is 10 seconds', String(POLL_SECONDS));
	check(POLL_SECONDS * 1000 === 10000, 'the poll interval is exactly 10000 ms',
		String(POLL_SECONDS * 1000));

	// --- hidden tab --------------------------------------------------------
	section('hidden tab');
	{
		const { poller, state } = harness();
		await poller.tick();
		const before = state.calls;
		check(before === 1, 'a visible refresh polls', String(before));
		state.hidden = true;
		await poller.tick();
		check(state.calls === before, 'a refresh is skipped while document.hidden is true',
			'status calls went from ' + before + ' to ' + state.calls);
		// Twice, so the skip is a decision and not a one-off guard.
		await poller.tick();
		check(state.calls === before, 'a second hidden refresh is also skipped',
			String(state.calls));
		// Becoming visible again must resume polling, or the page would stay stale
		// forever after the user returns to the tab.
		state.hidden = false;
		await poller.tick();
		check(state.calls === before + 1, 'a visible refresh polls again', String(state.calls));
	}

	// --- serialized requests ----------------------------------------------
	section('one request in flight');
	{
		let release = null;
		const { poller, state } = harness({
			status: (inner) => {
				if (inner.calls !== 1) return Promise.resolve(statusPayload());
				return new Promise((resolve) => { release = resolve; });
			}
		});
		const inflight = poller.tick();
		check(state.calls === 1, 'the poll under test made its request', String(state.calls));
		const second = poller.tick();
		check(state.calls === 1, 'a second refresh is skipped while one is in flight',
			'status calls: 1 -> ' + state.calls);
		await second;
		check(typeof release === 'function', 'the in-flight request is still pending',
			String(typeof release));
		release(statusPayload());
		await inflight;
		check(poller.inflight === false, 'the in-flight flag is cleared when the request settles');
		await poller.tick();
		check(state.calls === 2, 'polling resumes once the in-flight request settles',
			String(state.calls));
	}

	// --- backoff -----------------------------------------------------------
	section('backoff after repeated failures');
	{
		let failNow = true;
		const { poller, state } = harness({
			status: () => failNow
				? Promise.reject(new Error('rpc unavailable'))
				: Promise.resolve(statusPayload())
		});
		const expectedDelays = [10000, 20000, 40000, 60000, 60000];
		const observedDelays = [];
		for (let attempt = 0; attempt < expectedDelays.length; attempt++) {
			// Advance the clock past the previous backoff, which is what a real page
			// does between two poll ticks. Without this the second iteration would be
			// skipped by the previous delay and only prove the guard, not the growth.
			if (attempt > 0) state.clock += expectedDelays[attempt - 1];
			const before = state.calls;
			await poller.tick();
			check(state.calls === before + 1,
				'failure ' + (attempt + 1) + ' actually made a request', String(state.calls));
			observedDelays.push(poller.nextRetry - state.clock);
		}
		check(JSON.stringify(observedDelays) === JSON.stringify(expectedDelays),
			'the delay doubles and stops at 60000 ms', 'observed ' + JSON.stringify(observedDelays));
		check(observedDelays.every((delay) => delay <= 60000),
			'no delay exceeds 60000 ms', JSON.stringify(observedDelays));
		for (let index = 1; index < observedDelays.length; index++) {
			if (observedDelays[index] < observedDelays[index - 1])
				check(false, 'the delay never shrinks while failures continue',
					JSON.stringify(observedDelays));
		}
		check(poller.failures === expectedDelays.length,
			'every failure was counted', String(poller.failures));

		// The delay must actually suppress requests, not just be recorded.
		const beforeWait = state.calls;
		state.clock += 60000 - 1;
		await poller.tick();
		check(state.calls === beforeWait, 'no request is made before the backoff expires',
			String(state.calls));
		state.clock += 1;
		await poller.tick();
		check(state.calls === beforeWait + 1, 'a request resumes when the backoff expires',
			String(state.calls));

		// A success must clear the failure count, or one outage would leave the page
		// on the 60 second timer for the rest of the session.
		failNow = false;
		state.clock += 60000;
		await poller.tick();
		check(poller.failures === 0, 'a successful refresh resets the failure count',
			String(poller.failures));
		check(poller.nextRetry === 0, 'a successful refresh clears the backoff',
			String(poller.nextRetry));
		const afterRecovery = state.calls;
		await poller.tick();
		check(state.calls === afterRecovery + 1, 'polling is immediate again after recovery',
			String(state.calls));
	}

	// --- the backoff table itself ------------------------------------------
	section('backoff table');
	{
		const table = [1, 2, 3, 4, 5, 6].map((failures) => nextRetryDelayMs(failures));
		check(JSON.stringify(table) === JSON.stringify([10000, 20000, 40000, 60000, 60000, 60000]),
			'nextRetryDelayMs doubles from 10 s and caps at 60 s', JSON.stringify(table));
		check(nextRetryDelayMs(0) > 0 && nextRetryDelayMs(0) <= 10000,
			'a zero count stays within the base delay', String(nextRetryDelayMs(0)));
	}

	// --- a status reply cannot reach the form ------------------------------
	section('status updates leave the form alone');
	{
		// The form values are React state initialised once from uci and written
		// only by the user's edits. A status reply is mapped through applySnapshot,
		// which returns the live snapshot and the scan state - nothing else - so
		// there is no path from a poll to a form value.
		const reply = statusPayload({
			services: { upnp: { enabled: true, running: false }, cast: { enabled: true, running: true } },
			conflicts: ['Legacy binaries found in /usr/bin.'],
			scan: { running: true, last_scan: 1700000100, error: null },
			devices: [{
				engine: 'upnp', udn: 'uuid:demo-1', original_name: 'Demo Speaker',
				name: 'Kitchen', model: 'Other Model', manufacturer: 'Other Manufacturer',
				address: '192.0.2.99', last_seen: 1700000200, online: false, configured: true
			}]
		});
		const before = JSON.stringify(reply);
		const snapshot = applySnapshot(reply);
		check(JSON.stringify(Object.keys(snapshot).sort()) === JSON.stringify(['scan', 'status']),
			'applySnapshot returns only the snapshot and the scan state',
			Object.keys(snapshot).join(','));
		check(JSON.stringify(reply) === before,
			'applySnapshot does not mutate the reply', 'the reply changed in place');
		// A snapshot carries no per-field state: no key may look like a form value.
		const formLike = Object.keys(snapshot).filter((key) =>
			/max_volume|media_volume|latency|codec|artwork|http_length|stop_receiver|upnp_max/.test(key));
		check(formLike.length === 0, 'a snapshot carries no form values', formLike.join(','));

		// The scan block is derived, not copied, so two different replies cannot
		// produce the same scan state by accident.
		const quiet = applySnapshot(statusPayload({
			scan: { running: false, last_scan: null, error: null },
			services: { upnp: { enabled: false }, cast: { enabled: false } }
		}));
		check(quiet.scan.disabled === true, 'scan is disabled when no engine is enabled');
		check(snapshot.scan.running === true, 'a running scan is reported as running');
		check(snapshot.scan.disabled === true, 'scan is disabled while one is running');
		check(quiet.scan.error === null && quiet.scan.last_scan === null,
			'a quiet scan state has no error and no timestamp');
	}

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
