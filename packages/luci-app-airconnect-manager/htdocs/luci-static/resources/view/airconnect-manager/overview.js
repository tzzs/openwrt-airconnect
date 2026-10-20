'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require ui';
'require poll';

var configName = 'airconnect-manager';
var callStatus = rpc.declare({ object: 'airconnect.manager', method: 'status', expect: {} });
var callScan = rpc.declare({ object: 'airconnect.manager', method: 'scan', expect: {} });
var callLogs = rpc.declare({ object: 'airconnect.manager', method: 'logs', expect: {} });
var callValidate = rpc.declare({ object: 'airconnect.manager', method: 'validate', params: ['config'], expect: {} });
var callAction = rpc.declare({ object: 'airconnect.manager', method: 'action', params: ['action'], expect: {} });
var mainKeys = ['enabled', 'interface', 'airupnp', 'aircast', 'codec', 'latency', 'max_volume', 'media_volume', 'log_level'];
var deviceKeys = ['engine', 'udn', 'enabled', 'name', 'max_volume', 'media_volume', 'codec', 'latency'];

function text(value) { return value == null || value === '' ? _('Not provided') : String(value); }
function key(device) { return device.engine + '\n' + device.udn; }
function time(value) {
	if (!value) return _('Not provided');
	var date = new Date(Number(value) * 1000);
	return isNaN(date.getTime()) ? _('Not provided') : date.toLocaleString();
}
function badge(label, tone) { return E('span', { 'class': 'ac-badge ac-' + (tone || 'neutral') }, label); }
function replace(node, children) { node.replaceChildren.apply(node, Array.isArray(children) ? children : [children]); }
function errorMessage(error) { return error && error.message ? error.message : String(error); }
function safeName(section, value) {
	if (!value) return true;
	if (new TextEncoder().encode(value).length > 63) return _('Use at most 63 UTF-8 bytes for the AirPlay name.');
	return /[\x00-\x1f\x7f]/.test(value) ? _('Control characters are not allowed.') : true;
}
function latency(section, value) {
	return !value || /^(?:\d{1,4}|10000):(?:\d{1,4}|10000)$/.test(value) || _('Use two values from 0 to 10000, separated by a colon.');
}
function volume(section, value) {
	return !value || (/^(?:0(?:\.\d+)?|1(?:\.0+)?)$/.test(value)) || _('Enter a number from 0 to 1.');
}
function option(section, type, name, label, description) {
	var o = section.option(type, name, label, description);
	o.rmempty = true;
	return o;
}
function codecs(section, inherited) {
	var o = option(section, form.ListValue, 'codec', _('Audio format'), _('FLAC can use more CPU. Choose a format supported by your speaker.'));
	if (inherited) o.value('', _('Inherit global setting'));
	['flac', 'pcm', 'wav', 'mp3', 'aac'].forEach(function(value) { o.value(value, value.toUpperCase()); });
	return o;
}
function canonicalConfig() {
	var main = {}, devices = [];
	mainKeys.forEach(function(field) { var v = uci.get(configName, 'main', field); if (v != null) main[field] = v; });
	uci.sections(configName, 'device', function(s) {
		var item = { section: s['.name'] };
		deviceKeys.forEach(function(field) { if (s[field] != null) item[field] = s[field]; });
		devices.push(item);
	});
	return { main: main, devices: devices };
}

return view.extend({
	load: function() {
		return Promise.all([uci.load(configName), callStatus().then(function(data) { return { data: data }; }, function(error) { return { error: errorMessage(error) }; })]);
	},
	markDirty: function() {
		this.dirty = true;
		this.saveState.textContent = _('Unsaved changes');
		this.saveState.className = 'ac-save-state ac-warning';
	},
	notify: function(message, isError) {
		ui.addNotification(null, E('p', {}, message), isError ? 'danger' : 'info');
	},
	perform: function(button, task) {
		if (button.disabled) return Promise.resolve();
		button.disabled = true;
		button.setAttribute('aria-busy', 'true');
		return Promise.resolve().then(task).catch(L.bind(function(error) {
			this.notify(errorMessage(error), true);
		}, this)).finally(function() { button.disabled = false; button.removeAttribute('aria-busy'); });
	},
	makeMainForm: function() {
		var m = new form.Map(configName), s = m.section(form.NamedSection, 'main', 'main', _('General settings'));
		s.addremove = false;
		var o = option(s, form.Flag, 'enabled', _('Enable AirConnect'), _('Changes take effect after Save & Apply. Applying briefly disconnects AirPlay.'));
		o.rmempty = false;
		o = option(s, form.Value, 'interface', _('LAN interface'), _('Bind discovery and AirPlay to your local network interface.'));
		o.rmempty = false;
		o.validate = function(sid, value) { return /^[a-zA-Z0-9_.:-]{1,15}$/.test(value) || _('Enter an interface name of at most 15 characters.'); };
		o = option(s, form.Flag, 'airupnp', _('UPnP / DLNA speakers')); o.rmempty = false;
		o = option(s, form.Flag, 'aircast', _('Chromecast speakers')); o.rmempty = false;
		o = option(s, form.Value, 'max_volume', _('UPnP volume limit'), _('Default maximum volume, from 1 to 100.'));
		o.datatype = 'range(1,100)'; o.rmempty = false;
		o = option(s, form.Value, 'media_volume', _('Chromecast media volume'), _('Default media volume, from 0 to 1. This is not a volume limit.'));
		o.validate = volume; o.rmempty = false;
		this.maps.push(m);
		var advanced = new form.Map(configName), a = advanced.section(form.NamedSection, 'main', 'main');
		codecs(a, false).rmempty = false;
		o = option(a, form.Value, 'latency', _('Buffer and latency'), _('Format: 1000:2000. Lower values may cause audio dropouts.')); o.validate = latency; o.rmempty = false;
		o = option(a, form.ListValue, 'log_level', _('Log detail'));
		['error', 'warn', 'info', 'debug'].forEach(function(v) { o.value(v, v); }); o.rmempty = false;
		this.maps.push(advanced);
		return Promise.all([m.render(), advanced.render()]).then(function(nodes) {
			return E('div', {}, [nodes[0], E('details', { 'class': 'ac-advanced' }, [E('summary', {}, _('Advanced settings')), nodes[1]])]);
		});
	},
	makeDeviceForm: function(device, sectionId) {
		var m = new form.Map(configName), s = m.section(form.NamedSection, sectionId, 'device');
		s.addremove = false;
		var o = option(s, form.Flag, 'enabled', _('Enable bridging')); o.rmempty = false;
		o = option(s, form.Value, 'name', _('AirPlay name'), _('Changes only the virtual AirPlay receiver name. Leave empty to use the original name.'));
		o.placeholder = device.original_name || _('Original name'); o.validate = safeName;
		if (device.engine === 'upnp') {
			o = option(s, form.Value, 'max_volume', _('Volume limit'), _('Leave empty to inherit the global UPnP limit.'));
			o.datatype = 'range(1,100)'; o.placeholder = uci.get(configName, 'main', 'max_volume') || '100';
		} else {
			o = option(s, form.Value, 'media_volume', _('Media volume'), _('Leave empty to inherit the global Chromecast volume.'));
			o.validate = volume; o.placeholder = uci.get(configName, 'main', 'media_volume') || '0.5';
		}
		this.maps.push(m);
		var adv = new form.Map(configName), a = adv.section(form.NamedSection, sectionId, 'device');
		codecs(a, true);
		o = option(a, form.Value, 'latency', _('Buffer and latency'), _('Leave empty to inherit the global setting.')); o.validate = latency;
		this.maps.push(adv);
		return Promise.all([m.render(), adv.render()]).then(function(nodes) {
			return E('div', {}, [nodes[0], E('details', { 'class': 'ac-advanced' }, [E('summary', {}, _('Advanced audio settings')), nodes[1]])]);
		});
	},
	findSection: function(device) {
		var match;
		uci.sections(configName, 'device', function(s) { if (s.engine === device.engine && s.udn === device.udn) match = s['.name']; });
		return match;
	},
	makeDeviceCard: function(device) {
		var self = this, sectionId = this.findSection(device);
		var facts = E('dl', { 'class': 'ac-facts' });
		var status = E('div', { 'class': 'ac-device-status' });
		var body = E('div', { 'class': 'ac-device-controls' });
		var title = E('h3', {}, text(device.name || device.original_name));
		var card = E('article', { 'class': 'ac-device-card' }, [
			E('header', { 'class': 'ac-device-heading' }, [E('div', {}, [title, E('p', {}, text(device.original_name))]), status]),
			body,
			E('details', { 'class': 'ac-device-details' }, [E('summary', {}, _('Device information')), facts])
		]);
		this.cards[key(device)] = { node: card, facts: facts, status: status, title: title };
		if (sectionId) {
			this.makeDeviceForm(device, sectionId).then(function(node) { replace(body, node); }).catch(function(error) { replace(body, E('p', { role: 'alert' }, errorMessage(error))); });
		} else {
			var add = E('button', { type: 'button', 'class': 'cbi-button ac-button', click: function() {
				self.perform(add, function() {
					var sid = uci.add(configName, 'device');
					uci.set(configName, sid, 'engine', device.engine);
					uci.set(configName, sid, 'udn', device.udn);
					uci.set(configName, sid, 'enabled', '1');
					return self.makeDeviceForm(device, sid).then(function(node) { replace(body, node); self.markDirty(); });
				});
			}}, _('Configure speaker'));
			replace(body, [E('p', { 'class': 'ac-muted' }, _('Discovered on your network. Configure this speaker to override its AirPlay name and volume.')), add]);
		}
		this.updateDevice(device);
		return card;
	},
	updateDevice: function(device) {
		var card = this.cards[key(device)];
		if (!card) return;
		var online = device.online === true ? _('Discovered') : device.online === false ? _('Not currently discovered') : _('Discovery unknown');
		replace(card.status, [badge(device.engine === 'cast' ? 'Chromecast' : 'UPnP / DLNA'), badge(online, device.online === true ? 'positive' : 'neutral')]);
		var values = [
			[_('Original name'), device.original_name], [_('IP address'), device.address], [_('Model'), device.model],
			[_('Manufacturer'), device.manufacturer], [_('Device identifier (UDN)'), device.udn], [_('Last discovered'), time(device.last_seen)]
		];
		replace(card.facts, values.reduce(function(nodes, pair) { nodes.push(E('dt', {}, pair[0]), E('dd', {}, text(pair[1]))); return nodes; }, []));
	},
	updateStatus: function(data) {
		this.snapshot = data;
		this.lastSuccess = Date.now(); this.failures = 0;
		this.statusError.hidden = true;
		var services = data.services || {}, statuses = [];
		['upnp', 'cast'].forEach(function(engine) {
			var service = services[engine] || {};
			statuses.push(badge((engine === 'cast' ? 'Chromecast' : 'UPnP') + ': ' + (!service.enabled ? _('Disabled') : service.running === true ? _('Running') : service.running === false ? _('Stopped') : _('Unknown')), service.running ? 'positive' : 'neutral'));
		});
		replace(this.serviceStatus, statuses);
		this.statusNote.textContent = _('Service running does not confirm AirPlay availability or playback.');
		var conflicts = Array.isArray(data.conflicts) ? data.conflicts : [];
		this.conflict.hidden = conflicts.length === 0;
		replace(this.conflict, [E('strong', {}, _('Another AirConnect instance was detected.')), E('p', {}, conflicts.join('\n')), E('p', {}, _('Stop the existing instance before starting these engines.'))]);
		this.actionButtons.forEach(function(button) { if (button.dataset.action !== 'stop') button.disabled = conflicts.length > 0; });
		var devices = Array.isArray(data.devices) ? data.devices : [];
		var self = this, seen = {};
		devices.forEach(function(device) {
			if (!device.udn || ['upnp', 'cast'].indexOf(device.engine) < 0) return;
			seen[key(device)] = true;
			if (!self.cards[key(device)]) self.deviceList.appendChild(self.makeDeviceCard(device));
			else self.updateDevice(device);
		});
		uci.sections(configName, 'device', function(s) {
			var device = { engine: s.engine, udn: s.udn, name: s.name, configured: true, online: false };
			if (seen[key(device)] || !device.udn || ['upnp', 'cast'].indexOf(device.engine) < 0) return;
			if (!self.cards[key(device)]) self.deviceList.appendChild(self.makeDeviceCard(device));
			else self.updateDevice(device);
		});
		this.empty.hidden = Object.keys(this.cards).length !== 0;
		this.deviceCount.textContent = String(Object.keys(this.cards).length);
		var scan = data.scan || {};
		this.scanButton.disabled = !!scan.running || !(services.upnp && services.upnp.enabled || services.cast && services.cast.enabled);
		this.scanButton.textContent = scan.running ? _('Scanning…') : _('Scan for speakers');
		this.scanStatus.textContent = scan.error ? _('Scan failed: ') + scan.error : scan.running ? _('Discovery is in progress.') : scan.last_scan ? _('Last scan: ') + time(scan.last_scan) : _('No scan has been completed.');
		this.scanStatus.setAttribute('role', scan.error ? 'alert' : 'status');
		replace(this.diagnosticFacts, [E('dt', {}, _('Interface')), E('dd', {}, text(data.interface)), E('dt', {}, _('Manager version')), E('dd', {}, text(data.version)), E('dt', {}, _('AirPlay broadcast')), E('dd', {}, _('Unknown — not measured')), E('dt', {}, _('Playback')), E('dd', {}, _('Unknown — not measured'))]);
	},
	refresh: function() {
		var self = this;
		if (document.hidden || this.inflight || Date.now() < (this.nextRetry || 0)) return Promise.resolve();
		this.inflight = true;
		return callStatus().then(function(data) { self.updateStatus(data); }).catch(function(error) {
			self.failures = (self.failures || 0) + 1;
			self.nextRetry = Date.now() + Math.min(60000, 10000 * Math.pow(2, self.failures - 1));
			self.statusError.hidden = false;
			self.statusError.textContent = _('Status unavailable. Displayed information may be stale. ') + errorMessage(error);
		}).finally(function() { self.inflight = false; });
	},
	scan: function() {
		var self = this;
		return this.perform(this.scanButton, function() {
			return callScan().then(function(result) {
				if (!result.ok) throw new Error(result.error || _('Could not start discovery.'));
				self.scanStatus.textContent = _('Discovery requested. Results will update automatically.');
				return self.refresh();
			});
		});
	},
	render: function(results) {
		var self = this;
		this.maps = []; this.cards = {}; this.dirty = false;
		this.saveState = E('span', { 'class': 'ac-save-state', role: 'status', 'aria-live': 'polite' }, _('No unsaved changes'));
		this.serviceStatus = E('div', { 'class': 'ac-status-badges' });
		this.statusNote = E('p', { 'class': 'ac-muted' });
		this.statusError = E('div', { 'class': 'ac-alert ac-warning', role: 'alert', hidden: true });
		this.conflict = E('div', { 'class': 'ac-alert ac-warning', role: 'alert', hidden: true });
		this.deviceCount = E('span', { 'class': 'ac-count' }, '0');
		this.scanButton = E('button', { type: 'button', 'class': 'cbi-button ac-button ac-button-primary', click: function() { self.scan(); } }, _('Scan for speakers'));
		this.scanStatus = E('p', { 'class': 'ac-muted', role: 'status' });
		this.empty = E('div', { 'class': 'ac-empty' }, [E('h3', {}, _('Find your speakers')), E('p', {}, _('Turn on a discovery engine in Settings, then scan. Keep your speaker online on the same LAN and enable DLNA when required.'))]);
		this.deviceList = E('div', { 'class': 'ac-device-list' }, this.empty);
		var devicesPanel = E('section', { id: 'ac-panel-devices', role: 'tabpanel', 'aria-labelledby': 'ac-tab-devices' }, [
			E('div', { 'class': 'ac-section-heading' }, [E('div', {}, [E('h2', {}, [_('Speakers'), this.deviceCount]), E('p', { 'class': 'ac-muted' }, _('Set the AirPlay name and volume for each speaker.'))]), this.scanButton]), this.scanStatus, this.deviceList
		]);
		var settingsBody = E('div', { 'class': 'ac-settings-body' }, _('Loading settings…'));
		var settingsPanel = E('section', { id: 'ac-panel-settings', role: 'tabpanel', hidden: true, 'aria-labelledby': 'ac-tab-settings' }, [E('h2', {}, _('Settings')), E('p', { 'class': 'ac-muted' }, _('Global defaults apply unless a speaker has its own override.')), settingsBody]);
		var logOutput = E('pre', { 'class': 'ac-logs', tabindex: '0', 'aria-label': _('Recent AirConnect logs') }, _('Logs are loaded only when requested.'));
		var logButton = E('button', { type: 'button', 'class': 'cbi-button ac-button', click: function() {
			self.perform(logButton, function() { return callLogs().then(function(result) {
				if (!Array.isArray(result.lines)) throw new Error(_('The log response was invalid.'));
				logOutput.textContent = result.lines.length ? result.lines.join('\n') + (result.truncated ? '\n' + _('Older log lines were omitted.') : '') : _('No log entries.');
			}); });
		}}, _('Load recent logs'));
		this.actionButtons = ['start', 'stop', 'restart'].map(function(action) {
			var labels = { start: _('Start service'), stop: _('Stop service'), restart: _('Restart service') };
			var button = E('button', { type: 'button', 'class': 'cbi-button ac-button', 'data-action': action, click: function() {
				self.perform(button, function() { return callAction(action).then(function(result) {
					if (!result.ok) throw new Error(result.error || _('Service action failed.'));
					self.notify(_('Service request accepted. Check the reported service status.'));
					return self.refresh();
				}); });
			}}, labels[action]); return button;
		});
		this.diagnosticFacts = E('dl', { 'class': 'ac-facts' });
		var diagnosticsPanel = E('section', { id: 'ac-panel-diagnostics', role: 'tabpanel', hidden: true, 'aria-labelledby': 'ac-tab-diagnostics' }, [
			E('h2', {}, _('Diagnostics')), E('p', { 'class': 'ac-muted' }, _('Service actions use the last applied settings. Stopping or restarting briefly disconnects AirPlay.')),
			E('div', { 'class': 'ac-actions' }, this.actionButtons), this.diagnosticFacts,
			E('div', { 'class': 'ac-section-heading' }, [E('h3', {}, _('Recent logs')), logButton]), logOutput
		]);
		var tabs = E('div', { 'class': 'ac-tabs', role: 'tablist', 'aria-label': _('AirConnect pages') });
		var panels = [devicesPanel, settingsPanel, diagnosticsPanel], names = ['devices', 'settings', 'diagnostics'], labels = [_('Speakers'), _('Settings'), _('Diagnostics')];
		names.forEach(function(name, index) {
			var tab = E('button', { id: 'ac-tab-' + name, type: 'button', role: 'tab', 'aria-selected': index === 0 ? 'true' : 'false', 'aria-controls': 'ac-panel-' + name, tabindex: index === 0 ? '0' : '-1', click: function() {
				Array.from(tabs.children).forEach(function(t, i) { t.setAttribute('aria-selected', i === index ? 'true' : 'false'); t.tabIndex = i === index ? 0 : -1; panels[i].hidden = i !== index; });
			}, keydown: function(event) {
				var next = event.key === 'ArrowRight' ? (index + 1) % 3 : event.key === 'ArrowLeft' ? (index + 2) % 3 : event.key === 'Home' ? 0 : event.key === 'End' ? 2 : null;
				if (next != null) { event.preventDefault(); tabs.children[next].click(); tabs.children[next].focus(); }
			}}, labels[index]); tabs.appendChild(tab);
		});
		var root = E('div', { 'class': 'ac-manager', input: function() { self.markDirty(); }, change: function() { self.markDirty(); } }, [
			E('link', { rel: 'stylesheet', href: L.resource('airconnect-manager/manager.css') }),
			E('header', { 'class': 'ac-page-heading' }, [E('div', {}, [E('h1', {}, 'AirConnect'), E('p', { 'class': 'ac-muted' }, _('Bring your network speakers to AirPlay.'))]), this.saveState]),
			E('section', { 'class': 'ac-service-summary', 'aria-label': _('Service status') }, [this.serviceStatus, this.statusNote]), this.statusError, this.conflict,
			tabs, devicesPanel, settingsPanel, diagnosticsPanel,
			E('p', { 'class': 'ac-apply-note' }, _('Save keeps changes pending. Save & Apply validates settings and briefly disconnects AirPlay while applying.'))
		]);
		this.makeMainForm().then(function(node) { replace(settingsBody, node); }).catch(function(error) { replace(settingsBody, E('p', { role: 'alert' }, errorMessage(error))); });
		if (results[1].data) this.updateStatus(results[1].data);
		else { this.statusError.hidden = false; this.statusError.textContent = _('Could not load status. ') + results[1].error; }
		this.pollFn = L.bind(this.refresh, this);
		poll.add(this.pollFn, 10);
		return root;
	},
	handleSave: function() {
		var self = this;
		this.saveState.textContent = _('Validating…');
		return Promise.all(this.maps.map(function(m) { return m.parse(); })).then(function() {
			return callValidate(canonicalConfig());
		}).then(function(result) {
			if (!result.ok) throw new Error((result.errors || [_('Configuration validation failed.')]).join('\n'));
			return uci.save();
		}).then(function() {
			self.dirty = false; self.saveState.className = 'ac-save-state'; self.saveState.textContent = _('Saved; pending apply');
			return ui.changes.init();
		}).catch(function(error) {
			self.saveState.textContent = _('Not saved — check settings'); self.saveState.className = 'ac-save-state ac-warning';
			self.notify(errorMessage(error), true); throw error;
		});
	},
	handleSaveApply: function(event, mode) {
		var self = this;
		return this.handleSave().then(function() {
			self.saveState.textContent = _('Applying…');
			return ui.changes.apply(mode === '0');
		}).then(function() {
			/* LuCI owns apply/rollback notifications; a status read only reports processes. */
			self.saveState.textContent = _('Apply requested — check LuCI confirmation');
			return self.refresh();
		}).catch(function(error) { self.saveState.textContent = _('Apply failed — changes remain pending'); throw error; });
	},
	handleReset: function() { window.location.reload(); }
});
