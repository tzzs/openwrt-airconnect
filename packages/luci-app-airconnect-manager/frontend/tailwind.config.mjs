/** @type {import('tailwindcss').Config} */
export default {
	// Argon, the iStoreOS theme, toggles its own dark mode with a `data-darkmode`
	// attribute. `main.jsx` mirrors that onto a `.dark` class on the app root so
	// Tailwind only has to understand one convention.
	darkMode: ['class'],
	content: ['./src/**/*.{js,jsx}'],
	// LuCI and Argon already ship a global reset. Tailwind's preflight would
	// re-reset the sidebar, the header and every `cbi-*` widget, so it stays off
	// and `src/styles.css` carries a scoped box-sizing/border reset instead.
	corePlugins: { preflight: false },
	// Scope every generated utility to the app root and let it win over Argon's
	// Bootstrap-derived utilities (`.hidden`, `.block`, ...) that share names.
	important: '.ac-root',
	theme: {
		extend: {
			colors: {
				border: 'hsl(var(--border))',
				input: 'hsl(var(--input))',
				ring: 'hsl(var(--ring))',
				background: 'hsl(var(--background))',
				foreground: 'hsl(var(--foreground))',
				primary: {
					DEFAULT: 'hsl(var(--primary))',
					foreground: 'hsl(var(--primary-foreground))'
				},
				secondary: {
					DEFAULT: 'hsl(var(--secondary))',
					foreground: 'hsl(var(--secondary-foreground))'
				},
				destructive: {
					DEFAULT: 'hsl(var(--destructive))',
					foreground: 'hsl(var(--destructive-foreground))'
				},
				muted: {
					DEFAULT: 'hsl(var(--muted))',
					foreground: 'hsl(var(--muted-foreground))'
				},
				accent: {
					DEFAULT: 'hsl(var(--accent))',
					foreground: 'hsl(var(--accent-foreground))'
				},
				popover: {
					DEFAULT: 'hsl(var(--popover))',
					foreground: 'hsl(var(--popover-foreground))'
				},
				card: {
					DEFAULT: 'hsl(var(--card))',
					foreground: 'hsl(var(--card-foreground))'
				},
				success: {
					DEFAULT: 'hsl(var(--success))',
					foreground: 'hsl(var(--success-foreground))'
				},
				warning: {
					DEFAULT: 'hsl(var(--warning))',
					foreground: 'hsl(var(--warning-foreground))'
				}
			},
			borderRadius: {
				lg: 'var(--radius)',
				md: 'calc(var(--radius) - 2px)',
				sm: 'calc(var(--radius) - 4px)'
			},
			fontFamily: {
				sans: 'inherit',
				mono: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace'
			}
		}
	},
	plugins: []
};
