'require view';
'require uci';
'require rpc';
'require ui';
'require poll';

// Shared loader for the two AirConnect LuCI views.
//
// The page is a React + shadcn/ui bundle (app.js + app.css) built from
// frontend/ by `npm run build`. Neither file is committed: they are produced
// in CI (and by scripts/build-local.sh) before the SDK compiles this package.
//
// The two views are the same application with a different body, so the loading
// logic lives here instead of being written twice. `mode` tells the app which
// body to render.
//
// Neither view defines handleSave / handleSaveApply / handleReset. LuCI's base
// `View` class defines all three, so omitting them still renders a second,
// differently styled footer row. Each view explicitly sets them to null.

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

function createRoot(mode) {
	var root = E('div', { 'class': 'ac-root' });
	root.appendChild(
		E('link', { rel: 'stylesheet', href: L.resource('airconnect-manager/app.css') })
	);
	var mountNode = E('div', { 'class': 'ac-app' });
	root.appendChild(mountNode);

	loadApp()
		.then(function (app) {
			root.app = app.mount(mountNode, {
				uci: uci,
				rpc: rpc,
				ui: ui,
				poll: poll,
				translate: _,
				mode: mode
			});
		})
		.catch(function (error) {
			mountNode.appendChild(
				E('p', { 'class': 'ac-load-error' },
					'Failed to load the AirConnect UI: ' +
					(error && error.message ? error.message : String(error)))
			);
		});

	return root;
}

return view.extend({
	loadApp: loadApp,
	createRoot: createRoot
});
