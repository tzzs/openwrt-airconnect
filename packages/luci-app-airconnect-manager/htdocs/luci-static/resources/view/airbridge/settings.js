'require view';
'require uci';
'require rpc';
'require ui';
'require poll';
'require view.airbridge.common as common';

// Compatibility view for clients that still request the old settings view.
// New menu and in-app navigation stay on airbridge/overview.

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
  },
});
