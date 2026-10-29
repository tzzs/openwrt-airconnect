import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert } from './components/feedback.jsx';
import { Workspace } from './components/workspace.jsx';
import { createRules } from './lib/rules.js';
import { createFields } from './lib/fields.js';
import { createPresentation } from './lib/presentation.js';
import { applySnapshot, createPoller, POLL_SECONDS } from './lib/polling.js';
import { buildCanonicalConfig } from './lib/config.js';
import { duplicateNames, mergeDevices, readState } from './lib/model.js';

function message(error) {
	return error && error.message ? error.message : String(error);
}

export function App({ context, onReady }) {
	const services = context.services;
	const t = services.t;
	const _ = typeof t === 'function' ? t : function (s) { return s; };

	const rules = useMemo(() => createRules(t), [t]);
	const fields = useMemo(() => createFields(t), [t]);
	const presentation = useMemo(() => createPresentation(t), [t]);
	const inheritLabel = useMemo(() => _('Inherit global setting'), [t]);

	const [ready, setReady] = useState(false);
	const [fatal, setFatal] = useState(null);
	const [status, setStatus] = useState(null);
	const [statusError, setStatusError] = useState(null);
	const [scan, setScan] = useState({ running: false, error: null, last_scan: null, disabled: true });
	const [mainValues, setMainValues] = useState({});
	const [deviceValues, setDeviceValues] = useState({});
	const [configured, setConfigured] = useState([]);
	const [saveState, setSaveState] = useState({ text: _('No unsaved changes'), tone: 'idle' });
	const [busy, setBusy] = useState(false);
	const [logs, setLogs] = useState(null);
	const [selectedKey, setSelectedKey] = useState(null);
	const [settingsOpen, setSettingsOpen] = useState(false);

	// The poller owns the four polling promises (interval, hidden tab, one
	// request in flight, backoff). It only ever touches the live snapshot and the
	// scan state - never the form, which belongs to the user until they save.
	const poller = useMemo(() => createPoller({
		fetch: () => services.status(),
		onSnapshot: (data) => {
			const snapshot = applySnapshot(data);
			setStatus(snapshot.status);
			setScan(snapshot.scan);
			setStatusError(null);
		},
		onError: (error) => {
			setStatusError(_('Status unavailable. Displayed information may be stale. ') + message(error));
		},
		isHidden: () => typeof document !== 'undefined' && document.hidden === true
	}), [services, t]);

	const refresh = useCallback(() => poller.tick(), [poller]);

	const reload = useCallback(async () => {
		await services.loadConfig();
		const state = readState({
			get: (section, option) => services.get(section, option),
			sections: (type, callback) => services.sections(type, callback)
		});
		setMainValues(state.main);
		setDeviceValues(state.devices);
		setConfigured(state.sections);
	}, [services]);

	useEffect(() => {
		let cancelled = false;
		(async () => {
			try {
				await reload();
				await refresh();
				if (!cancelled) setReady(true);
			} catch (error) {
				if (!cancelled) setFatal(message(error));
			}
		})();
		const tick = () => { refresh(); };
		services.pollAdd(tick, POLL_SECONDS);
		return () => {
			cancelled = true;
			services.pollRemove(tick);
		};
	}, [services, reload, refresh]);

	const dirty = useCallback(() => {
		setSaveState({ text: _('Unsaved changes'), tone: 'warning' });
	}, [t]);

	const setMain = useCallback((field, value) => {
		setMainValues((previous) => Object.assign({}, previous, { [field]: value }));
		services.set('main', field, value);
		dirty();
	}, [services, dirty]);

	const setDevice = useCallback((section, field, value) => {
		if (section == null) return;
		setDeviceValues((previous) => Object.assign({}, previous, {
			[section]: Object.assign({}, previous[section] || {}, { [field]: value })
		}));
		services.set(section, field, value);
		dirty();
	}, [services, dirty]);

	const configure = useCallback((device) => {
		const sid = services.add('device');
		services.set(sid, 'engine', device.engine);
		services.set(sid, 'udn', device.udn);
		services.set(sid, 'enabled', '1');
		setDeviceValues((previous) => Object.assign({}, previous, {
			[sid]: { engine: device.engine, udn: device.udn, enabled: '1' }
		}));
		setConfigured((previous) => previous.concat([
			{ name: sid, engine: device.engine, udn: device.udn, removed: false }
		]));
		dirty();
	}, [services, dirty]);

	// The canonical payload the manager validates: the main section from uci, and
	// every device section - including ones added in this session, which some
	// LuCI versions only expose through uci.sections after a save.
	const buildConfig = useCallback(() => {
		const seen = new Set();
		return buildCanonicalConfig({
			get: (pkg, section, option) => services.get(section, option),
			sections: (pkg, type, callback) => {
				services.sections(type, (section) => {
					seen.add(section['.name']);
					callback(section);
				});
				for (const item of configured) {
					if (type !== 'device' || seen.has(item.name) || item.removed) continue;
					callback(Object.assign({}, deviceValues[item.name] || {}, {
						'.name': item.name,
						'.type': type
					}));
				}
			}
		});
	}, [services, configured, deviceValues]);

	const handleSave = useCallback(async () => {
		setSaveState({ text: _('Validating…'), tone: 'idle' });
		try {
			const result = await services.validate(buildConfig());
			if (!result || !result.ok) {
				const errors = (result && result.errors) || [_('Configuration validation failed.')];
				throw new Error(errors.join('\n'));
			}
			await services.save();
			setSaveState({ text: _('Saved; pending apply'), tone: 'idle' });
			await services.changesInit();
		} catch (error) {
			setSaveState({ text: _('Not saved — check settings'), tone: 'warning' });
			services.notify(message(error), 'danger');
			throw error;
		}
	}, [services, buildConfig, t]);

	const handleSaveApply = useCallback(async (rollback) => {
		await handleSave();
		try {
			setSaveState({ text: _('Applying…'), tone: 'idle' });
			await services.changesApply(rollback);
			// LuCI owns apply/rollback notifications; a status read only reports processes.
			setSaveState({ text: _('Apply requested — check LuCI confirmation'), tone: 'idle' });
			await refresh();
		} catch (error) {
			setSaveState({ text: _('Apply failed — changes remain pending'), tone: 'warning' });
			throw error;
		}
	}, [handleSave, services, refresh, t]);

	// Hand the LuCI view its save hooks once, so its footer buttons drive this app.
	const readyRef = useRef(false);
	useEffect(() => {
		if (readyRef.current) return;
		readyRef.current = true;
		if (typeof onReady === 'function')
			onReady({ save: handleSave, saveApply: handleSaveApply });
	}, [onReady, handleSave, handleSaveApply]);

	const runAction = useCallback(async (action) => {
		setBusy(true);
		try {
			const result = await services.action(action);
			if (!result || !result.ok) throw new Error((result && result.error) || _('Service action failed.'));
			await refresh();
		} catch (error) {
			services.notify(message(error), 'danger');
		} finally {
			setBusy(false);
		}
	}, [services, refresh, t]);

	const runScan = useCallback(async () => {
		setBusy(true);
		try {
			const result = await services.scan();
			if (!result || !result.ok) throw new Error((result && result.error) || _('Could not start discovery.'));
			await refresh();
		} catch (error) {
			services.notify(message(error), 'danger');
		} finally {
			setBusy(false);
		}
	}, [services, refresh, t]);

	const loadLogs = useCallback(async () => {
		const result = await services.logs();
		if (!Array.isArray(result.lines)) throw new Error(_('The log response was invalid.'));
		return { lines: result.lines, truncated: !!result.truncated };
	}, [services, t]);

	const model = useMemo(
		() => ({ status, configured, deviceValues }),
		[status, configured, deviceValues]);
	const devices = useMemo(() => mergeDevices(model), [model]);
	const duplicates = useMemo(() => duplicateNames(model), [model]);

	useEffect(() => {
		if (!selectedKey && devices.length > 0) setSelectedKey(devices[0].engine + '\n' + devices[0].udn);
		if (selectedKey && !devices.some((device) => device.engine + '\n' + device.udn === selectedKey))
			setSelectedKey(devices.length ? devices[0].engine + '\n' + devices[0].udn : null);
	}, [devices, selectedKey]);

	const selectedDevice = devices.find((device) => device.engine + '\n' + device.udn === selectedKey) || null;

	const handleDeviceChange = useCallback((section, field, value) => {
		if (field === '__configure__') {
			configure(value);
			setSelectedKey(value.engine + '\n' + value.udn);
			return;
		}
		setDevice(section, field, value);
	}, [configure, setDevice]);

	const withBusy = (task) => {
		setBusy(true);
		task().catch(() => {}).finally(() => setBusy(false));
	};

	if (fatal) {
		return <Alert tone="destructive">{_('Could not load settings. ')}{fatal}</Alert>;
	}

	if (!ready) {
		return (
			<div className="ac-loading-state">
				<div className="ac-loading-line ac-loading-line-wide" />
				<div className="ac-loading-line" />
				<div className="ac-loading-block" />
				<span>{_('Loading speakers and status…')}</span>
			</div>
		);
	}

	return (
		<Workspace
			status={status}
			presentation={presentation}
			devices={devices}
			selectedKey={selectedKey}
			selectedDevice={selectedDevice}
			deviceValues={deviceValues}
			fields={fields}
			rules={rules}
			scanState={scan}
			mainValues={mainValues}
			saveState={saveState}
			busy={busy}
			conflicts={(status && status.conflicts) || []}
			logs={logs}
			onSelect={(key) => { setSelectedKey(key); setSettingsOpen(false); }}
			onConfigure={configure}
			onDeviceChange={handleDeviceChange}
			onMainChange={setMain}
			onScan={runScan}
			onAction={runAction}
			onLoadLogs={async () => { try { setLogs(await loadLogs()); } catch (error) { services.notify(message(error), 'danger'); } }}
			onSave={() => withBusy(handleSave)}
			onSaveApply={() => withBusy(() => handleSaveApply(false))}
			onReset={() => window.location.reload()}
			onRefresh={() => refresh()}
			onSettings={() => setSettingsOpen(true)}
			settingsOpen={settingsOpen}
			onCloseSettings={() => setSettingsOpen(false)}
			t={t}
			inheritLabel={inheritLabel}
		/>
	);
}
