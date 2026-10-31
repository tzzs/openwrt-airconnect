'require view';
'require uci';
'require rpc';
'require ui';
'require poll';
'require view.airconnect-manager.common as common';

// The device workspace. The global configuration lives in its own view
// (settings.js) and its own menu entry, so neither page has to fit both
// purposes into one layout.

var configName = 'airconnect-manager';

return view.extend({
	load: function () {
		return Promise.all([uci.load(configName), common.loadApp()]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	render: function () {
		return common.createRoot('overview');
	}
});
