import { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert } from './components/feedback.jsx';
import { PageChrome } from './components/chrome.jsx';
import { Workspace } from './components/workspace.jsx';
import { SettingsPage } from './components/settings-page.jsx';
import { createRules } from './lib/rules.js';
import { createFields } from './lib/fields.js';
import { createPresentation } from './lib/presentation.js';
import {
	createTranslator,
	readLanguage,
	writeLanguage
} from './lib/i18n.js';
import { applyTheme, detectTheme, writeTheme } from './lib/theme.js';
import { applySnapshot, createPoller, POLL_SECONDS } from './lib/polling.js';
import { buildCanonicalConfig } from './lib/config.js';
import { duplicateNames, mergeDevices, readState } from './lib/model.js';

function message(error) {
	return error && error.message ? error.message : String(error);
}

/**
 * The AirConnect application.
 *
 * `context.mode` decides which page this is: 'overview' is the device
 * workspace, 'settings' is the global configuration. Both are the same
 * application with a different body, so they share the chrome, the polling,
 * the save logic and the preference state - only the body differs. The LuCI
 * views pass the mode in, which is what lets the two pages be separate menu
 * entries with separate URLs.
 */
export function App({ context }) {
	const services = context.services;
	const mode = context.mode === 'settings' ? 'settings' : 'overview';

	// `luciTranslate` is LuCI's server-side `_` (compiled .lmo). It may be
	// undefined in a test harness; createTranslator tolerates that.
	const luciTranslate = services.t;

	// The language preference lives in localStorage (airconnect.lang) and is
	// independent of LuCI's global language, so a switch is instant and
	// pure-frontend. The translator falls back to LuCI's `_` for strings the
	// built-in table does not cover.
	const [lang, setLang] = useState(readLanguage);
	const t = useMemo(
		() => createTranslator(lang, luciTranslate),
		[lang, luciTranslate]
	);

	// The theme is a pure-frontend preference as well. It is applied to the
	// `.ac-root` element, which the LuCI view creates outside the React tree,
	// so the host element comes in through the context.
	const themeHost = context.themeHost || null;
	const [theme, setTheme] = useState(detectTheme);

	const setLanguage = useCallback((next) => {
		writeLanguage(next);
		setLang(next);
	}, []);

	const setThemePreference = useCallback((next) => {
		writeTheme(next);
		setTheme(next);
	}, []);

	useEffect(() => {
		applyTheme(themeHost, theme);
	}, [themeHost, theme]);

	const rules = useMemo(() => createRules(t), [t]);
	const fields = useMemo(() => createFields(t), [t]);
	const presentation = useMemo(() => createPresentation(t), [t]);
	const inheritLabel = useMemo(() => t('Inherit global setting'), [t]);

	const [ready, setReady] = useState(false);
	const [fatal, setFatal] = useState(null);
	const [status, setStatus] = useState(null);
	const [statusError, setStatusError] = useState(null);
	const [scan, setScan] = useState({
		running: false,
		error: null,
		last_scan: null,
		disabled: true
	});
	const [mainValues, setMainValues] = useState({});
	const [deviceValues, setDeviceValues] = useState({});
	const [configured, setConfigured] = useState([]);
	const [saveState, setSaveState] = useState({
		text: t('No unsaved changes'),
		tone: 'idle'
	});
	const [busy, setBusy] = useState(false);
	const [logs, setLogs] = useState(null);
	const [selectedKey, setSelectedKey] = useState(null);
	const [settingsOpen, setSettingsOpen] = useState(false);

	// The poller owns the four polling promises (interval, hidden tab, one
	// request in flight, backoff). It only ever touches the live snapshot and
	// the scan state - never the form, which belongs to the user until they
	// save.
	const poller = useMemo(
		() =>
			createPoller({
				fetch: () => services.status(),
				onSnapshot: (data) => {
					const snapshot = applySnapshot(data);
					setStatus(snapshot.status);
					setScan(snapshot.scan);
					setStatusError(null);
				},
				onError: (error) => {
					setStatusError(
						t('Status unavailable. Displayed information may be stale. ') +
							message(error)
					);
				},
				isHidden: () =>
					typeof document !== 'undefined' && document.hidden === true
			}),
		[services, t]
	);

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
		const tick = () => {
			refresh();
		};
		services.pollAdd(tick, POLL_SECONDS);
		return () => {
			cancelled = true;
			services.pollRemove(tick);
		};
	}, [services, reload, refresh]);

	const dirty = useCallback(() => {
		setSaveState({ text: t('Unsaved changes'), tone: 'warning' });
	}, [t]);

	const setMain = useCallback(
		(field, value) => {
			setMainValues((previous) =>
				Object.assign({}, previous, { [field]: value })
			);
			services.set('main', field, value);
			dirty();
		},
		[services, dirty]
	);

	const setDevice = useCallback(
		(section, field, value) => {
			if (section == null) return;
			setDeviceValues((previous) =>
				Object.assign({}, previous, {
					[section]: Object.assign({}, previous[section] || {}, {
						[field]: value
					})
				})
			);
			services.set(section, field, value);
			dirty();
		},
		[services, dirty]
	);

	const configure = useCallback(
		(device) => {
			const sid = services.add('device');
			services.set(sid, 'engine', device.engine);
			services.set(sid, 'udn', device.udn);
			services.set(sid, 'enabled', '1');
			setDeviceValues((previous) =>
				Object.assign({}, previous, {
					[sid]: { engine: device.engine, udn: device.udn, enabled: '1' }
				})
			);
			setConfigured((previous) =>
				previous.concat([
					{
						name: sid,
						engine: device.engine,
						udn: device.udn,
						removed: false
					}
				])
			);
			dirty();
		},
		[services, dirty]
	);

	// The canonical payload the manager validates: the main section from uci,
	// and every device section - including ones added in this session, which
	// some LuCI versions only expose through uci.sections after a save.
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
					if (type !== 'device' || seen.has(item.name) || item.removed)
						continue;
					callback(
						Object.assign({}, deviceValues[item.name] || {}, {
							'.name': item.name,
							'.type': type
						})
					);
				}
			}
		});
	}, [services, configured, deviceValues]);

	const handleSave = useCallback(async () => {
		setSaveState({ text: t('Validating…'), tone: 'idle' });
		try {
			const result = await services.validate(buildConfig());
			if (!result || !result.ok) {
				const errors = (result && result.errors) || [
					t('Configuration validation failed.')
				];
				throw new Error(errors.join('\n'));
			}
			await services.save();
			setSaveState({ text: t('Saved; pending apply'), tone: 'idle' });
			await services.changesInit();
		} catch (error) {
			setSaveState({ text: t('Not saved — check settings'), tone: 'warning' });
			services.notify(message(error), 'danger');
			throw error;
		}
	}, [services, buildConfig, t]);

	const handleSaveApply = useCallback(
		async (rollback) => {
			await handleSave();
			try {
				setSaveState({ text: t('Applying…'), tone: 'idle' });
				await services.changesApply(rollback);
				// LuCI owns apply/rollback notifications; a status read only
				// reports processes.
				setSaveState({
					text: t('Apply requested — check LuCI confirmation'),
					tone: 'idle'
				});
				await refresh();
			} catch (error) {
				setSaveState({
					text: t('Apply failed — changes remain pending'),
					tone: 'warning'
				});
				throw error;
			}
		},
		[handleSave, services, refresh, t]
	);

	const runAction = useCallback(
		async (action) => {
			setBusy(true);
			try {
				const result = await services.action(action);
				if (!result || !result.ok)
					throw new Error(
						(result && result.error) || t('Service action failed.')
					);
				await refresh();
			} catch (error) {
				services.notify(message(error), 'danger');
			} finally {
				setBusy(false);
			}
		},
		[services, refresh, t]
	);

	const runScan = useCallback(async () => {
		setBusy(true);
		try {
			const result = await services.scan();
			if (!result || !result.ok)
				throw new Error(
					(result && result.error) || t('Could not start discovery.')
				);
			await refresh();
		} catch (error) {
			services.notify(message(error), 'danger');
		} finally {
			setBusy(false);
		}
	}, [services, refresh, t]);

	const loadLogs = useCallback(async () => {
		const result = await services.logs();
		if (!Array.isArray(result.lines))
			throw new Error(t('The log response was invalid.'));
		return { lines: result.lines, truncated: !!result.truncated };
	}, [services, t]);

	const model = useMemo(
		() => ({ status, configured, deviceValues }),
		[status, configured, deviceValues]
	);
	const devices = useMemo(() => mergeDevices(model), [model]);
	const duplicates = useMemo(() => duplicateNames(model), [model]);

	useEffect(() => {
		if (!selectedKey && devices.length > 0)
			setSelectedKey(devices[0].engine + '\n' + devices[0].udn);
		if (
			selectedKey &&
			!devices.some(
				(device) => device.engine + '\n' + device.udn === selectedKey
			)
		)
			setSelectedKey(
				devices.length ? devices[0].engine + '\n' + devices[0].udn : null
			);
	}, [devices, selectedKey]);

	const selectedDevice =
		devices.find(
			(device) => device.engine + '\n' + device.udn === selectedKey
		) || null;

	const handleDeviceChange = useCallback(
		(section, field, value) => {
			if (field === '__configure__') {
				configure(value);
				setSelectedKey(value.engine + '\n' + value.udn);
				return;
			}
			setDevice(section, field, value);
		},
		[configure, setDevice]
	);

	const withBusy = (task) => {
		setBusy(true);
		task()
			.catch(() => {})
			.finally(() => setBusy(false));
	};

	if (fatal) {
		return (
			<Alert tone="destructive">
				{t('Could not load settings. ')}
				{fatal}
			</Alert>
		);
	}

	if (!ready) {
		return (
			<div className="ac-loading-state">
				<div className="ac-loading-line ac-loading-line-wide" />
				<div className="ac-loading-line" />
				<div className="ac-loading-block" />
				<span>{t('Loading speakers and status…')}</span>
			</div>
		);
	}

	const chrome = (body) => (
		<PageChrome
			themeHost={themeHost}
			theme={theme}
			lang={lang}
			onLanguageChange={setLanguage}
			onThemeChange={setThemePreference}
			t={t}
			status={status}
			saveState={saveState}
			busy={busy}
			onSave={() => withBusy(handleSave)}
			onSaveApply={() => withBusy(() => handleSaveApply(false))}
			onReset={() => window.location.reload()}
			onRefresh={() => refresh()}
		>
			{body}
		</PageChrome>
	);

	if (mode === 'settings') {
		return chrome(
			<SettingsPage
				fields={fields.main}
				model={mainValues}
				set={setMain}
				rules={rules}
				t={t}
				inheritLabel={inheritLabel}
			/>
		);
	}

	return chrome(
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
			saveState={saveState}
			busy={busy}
			conflicts={(status && status.conflicts) || []}
			logs={logs}
			onSelect={(key) => setSelectedKey(key)}
			onDeviceChange={handleDeviceChange}
			onScan={runScan}
			onAction={runAction}
			onLoadLogs={async () => {
				try {
					setLogs(await loadLogs());
				} catch (error) {
					services.notify(message(error), 'danger');
				}
			}}
			onOpenSettings={() => {
				window.location.href =
					'/cgi-bin/luci/admin/services/airconnect-manager/settings';
			}}
			t={t}
			inheritLabel={inheritLabel}
		/>
	);
}
