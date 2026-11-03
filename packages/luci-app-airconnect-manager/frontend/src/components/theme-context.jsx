import { createContext, useContext } from 'react';

/**
 * The theme preference, for content Radix renders outside `.ac-root`.
 *
 * The drawer and the select menu are portalled to `<body>` so they escape the
 * page card's `overflow: hidden`. That also puts them outside `.ac-root`, which
 * is where the colour tokens and the button reset live: without a theme class
 * of their own they inherited Argon's text colour and no background, so the
 * interface dropdown was invisible in dark mode.
 *
 * Portalled content therefore carries `ac-portal` plus the same
 * `ac-theme-light` / `ac-theme-dark` class the root uses. `system` adds
 * neither, exactly like the root, which leaves the stylesheet's
 * `prefers-color-scheme` block to decide.
 */
export const ThemeContext = createContext('system');

export function useThemeClass() {
	const theme = useContext(ThemeContext);
	if (theme === 'dark') return 'ac-theme-dark';
	if (theme === 'light') return 'ac-theme-light';
	return '';
}
