/**
 * The status poller, extracted from the React tree so its contract can be
 * executed without a browser.
 *
 * docs/PERFORMANCE.zh-CN.md and docs/ARCHITECTURE.zh-CN.md promise four things
 * about the page: it polls every 10 seconds, pauses while the tab is hidden,
 * never has two requests in flight, and backs off to 60 seconds after repeated
 * failures. Those four claims decide whether opening a second tab doubles the
 * router's RPC load, so they live here as a plain object the test suite drives
 * with a fake clock instead of as effects inside a component.
 */

import { nextRetryDelayMs } from './backoff.js';

/** The polling interval, in seconds. LuCI's `poll.add` takes seconds. */
export const POLL_SECONDS = 10;

/**
 * What one status reply is allowed to update.
 *
 * A status reply updates the live snapshot and the scan state. It deliberately
 * cannot touch the form: the field values come from uci once and then belong to
 * the user until they save, so a poll arriving mid-edit must not overwrite what
 * they typed.
 */
export function applySnapshot(data) {
	const scan = (data && data.scan) || {};
	const services = (data && data.services) || {};
	return {
		status: data,
		scan: {
			running: !!scan.running,
			error: scan.error || null,
			last_scan: scan.last_scan || null,
			disabled: !!scan.running || !(
				(services.upnp && services.upnp.enabled) ||
				(services.cast && services.cast.enabled)
			)
		}
	};
}

/**
 * @param {object} options
 * @param {() => Promise<object>} options.fetch  One status request.
 * @param {(data: object) => void} options.onSnapshot  Called with a good reply.
 * @param {(error: Error) => void} options.onError  Called with a failed one.
 * @param {() => number} [options.now]  Injectable clock, for tests.
 * @param {() => boolean} [options.isHidden]  Injectable tab visibility.
 */
export function createPoller(options) {
	const fetch = options.fetch;
	const onSnapshot = options.onSnapshot;
	const onError = options.onError;
	const now = options.now || function () { return Date.now(); };
	const isHidden = options.isHidden || function () { return false; };

	let failures = 0;
	let nextRetry = 0;
	let inflight = false;

	return {
		/** One poll. Returns when the request settles, or immediately if skipped. */
		async tick() {
			if (isHidden()) return;
			if (inflight) return;
			if (now() < nextRetry) return;
			inflight = true;
			try {
				const data = await fetch();
				failures = 0;
				nextRetry = 0;
				onSnapshot(data);
			} catch (error) {
				failures += 1;
				nextRetry = now() + nextRetryDelayMs(failures);
				onError(error);
			} finally {
				inflight = false;
			}
		},
		get failures() { return failures; },
		get nextRetry() { return nextRetry; },
		get inflight() { return inflight; }
	};
}
