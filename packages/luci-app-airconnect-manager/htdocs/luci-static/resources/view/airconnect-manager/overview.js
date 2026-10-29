'use strict';
'require view';
'require uci';
'require rpc';
'require ui';
'require poll';

// The page itself is a React + shadcn/ui bundle (app.js + app.css) built from
// frontend/ by `npm run build`. Neither file is committed: they are produced in
// CI (and by scripts/build-local.sh) before the SDK compiles this package.
//
// This file stays a LuCI class because that is what LuCI's router loads, and it
// owns the page globals the app needs (`uci`, `rpc`, `ui`, `poll`, `_`). It
// mounts the app into a container; saving, applying and reloading all live in
// the app's own header, not in a LuCI footer.
//
// The footer buttons are suppressed by setting handleSave / handleSaveApply /
// handleReset to null below. Leaving them undefined is not enough: LuCI's base
// `View` class defines all three, so `this.handleSave` is always truthy and
// addFooter() would render a second, differently styled "Save and apply / Save
// / Reset" row under a page whose header already provides them. `null` makes
// the tests in addFooter() fail without touching the base class.
//
// Do not remove these three properties: the page has no cbi-map to save, so the
// inherited handlers would only add buttons that do nothing.

var configName = 'airconnect-manager';

// Memoised so a re-render does not inject the script twice.
var appPromise = null;

function loadApp() {
	if (appPromise) return appPromise;
	appPromise = new Promise(function (resolve, reject) {
		if (window.AirConnectApp && typeof window.AirConnectApp.mount === 'function') {
			resolve(window.AirConnectApp);
			return;
		}
		var url = L.resource('airconnect-manager/app.js');
		var script = document.createElement('script');
		script.src = url;
		script.async = true;
		script.onload = function () {
			if (window.AirConnectApp && typeof window.AirConnectApp.mount === 'function')
				resolve(window.AirConnectApp);
			else
				reject(new Error('app.js loaded but did not define AirConnectApp'));
		};
		script.onerror = function () {
			reject(new Error('could not load ' + url));
		};
		document.head.appendChild(script);
	});
	return appPromise;
}

return view.extend({
	// Load the UCI config and the app bundle before LuCI calls render(), so the
	// first paint already has the React tree instead of an empty container.
	load: function () {
		return Promise.all([uci.load(configName), loadApp()]);
	},

	// See the comment at the top of this file: these must be explicit nulls so
	// addFooter() skips the cbi-page-actions row entirely.
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	render: function () {
		var self = this;
		var root = E('div', { 'class': 'ac-root' });
		root.appendChild(
			E('link', { rel: 'stylesheet', href: L.resource('airconnect-manager/app.css') })
		);
		var mountNode = E('div', {});
		root.appendChild(mountNode);

		loadApp()
			.then(function (app) {
				// Kept so the mounted instance can be inspected or unmounted from
				// the console; the page does not delegate its buttons to it.
				self.app = app.mount(mountNode, {
					uci: uci,
					rpc: rpc,
					ui: ui,
					poll: poll,
					translate: _
				});
			})
			.catch(function (error) {
				root.appendChild(
					E('p', { 'class': 'text-destructive' },
						'Failed to load the AirConnect UI: ' +
						(error && error.message ? error.message : String(error)))
				);
			});

		return root;
	}
});
