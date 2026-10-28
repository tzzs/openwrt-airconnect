import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { RotateCcw, Save } from 'lucide-react';

import { Tabs, TabsContent, TabsList, TabsTrigger } from './components/ui/tabs.jsx';
import { Button } from './components/ui/button.jsx';
import { Alert, StatusBadge } from './components/feedback.jsx';
import { SettingsPanel } from './components/settings.jsx';
import { DiagnosticsPanel } from './components/diagnostics.jsx';
import { SpeakersPanel } from './components/speakers.jsx';
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
			services.notify(_('Service request accepted. Check the reported service status.'));
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

	const withBusy = (task) => {
		setBusy(true);
		task().catch(() => {}).finally(() => setBusy(false));
	};

	if (fatal) {
		return <Alert tone="destructive">{_('Could not load settings. ')}{fatal}</Alert>;
	}

	const broadcast = (status && status.broadcast) || {};

	return (
		<div className="space-y-5">
			<div className="flex flex-wrap items-start justify-between gap-3">
				<div>
					<h1 className="text-2xl font-semibold tracking-tight">AirConnect</h1>
					<p className="text-sm text-muted-foreground">
						{_('Bring your network speakers to AirPlay.')}
					</p>
				</div>
				<div className="flex flex-wrap items-center gap-2">
					<span
						className={'text-xs ' + (saveState.tone === 'warning'
							? 'text-warning'
							: 'text-muted-foreground')}
						role="status"
						aria-live="polite"
					>
						{saveState.text}
					</span>
					<Button
						variant="outline"
						size="sm"
						disabled={busy}
						onClick={() => withBusy(() => handleSaveApply(false))}
					>
						<Save className="size-4" /> {_('Save & Apply')}
					</Button>
					<Button variant="outline" size="sm" disabled={busy} onClick={() => withBusy(handleSave)}>
						{_('Save')}
					</Button>
					<Button variant="ghost" size="sm" disabled={busy} onClick={() => window.location.reload()}>
						<RotateCcw className="size-4" /> {_('Reset')}
					</Button>
				</div>
			</div>

			<div className="rounded-xl border border-border bg-muted/30 p-3" aria-label={_('Service status')}>
				<div className="flex flex-wrap gap-2">
					<StatusBadge tone={presentation.serviceTone(status && status.services && status.services.upnp)}>
						{_('UPnP')}: {presentation.serviceLabel(status && status.services && status.services.upnp)}
					</StatusBadge>
					<StatusBadge tone={presentation.serviceTone(status && status.services && status.services.cast)}>
						{_('Chromecast')}: {presentation.serviceLabel(status && status.services && status.services.cast)}
					</StatusBadge>
				</div>
				<p className="mt-1.5 text-xs text-muted-foreground">
					{_('Service running does not confirm AirPlay availability or playback.')}
				</p>
			</div>

			{statusError ? <Alert tone="warning">{statusError}</Alert> : null}

			{!ready ? (
				<p className="text-sm text-muted-foreground">{_('Loading settings…')}</p>
			) : (
				<Tabs defaultValue="speakers">
					<TabsList>
						<TabsTrigger value="speakers">{_('Speakers')}</TabsTrigger>
						<TabsTrigger value="settings">{_('Settings')}</TabsTrigger>
						<TabsTrigger value="diagnostics">{_('Diagnostics')}</TabsTrigger>
					</TabsList>
					<TabsContent value="speakers">
						<SpeakersPanel
							devices={devices}
							deviceValues={deviceValues}
							onDeviceChange={setDevice}
							onConfigure={configure}
							rules={rules}
							fields={fields.device}
							presentation={presentation}
							onScan={runScan}
							scanState={scan}
							duplicates={duplicates}
							observation={broadcast}
							t={t}
							inheritLabel={inheritLabel}
						/>
					</TabsContent>
					<TabsContent value="settings">
						<SettingsPanel
							fields={fields.main}
							model={mainValues}
							set={setMain}
							rules={rules}
							t={t}
							inheritLabel={inheritLabel}
						/>
					</TabsContent>
					<TabsContent value="diagnostics">
						<DiagnosticsPanel
							status={status}
							presentation={presentation}
							onAction={runAction}
							onLoadLogs={loadLogs}
							logs={logs}
							setLogs={setLogs}
							busy={busy}
							t={t}
						/>
					</TabsContent>
				</Tabs>
			)}

			<p className="text-xs text-muted-foreground">
				{_('Save keeps changes pending. Save & Apply validates settings and briefly disconnects AirPlay while applying.')}
			</p>
		</div>
	);
}
