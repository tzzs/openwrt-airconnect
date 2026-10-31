'require view';
'require uci';
'require rpc';
'require ui';
'require poll';
'require view.airconnect-manager.common as common';

// The global configuration, as its own page.
// See common.js for the shared bundle loader and the app's mode switch.

var configName = 'airconnect-manager';

return view.extend({
	load: function () {
		return Promise.all([uci.load(configName), common.loadApp()]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	render: function () {
		return common.createRoot('settings');
	}
});
