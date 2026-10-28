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
 * test. The return value is the small API the view's `handleSave` /
 * `handleSaveApply` delegate to, because LuCI drives the footer buttons, not the
 * app.
 */
export function mount(container, context) {
	const services = createServices(context);
	const api = { save: null, saveApply: null };
	const root = createRoot(container);
	root.render(
		<App
			context={{ services }}
			onReady={(handlers) => {
				api.save = handlers.save;
				api.saveApply = handlers.saveApply;
			}}
		/>
	);
	return {
		save: () => (api.save ? api.save() : Promise.resolve()),
		saveApply: (rollback) => (api.saveApply ? api.saveApply(rollback) : Promise.resolve()),
		unmount: () => root.unmount()
	};
}

// The IIFE build exposes this global for the LuCI view to call.
window.AirConnectApp = { mount };
