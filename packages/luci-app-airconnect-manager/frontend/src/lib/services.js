/**
 * Bridge between LuCI's page globals and the React app.
 *
 * The LuCI view (`overview.js`) owns the LuCI objects (`uci`, `rpc`, `ui`,
 * `poll`, `L`, `_`); it hands them to `mountApp` in `main.jsx`. Nothing in the
 * React tree touches `window` directly, so the same components can be rendered
 * by a test with a fake bridge.
 *
 * `createServices(context)` normalises those globals into the small API the app
 * uses: promises for the RPC calls, uci accessors, polling and notifications.
 */

export function createServices(context) {
	const { uci, rpc, ui, poll, translate } = context;
	const t = typeof translate === 'function' ? translate : (s) => s;

	const call = {
		status: rpc.declare({ object: 'airconnect.manager', method: 'status', expect: {} }),
		scan: rpc.declare({ object: 'airconnect.manager', method: 'scan', expect: {} }),
		logs: rpc.declare({ object: 'airconnect.manager', method: 'logs', expect: {} }),
		validate: rpc.declare({
			object: 'airconnect.manager', method: 'validate', params: ['config'], expect: {}
		}),
		action: rpc.declare({
			object: 'airconnect.manager', method: 'action', params: ['action'], expect: {}
		})
	};

	return {
		t,
		uci,
		ui,
		poll,
		async loadConfig() {
			await uci.load('airconnect-manager');
		},
		get(section, option) {
			return uci.get('airconnect-manager', section, option);
		},
		sections(type, callback) {
			return uci.sections('airconnect-manager', type, callback);
		},
		set(section, option, value) {
			uci.set('airconnect-manager', section, option, value);
		},
		add(type) {
			return uci.add('airconnect-manager', type);
		},
		remove(section) {
			return uci.remove('airconnect-manager', section);
		},
		save() {
			return uci.save();
		},
		status() {
			return call.status();
		},
		scan() {
			return call.scan();
		},
		logs() {
			return call.logs();
		},
		validate(config) {
			return call.validate(config);
		},
		action(name) {
			return call.action(name);
		},
		notify(message, kind) {
			if (!ui || typeof ui.addNotification !== 'function') return;
			// LuCI renders the node it is given; a plain object would render as
			// "[object Object]". Text is set as text, never as HTML.
			const node = document.createElement('p');
			node.textContent = message;
			ui.addNotification(null, node, kind || 'info');
		},
		changesInit() {
			return ui && ui.changes && ui.changes.init ? ui.changes.init() : Promise.resolve();
		},
		changesApply(rollback) {
			return ui && ui.changes && ui.changes.apply ? ui.changes.apply(rollback) : Promise.resolve();
		},
		pollAdd(fn, seconds) {
			if (poll && typeof poll.add === 'function') poll.add(fn, seconds);
		},
		pollRemove(fn) {
			if (poll && typeof poll.remove === 'function') poll.remove(fn);
		}
	};
}
