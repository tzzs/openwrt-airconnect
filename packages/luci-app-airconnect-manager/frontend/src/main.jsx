import { createRoot } from 'react-dom/client';

import { App } from './App.jsx';
import { createServices } from './lib/services.js';
import './styles.css';

/**
 * Mount the app into a LuCI-provided container.
 *
 * The LuCI view owns the page globals (`uci`, `rpc`, `ui`, `poll`, `_`); it
 * passes them in `context`, so nothing in the React tree reads `window`
 * directly and the same components can be rendered against a fake context in a
 * test. Saving is driven by the page's own toolbar (the view defines no
 * handleSave/handleSaveApply, so LuCI renders no footer buttons), which leaves
 * `unmount` as the only thing the view needs back.
 *
 * `themeHost` is the `.ac-root` element the view wraps us in: the CSS tokens
 * live on that element, and it sits outside the React tree, so the app cannot
 * reach it with a ref.
 */
export function mount(container, context) {
	const services = createServices(context);
	const themeHost = typeof container.closest === 'function'
		? (container.closest('.ac-root') || container)
		: container;
	const root = createRoot(container);
	root.render(
		<App context={{ services, themeHost }} />
	);
	return {
		unmount: () => root.unmount()
	};
}

// The IIFE build exposes this global for the LuCI view to call.
window.AirConnectApp = { mount };
