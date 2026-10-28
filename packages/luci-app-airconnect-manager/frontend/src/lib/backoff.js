/**
 * Poll backoff, extracted from the page's refresh loop so it can be unit-tested
 * without a browser.
 *
 * The status fetch is retried with exponential backoff (base 10s, hard cap 60s),
 * so a manager that has been down for a while does not hammer ubus on every
 * failed tick. `failures` is the count of consecutive failures so far.
 */
export function nextRetryDelayMs(failures) {
	const count = Number.isFinite(failures) && failures > 0 ? failures : 0;
	return Math.min(60000, 10000 * Math.pow(2, count - 1));
}
