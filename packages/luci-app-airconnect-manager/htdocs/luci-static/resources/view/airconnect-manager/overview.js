'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require ui';
'require poll';
'require airconnect-manager.rules as rules';

var configName = 'airconnect-manager';
var callStatus = rpc.declare({ object: 'airconnect.manager', method: 'status', expect: {} });
var callScan = rpc.declare({ object: 'airconnect.manager', method: 'scan', expect: {} });
var callLogs = rpc.declare({ object: 'airconnect.manager', method: 'logs', expect: {} });
var callValidate = rpc.declare({ object: 'airconnect.manager', method: 'validate', params: ['config'], expect: {} });
var callAction = rpc.declare({ object: 'airconnect.manager', method: 'action', params: ['action'], expect: {} });
var mainKeys = ['enabled', 'interface', 'airupnp', 'aircast', 'codec', 'latency', 'max_volume', 'media_volume', 'log_level', 'metadata', 'flush', 'drift', 'artwork', 'http_length', 'upnp_max', 'stop_receiver'];
var deviceKeys = ['engine', 'udn', 'enabled', 'name', 'max_volume', 'media_volume', 'codec', 'latency', 'metadata', 'flush', 'drift', 'artwork', 'http_length', 'stop_receiver'];

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
// LuCI calls validate(section_id, value) and treats anything but `true` as a
// rejection message. The shared rules take the value alone, so every option is
// wired through this adapter rather than assigned the rule directly.
//
// `allowEmpty` is the form semantic, not a rule: on a device override an empty
// field means "inherit the global value" (config.uc's inherited()), so the form
// must let it through. The global fields are never empty - they have
// rmempty = false and config.uc rejects an explicit empty string - so they use
// the rule as-is and get a proper message instead of a backend round trip.
function validated(rule, allowEmpty) {
	return function(section, value) {
		if (allowEmpty && (value == null || value === '')) return true;
		return rule(value);
	};
}
// AirPlay names are compared after trailing whitespace is removed: the engine
// strips it, so "Demo " and "Demo" are the same receiver.
function trimmed(value) { return value == null ? '' : String(value).replace(/\s+$/, ''); }
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
// The four 0/1 switches the engines read with atoi() into a bool: metadata,
// flush, drift and stop_receiver. A select keeps the stored value the exact
// "0"/"1" config.uc accepts, so the browser cannot submit "true"/"yes" and
// get a backend rejection round trip.
//
// `fallback` is the upstream default and is listed first, because LuCI selects
// the first entry when the option is absent. A configuration that predates these
// fields therefore shows the value the engine is actually using instead of an
// arbitrary first choice, and saving it writes that same value.
function binaryFlag(section, key, label, description, inherited, fallback) {
	var o = option(section, form.ListValue, key, label, description);
	if (inherited) o.value('', _('Inherit global setting'));
	var entries = [['1', _('On (1)')], ['0', _('Off (0)')]];
	if (fallback === '0') entries.reverse();
	entries.forEach(function(pair) { o.value(pair[0], pair[1]); });
	o.validate = validated(rules.binaryFlag, inherited);
	return o;
}
// http_length is the transfer mode, not a size: upstream only defines -3, -1, 0
// (README "HTTP content-length and transfer modes"). The default -1 is first for
// the same reason as above.
function httpLength(section, inherited) {
	var o = option(section, form.ListValue, 'http_length', _('HTTP transfer mode (UPnP only)'),
		_('Compatibility only. Change this when a UPnP speaker cannot play at all; the default works for most devices.'));
	if (inherited) o.value('', _('Inherit global setting'));
	o.value('-1', _('-1: no content-length (default)'));
	o.value('-3', _('-3: chunked encoding'));
	o.value('0', _('0: fixed dummy length'));
	o.validate = validated(rules.httpLength, inherited);
	return o;
}
// upnp_max is a search version, 1..9; a select is honest here because the range
// is tiny and there is nothing else to type. 1 is the upstream default. It is
// global only: upstream parses a device-level value but never reads it.
function upnpMax(section) {
	var o = option(section, form.ListValue, 'upnp_max', _('UPnP search version (UPnP only)'),
		_('Highest UPnP MediaRenderer version to search. The Chromecast engine ignores this.'));
	for (var version = 1; version <= 9; version++) o.value(String(version), String(version));
	o.validate = validated(rules.upnpMax);
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
		o.validate = validated(rules.interfaceValue);
		o = option(s, form.Flag, 'airupnp', _('UPnP / DLNA speakers')); o.rmempty = false;
		o = option(s, form.Flag, 'aircast', _('Chromecast speakers')); o.rmempty = false;
		o = option(s, form.Value, 'max_volume', _('UPnP volume limit'), _('Default maximum volume, from 1 to 100.'));
		o.validate = validated(rules.upnpVolume); o.rmempty = false;
		o = option(s, form.Value, 'media_volume', _('Chromecast media volume'), _('Default media volume, from 0 to 1. This is not a volume limit.'));
		o.validate = validated(rules.castVolume); o.rmempty = false;
		this.maps.push(m);
		var advanced = new form.Map(configName), a = advanced.section(form.NamedSection, 'main', 'main');
		codecs(a, false).rmempty = false;
		o = option(a, form.Value, 'latency', _('Buffer and latency'), _('Format: 1000:2000. Lower values may cause audio dropouts.')); o.validate = validated(rules.latency); o.rmempty = false;
		// Track metadata and cover art: both engines read these, and the engines
		// decide whether a given speaker can display them.
		binaryFlag(a, 'metadata', _('Send track information'), _('Sends the title and artist to the speaker. Both engines read this. A speaker may still show nothing.'), false, '1').rmempty = false;
		o = option(a, form.Value, 'artwork', _('Cover art URL'), _('Optional http:// or https:// image the speaker fetches itself. Leave empty for none. The router never downloads it.'));
		o.validate = validated(rules.artwork);
		binaryFlag(a, 'flush', _('Handle FLUSH'), _('Compatibility option, both engines. Turning it off can change pause and track-change behaviour, so keep it on unless a speaker misbehaves.'), false, '1').rmempty = false;
		binaryFlag(a, 'drift', _('Let the timing reference drift'), _('Both engines. Off adjusts timing by adding or dropping a frame, which can be audible as a click; on avoids the click but risks underruns.'), false, '0').rmempty = false;
		// The next two are read only by airupnp; aircast has no such element.
		httpLength(a, false).rmempty = false;
		upnpMax(a).rmempty = false;
		binaryFlag(a, 'stop_receiver', _('Stop the receiver (Chromecast only)'), _('Chromecast compatibility option. The UPnP engine ignores this.'), false, '0').rmempty = false;
		o = option(a, form.ListValue, 'log_level', _('Log detail'));
		['error', 'warn', 'info', 'debug'].forEach(function(v) { o.value(v, v); });
		o.validate = validated(rules.logLevel); o.rmempty = false;
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
		o.placeholder = device.original_name || _('Original name'); o.validate = validated(rules.airplayName);
		if (device.engine === 'upnp') {
			o = option(s, form.Value, 'max_volume', _('Volume limit'), _('Leave empty to inherit the global UPnP limit.'));
			o.validate = validated(rules.upnpVolume, true); o.placeholder = uci.get(configName, 'main', 'max_volume') || '100';
		} else {
			o = option(s, form.Value, 'media_volume', _('Media volume'), _('Leave empty to inherit the global Chromecast volume.'));
			o.validate = validated(rules.castVolume, true); o.placeholder = uci.get(configName, 'main', 'media_volume') || '0.5';
		}
		this.maps.push(m);
		var adv = new form.Map(configName), a = adv.section(form.NamedSection, sectionId, 'device');
		codecs(a, true);
		o = option(a, form.Value, 'latency', _('Buffer and latency'), _('Leave empty to inherit the global setting.')); o.validate = validated(rules.latency, true);
		// Only the fields the device's own engine reads are offered. A Cast
		// speaker never gets http_length or upnp_max, and a UPnP speaker never
		// gets stop_receiver: those elements do not exist in the other parser.
		binaryFlag(a, 'metadata', _('Send track information'), _('Leave empty to inherit the global setting.'), true, '1');
		o = option(a, form.Value, 'artwork', _('Cover art URL'), _('Leave empty to inherit the global setting.'));
		o.validate = validated(rules.artwork, true); o.placeholder = uci.get(configName, 'main', 'artwork') || _('No cover art');
		binaryFlag(a, 'flush', _('Handle FLUSH'), _('Leave empty to inherit the global setting.'), true, '1');
		binaryFlag(a, 'drift', _('Let the timing reference drift'), _('Leave empty to inherit the global setting.'), true, '0');
		if (device.engine === 'upnp') {
			httpLength(a, true);
		}
		else {
			binaryFlag(a, 'stop_receiver', _('Stop the receiver'), _('Leave empty to inherit the global setting.'), true, '0');
		}
		this.maps.push(adv);
		// Remembered separately so a committed edit can be re-staged without
		// re-parsing the global settings, which have nothing to do with names.
		this.deviceMaps.push(m); this.deviceMaps.push(adv);
		return Promise.all([m.render(), adv.render()]).then(function(nodes) {
			return E('div', {}, [nodes[0], E('details', { 'class': 'ac-advanced' }, [E('summary', {}, _('Advanced audio settings')), nodes[1]])]);
		});
	},
	findSection: function(device) {
		var match;
		uci.sections(configName, 'device', function(s) { if (s.engine === device.engine && s.udn === device.udn) match = s['.name']; });
		return match;
	},
	// The effective AirPlay name is what the receiver will broadcast: an explicit
	// override, otherwise the name discovery reported. A device with neither has
	// nothing to collide on and is skipped. Trailing whitespace is ignored
	// because the engines trim it before publishing the name.
	effectiveNames: function() {
		var discovered = Object.create(null), names = [];
		((this.snapshot || {}).devices || []).forEach(function(device) {
			if (device && device.udn) discovered[device.engine + '\n' + device.udn] = device.original_name;
		});
		uci.sections(configName, 'device', function(s) {
			var name = trimmed(s.name) || trimmed(discovered[s.engine + '\n' + s.udn]);
			if (name !== '') names.push(name);
		});
		return names;
	},
	// Re-stage the device forms so a rename the user just committed reaches
	// uci.sections before the collision check reads it. A rejected parse stages
	// nothing and is ignored here: save reports the invalid field with the
	// rule's own message. A map that is still rendering has no widgets yet and
	// simply stages nothing.
	restageDevices: function() {
		return Promise.all((this.deviceMaps || []).map(function(m) {
			return Promise.resolve().then(function() { return m.parse(); }).catch(function() {});
		}));
	},
	// Names used by more than one device, in the order they were first seen.
	// Object.create(null) keeps a speaker named "constructor" or "__proto__" an
	// ordinary key instead of a prototype lookup.
	duplicateNames: function() {
		var counts = Object.create(null), order = [], duplicates = [];
		this.effectiveNames().forEach(function(name) {
			if (counts[name] === undefined) { counts[name] = 1; order.push(name); }
			else counts[name] = counts[name] + 1;
		});
		order.forEach(function(name) { if (counts[name] > 1) duplicates.push(name); });
		return duplicates;
	},
	// A warning, never a block: two receivers with one name are confusing but
	// still a configuration the engines accept, so saving must go on.
	//
	// LuCI stages form values into uci only inside Map.parse(), so this runs
	// after the device forms are parsed (on `change`, and again on save) and on
	// every status refresh, which is when discovery can change an inherited
	// name. It is never derived from the DOM: staged uci.sections and the last
	// status snapshot are the only inputs.
	updateNameWarning: function() {
		if (!this.nameWarning) return;
		var duplicates = this.duplicateNames();
		this.nameWarning.hidden = duplicates.length === 0;
		if (duplicates.length === 0) { replace(this.nameWarning, []); return; }
		// One element per name: a newline inside a single text node is collapsed
		// by the HTML layout, so several colliding names would run together in
		// one wrapped sentence.
		var names = duplicates.map(function(name) { return E('div', {}, name); });
		replace(this.nameWarning, [
			E('strong', {}, _('More than one speaker uses the same AirPlay name.'))
		].concat(names, [
			E('p', {}, _('AirPlay lists these receivers under one name. Give each speaker its own name.'))
		]));
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
		var status = [badge(device.engine === 'cast' ? 'Chromecast' : 'UPnP / DLNA'), badge(online, device.online === true ? 'positive' : 'neutral')];
		// Broadcasting is its own badge, never folded into "Discovered": a speaker
		// can be discovered while nothing is advertised for it, and the other way
		// round. A true badge is the only positive; null stays neutral and says so.
		if (device.broadcasting === true)
			status.push(badge(_('AirPlay advertised'), 'positive'));
		else if (device.broadcasting === false)
			status.push(badge(_('No AirPlay advertisement'), 'neutral'));
		else
			status.push(badge(_('AirPlay broadcast unknown'), 'neutral'));
		replace(card.status, status);
		var broadcast = this.snapshot && this.snapshot.broadcast ? this.snapshot.broadcast : {};
		var values = [
			[_('Original name'), device.original_name], [_('IP address'), device.address], [_('Model'), device.model],
			[_('Manufacturer'), device.manufacturer], [_('Device identifier (UDN)'), device.udn],
			[_('Last discovered'), time(device.last_seen)],
			// The observation time is the mDNS scan, not the discovery scan above.
			[_('AirPlay broadcast'), device.broadcasting === true
				? _('Yes') + (broadcast.observed_at ? ' (' + _('observed') + ' ' + time(broadcast.observed_at) + ')' : '')
				: device.broadcasting === false
					? _('No') + (broadcast.observed_at ? ' (' + _('observed') + ' ' + time(broadcast.observed_at) + ')' : '')
					: _('Unknown — not measured')]
		];
		replace(card.facts, values.reduce(function(nodes, pair) { nodes.push(E('dt', {}, pair[0]), E('dd', {}, text(pair[1]))); return nodes; }, []));
	},
	// The four states are rendered from four different facts and never from each
	// other. `broadcasting` is a measurement (true / false / null), `playback` is
	// always the constant unknown, and the two are given separate rows with
	// separate wording so a positive broadcast can never read as playback.
	// `broadcast.observed_at` is the time of the mDNS observation, not the time of
	// the last discovery scan: they are different measurements.
	broadcastText: function(value, observedAt, reason) {
		if (value === true)
			return _('Yes — an AirPlay receiver is advertised') + (observedAt ? ' (' + _('observed') + ' ' + time(observedAt) + ')' : '');
		if (value === false)
			return _('No — the scan found no advertisement') + (observedAt ? ' (' + _('observed') + ' ' + time(observedAt) + ')' : '');
		// Never a positive: an unmeasured or failed observation states what would
		// have to be true for the answer to be known, and why it is not.
		var why = reason ? ' ' + _('Last attempt:') + ' ' + reason + '.' : '';
		return _('Unknown — no completed mDNS observation. This needs the engine running and its receiver advertised on this LAN.') + why;
	},
	playbackText: function(data) {
		// Playback is not measurable through the documented upstream surface. It is
		// kept as its own row with its own reason, deliberately never derived from
		// the broadcast row above.
		var playback = data.playback || {};
		if (playback.known === true && playback.playing === true)
			return _('Playing');
		if (playback.known === true && playback.playing === false)
			return _('Not playing');
		return _('Unknown — the engines expose no documented playback status, so this is never inferred from the broadcast state.');
	},
	updateStatus: function(data) {
		this.snapshot = data;
		this.lastSuccess = Date.now(); this.failures = 0;
		this.statusError.hidden = true;
		var services = data.services || {}, statuses = [];
		['upnp', 'cast'].forEach(function(engine) {
			var service = services[engine] || {};
			// The badge reports the service process only. Broadcasting is a separate
			// fact and gets its own row below, so a running process cannot be read as
			// an AirPlay advertisement.
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
		// Discovered names can appear or change between polls, which changes what
		// a device with no override collides with.
		this.updateNameWarning();
		var scan = data.scan || {};
		this.scanButton.disabled = !!scan.running || !(services.upnp && services.upnp.enabled || services.cast && services.cast.enabled);
		this.scanButton.textContent = scan.running ? _('Scanning…') : _('Scan for speakers');
		this.scanStatus.textContent = scan.error ? _('Scan failed: ') + scan.error : scan.running ? _('Discovery is in progress.') : scan.last_scan ? _('Last scan: ') + time(scan.last_scan) : _('No scan has been completed.');
		this.scanStatus.setAttribute('role', scan.error ? 'alert' : 'status');
		var broadcast = data.broadcast || {};
		var upnpService = services.upnp || {}, castService = services.cast || {};
		// Each row is one fact from one source. The broadcast rows carry the mDNS
		// observation time; the playback row never does, because it has none.
		replace(this.diagnosticFacts, [
			E('dt', {}, _('Interface')), E('dd', {}, text(data.interface)),
			E('dt', {}, _('Manager version')), E('dd', {}, text(data.version)),
			E('dt', {}, _('AirPlay broadcast (UPnP)')), E('dd', {}, this.broadcastText(upnpService.broadcasting, broadcast.observed_at, broadcast.error)),
			E('dt', {}, _('AirPlay broadcast (Chromecast)')), E('dd', {}, this.broadcastText(castService.broadcasting, broadcast.observed_at, broadcast.error)),
			E('dt', {}, _('Playback')), E('dd', {}, this.playbackText(data))
		]);
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
		this.maps = []; this.deviceMaps = []; this.cards = {}; this.dirty = false;
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
		this.nameWarning = E('div', { 'class': 'ac-alert ac-warning', role: 'status', hidden: true });
		var devicesPanel = E('section', { id: 'ac-panel-devices', role: 'tabpanel', 'aria-labelledby': 'ac-tab-devices' }, [
			E('div', { 'class': 'ac-section-heading' }, [E('div', {}, [E('h2', {}, [_('Speakers'), this.deviceCount]), E('p', { 'class': 'ac-muted' }, _('Set the AirPlay name and volume for each speaker.'))]), this.scanButton]), this.scanStatus, this.nameWarning, this.deviceList
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
		var root = E('div', { 'class': 'ac-manager', input: function() { self.markDirty(); }, change: function() {
			self.markDirty();
			self.restageDevices().then(function() { self.updateNameWarning(); });
		} }, [
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
			// Parsed forms have staged their values in uci.sections, so the
			// collision check runs on the configuration that is about to be sent,
			// not on whatever the DOM shows.
			self.updateNameWarning();
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
