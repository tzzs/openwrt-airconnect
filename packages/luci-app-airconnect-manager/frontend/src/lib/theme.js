/**
 * Theme state for the AirConnect workspace: light / dark / system.
 *
 * Storage mirrors the i18n preference pattern: a single string under
 * `airconnect.theme`. `system` defers to the OS via `prefers-color-scheme`,
 * so the page can follow the user's OS setting without us polling it.
 *
 * Every browser API (`localStorage`, `matchMedia`, `classList`) is gated on
 * existence and wrapped in try/catch, because the bundle is imported both in a
 * browser and by the Node test suites (which have none of these globals). The
 * tests import this module to assert its shape, so it must never throw at
 * import time or when called in a headless environment.
 */

/**
 * The three selectable themes. `system` means "follow the OS"; the other two
 * pin the workspace to a specific palette regardless of OS setting.
 *
 * Style contract for the CSS side (handled by styles.css, not here):
 *   `.ac-root.ac-theme-dark`  -> dark tokens
 *   `.ac-root.ac-theme-light` -> light tokens
 *   `.ac-root` (no theme class) -> follow `prefers-color-scheme`
 */
export const THEMES = [
	{ value: 'system', label: 'System' },
	{ value: 'light', label: 'Light' },
	{ value: 'dark', label: 'Dark' }
];

/** localStorage key; kept in sync with the i18n preference key namespace. */
const STORAGE_KEY = 'airconnect.theme';

/** The set of values we accept; anything else falls back to `system`. */
const VALID_THEMES = new Set(['system', 'light', 'dark']);

/**
 * Read the stored theme preference. Returns `system` when the value is
 * missing, unrecognized, or unreadable (private mode / disabled storage), so a
 * fresh or corrupted state always degrades to the OS default rather than a
 * blank page.
 *
 * @returns {'system'|'light'|'dark'}
 */
export function detectTheme() {
	try {
		if (typeof localStorage === 'undefined' || localStorage === null) {
			return 'system';
		}
		const stored = localStorage.getItem(STORAGE_KEY);
		if (stored && VALID_THEMES.has(stored)) {
			return stored;
		}
	} catch {
		// localStorage can throw in private mode or sandboxed iframes; the
		// safe default is always `system`.
	}
	return 'system';
}

/**
 * Persist the user's theme choice. Silently no-ops when storage is unavailable
 * (private mode, restricted environments), so the caller never has to branch.
 *
 * @param {'system'|'light'|'dark'} theme
 * @returns {void}
 */
export function writeTheme(theme) {
	try {
		if (typeof localStorage === 'undefined' || localStorage === null) {
			return;
		}
		if (!VALID_THEMES.has(theme)) {
			return;
		}
		localStorage.setItem(STORAGE_KEY, theme);
	} catch {
		// Swallow: a write failure must not break the in-memory theme switch.
	}
}

/**
 * Resolve a theme value to a concrete palette. `system` is expanded by asking
 * the OS (`prefers-color-scheme: dark`); `light` and `dark` pass through
 * unchanged. When `matchMedia` is unavailable or throws (Node, very old
 * browsers), `system` resolves to `light` — the palette with the widest
 * readability margin when we cannot detect preference.
 *
 * @param {'system'|'light'|'dark'} theme
 * @returns {'light'|'dark'}
 */
export function resolveTheme(theme) {
	if (theme !== 'system') {
		return theme === 'dark' ? 'dark' : 'light';
	}
	try {
		if (typeof window === 'undefined' || window === null ||
			typeof window.matchMedia !== 'function') {
			return 'light';
		}
		const mql = window.matchMedia('(prefers-color-scheme: dark)');
		return mql && mql.matches ? 'dark' : 'light';
	} catch {
		return 'light';
	}
}

/**
 * Apply a resolved theme to a root element by toggling class names.
 *
 * Both `ac-theme-light` and `ac-theme-dark` are removed first, then the
 * matching one is added. `system` adds neither, leaving the CSS
 * `@media (prefers-color-scheme)` blocks to decide — this is what lets a
 * `system` choice react to OS changes with zero re-rendering.
 *
 * `root` may be null (e.g. before mount, or in a headless test), in which case
 * this is a no-op rather than a crash.
 *
 * @param {Element|null} root
 * @param {'system'|'light'|'dark'} theme
 * @returns {void}
 */
export function applyTheme(root, theme) {
	if (!root || typeof root.classList === 'undefined' || root.classList === null) {
		return;
	}
	try {
		root.classList.remove('ac-theme-light', 'ac-theme-dark');
		if (theme === 'light') {
			root.classList.add('ac-theme-light');
		} else if (theme === 'dark') {
			root.classList.add('ac-theme-dark');
		}
		// theme === 'system' -> add neither; CSS media query governs.
	} catch {
		// classList is read-only on some exotic elements; ignore safely.
	}
}

/**
 * Subscribe to OS color-scheme changes. Intended for the `system` mode: when
 * the OS flips between light and dark, the callback fires so the host can
 * re-resolve and re-apply. The host is responsible for only acting when the
 * current selection is `system`; this watcher fires regardless, which keeps it
 * cheap to leave subscribed even when the user has pinned a theme.
 *
 * Uses the modern `addEventListener('change', ...)` and falls back to the
 * deprecated `addListener` for older Safari / legacy WebViews found on some
 * router admin shells. Returns an unsubscribe function; in environments
 * without `matchMedia` (Node, SSR) it is an empty noop so callers can always
 * invoke the returned cleanup without feature-checking.
 *
 * @param {() => void} callback
 * @returns {() => void}
 */
export function watchSystemTheme(callback) {
	if (typeof callback !== 'function') {
		return () => {};
	}
	try {
		if (typeof window === 'undefined' || window === null ||
			typeof window.matchMedia !== 'function') {
			return () => {};
		}
		const mql = window.matchMedia('(prefers-color-scheme: dark)');
		if (!mql) {
			return () => {};
		}
		const handler = () => {
			try {
				callback();
			} catch {
				// A failing callback must not break the media-query listener.
			}
		};
		if (typeof mql.addEventListener === 'function') {
			mql.addEventListener('change', handler);
			return () => {
				try {
					mql.removeEventListener('change', handler);
				} catch {
					// Already detached or unavailable; nothing to undo.
				}
			};
		}
		// Legacy fallback: older browsers expose addListener/removeListener.
		if (typeof mql.addListener === 'function') {
			mql.addListener(handler);
			return () => {
				try {
					mql.removeListener(handler);
				} catch {
					// Already detached or unavailable; nothing to undo.
				}
			};
		}
	} catch {
		// matchMedia itself threw; nothing to subscribe to.
	}
	return () => {};
}
