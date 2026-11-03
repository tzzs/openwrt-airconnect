'require view';
'require uci';
'require rpc';
'require ui';
'require poll';
'require view.airbridge.common as common';

// The device workspace and global settings share this LuCI view. The React app
// selects the visible page from the URL hash, keeping LuCI's navigation shell
// mounted while moving between them.

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
