/**
 * The two AirBridge pages, and how to move between them.
 *
 * LuCI serves both from the same view path, one level apart:
 *
 *   /…/admin/services/airbridge/           the device workspace
 *   /…/admin/services/airbridge/settings   the global settings
 *
 * The prefix before that is the dispatcher path (`/cgi-bin/luci` by default,
 * but any string is allowed), so it is never hardcoded: each URL is derived
 * from the one the browser is on. That keeps a custom dispatcher working and
 * is why these are pure functions the test suite can check.
 */

/** The settings page next to the current one. Already there? Stay put. */
export function settingsPageUrl(href) {
	const url = new URL(href);
	const path = url.pathname.replace(/\/+$/, '');
	url.pathname = /\/settings$/.test(path) ? path : path + '/settings';
	url.search = '';
	url.hash = '';
	return url.href;
}

/**
 * The workspace page above the current one.
 *
 * Only the trailing `settings` segment is removed, so the result is the page
 * the settings view hangs off, whatever the dispatcher prefix is. A URL that
 * does not end in `settings` is returned unchanged rather than guessed at:
 * stripping a different last segment could land on a page that does not exist.
 */
export function parentPageUrl(href) {
	const url = new URL(href);
	const path = url.pathname.replace(/\/+$/, '');
	const parent = path.replace(/\/settings$/, '');
	url.pathname = parent === '' ? '/' : parent;
	url.search = '';
	url.hash = '';
	return url.href;
}
