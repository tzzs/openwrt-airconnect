import { useMemo, useState } from 'react';
import {
	Activity,
	AlertTriangle,
	Check,
	ChevronRight,
	Circle,
	Clock3,
	Cog,
	Compass,
	Headphones,
	Info,
	Menu,
	Mic2,
	MoreHorizontal,
	Pause,
	Play,
	Radio,
	RefreshCw,
	Search,
	Settings2,
	Signal,
	SlidersHorizontal,
	Speaker,
	Square,
	Wifi,
	X
} from 'lucide-react';

import { Button } from './ui/button.jsx';
import { Input } from './ui/input.jsx';
import { Switch } from './ui/switch.jsx';
import { Alert } from './feedback.jsx';
import { Field } from './field.jsx';

function copy(t, text) {
	return typeof t === 'function' ? t(text) : text;
}

function toneForBroadcast(value) {
	return value === true ? 'positive' : value === false ? 'neutral' : 'unknown';
}

function StatusDot({ tone = 'neutral' }) {
	return <span className={'ac-dot ac-dot-' + tone} aria-hidden="true" />;
}

function StatusPill({ tone = 'neutral', icon: Icon = Circle, children }) {
	return (
		<span className={'ac-status-pill ac-pill-' + tone}>
			<Icon className="ac-pill-icon" />
			{children}
		</span>
	);
}

function HealthStrip({ status, presentation, t }) {
	const _ = (text) => copy(t, text);
	const services = (status && status.services) || {};
	const upnp = services.upnp || {};
	const cast = services.cast || {};
	const online = Array.isArray(status && status.devices)
		? status.devices.filter((device) => device && device.online === true).length
		: 0;
	const total = Array.isArray(status && status.devices)
		? status.devices.filter((device) => device && device.udn).length
		: 0;
	const broadcast = (status && status.broadcast) || {};
	const activeEngine = upnp.running ? _('UPnP') : cast.running ? _('Chromecast') : _('No engine');

	return (
		<div className="ac-health-strip" aria-label={_('AirConnect health overview')}>
			<div className="ac-health-item">
				<span className="ac-health-icon ac-health-icon-blue"><Wifi /></span>
				<span className="ac-health-copy">
					<strong>{online} / {total || 0}</strong>
					<small>{_('speakers discovered')}</small>
				</span>
				<StatusDot tone={online > 0 ? 'positive' : 'neutral'} />
			</div>
			<div className="ac-health-item">
				<span className="ac-health-icon ac-health-icon-purple"><Radio /></span>
				<span className="ac-health-copy">
					<strong>{activeEngine}</strong>
					<small>{_('discovery engine')}</small>
				</span>
				<StatusDot tone={upnp.running || cast.running ? 'positive' : 'neutral'} />
			</div>
			<div className="ac-health-item">
				<span className="ac-health-icon ac-health-icon-green"><Signal /></span>
				<span className="ac-health-copy">
					<strong>{broadcast.observed_at ? presentation.time(broadcast.observed_at) : _('Not measured')}</strong>
					<small>{_('last AirPlay observation')}</small>
				</span>
				<StatusDot tone={broadcast.error ? 'warning' : broadcast.observed_at ? 'positive' : 'unknown'} />
			</div>
		</div>
	);
}

function TopBar({ status, saveState, busy, onSave, onSaveApply, onReset, onSettings, onRefresh, t }) {
	const _ = (text) => copy(t, text);
	const services = (status && status.services) || {};
	const running = (services.upnp && services.upnp.running) || (services.cast && services.cast.running);
	return (
		<div className="ac-workspace-header" role="banner">
			<div className="ac-brand-lockup">
				<div className="ac-brand-mark"><Activity /></div>
				<div>
					<strong>AirConnect</strong>
					<span>{_('Speaker bridge')}</span>
				</div>
			</div>
			<div className="ac-header-status">
				<StatusPill tone={running ? 'positive' : 'neutral'} icon={running ? Play : Pause}>
					{running ? _('Service running') : _('Service stopped')}
				</StatusPill>
				<span className={'ac-save-state ac-save-' + saveState.tone} role="status" aria-live="polite">
					{saveState.text}
				</span>
				<Button variant="ghost" size="icon" className="ac-icon-button" disabled={busy} onClick={onRefresh} title={_('Refresh status')}>
					<RefreshCw />
				</Button>
				<Button variant="outline" size="sm" disabled={busy} onClick={onSettings}>
					<Settings2 /> {_('Global settings')}
				</Button>
				<Button variant="outline" size="sm" disabled={busy} onClick={onSave}>
					{_('Save')}
				</Button>
				<Button size="sm" disabled={busy} onClick={onSaveApply}>
					{_('Save and apply')}
				</Button>
				<Button variant="ghost" size="icon" className="ac-icon-button" disabled={busy} onClick={onReset} title={_('Reset')}>
					<MoreHorizontal />
				</Button>
			</div>
		</div>
	);
}

function DeviceRail({ devices, selectedKey, onSelect, onScan, scanState, onConfigure, presentation, t }) {
	const _ = (text) => copy(t, text);
	const [query, setQuery] = useState('');
	const filtered = useMemo(() => {
		const term = query.trim().toLowerCase();
		if (!term) return devices;
		return devices.filter((device) => [device.name, device.original_name, device.model, device.udn]
			.some((value) => value && String(value).toLowerCase().includes(term)));
	}, [devices, query]);

	return (
		<aside className="ac-device-rail">
			<div className="ac-rail-heading">
				<div>
					<span className="ac-section-label">{_('Workspace')}</span>
					<h2>{_('Speakers')} <span>{devices.length}</span></h2>
				</div>
				<Button variant="ghost" size="icon" className="ac-icon-button" title={_('Rail menu')}>
					<Menu />
				</Button>
			</div>
			<label className="ac-search-field">
				<Search />
				<input value={query} onChange={(event) => setQuery(event.target.value)} placeholder={_('Search speakers')} />
				{query ? <button type="button" onClick={() => setQuery('')} aria-label={_('Clear search')}><X /></button> : null}
			</label>
			<Button className="ac-scan-button" variant="outline" disabled={scanState.disabled || scanState.running} onClick={onScan}>
				<Compass /> {scanState.running ? _('Scanning speakers') : _('Scan for speakers')}
			</Button>
			<div className="ac-rail-caption">
				<span>{scanState.error ? _('Discovery error') : scanState.last_scan ? _('Last scan') : _('Ready to discover')}</span>
				{scanState.last_scan ? <time>{presentation.time(scanState.last_scan)}</time> : null}
			</div>
			<nav className="ac-device-list" aria-label={_('Speakers')}>
				{filtered.map((device) => {
					const key = device.engine + '\n' + device.udn;
					const selected = key === selectedKey;
					const broadcast = presentation.deviceBroadcastBadge(device.broadcasting);
					return (
						<button key={key} type="button" className={'ac-device-row' + (selected ? ' is-selected' : '')} onClick={() => onSelect(key)}>
							<span className="ac-device-avatar"><Speaker /></span>
							<span className="ac-device-row-copy">
								<strong>{device.name || device.original_name || _('Unnamed speaker')}</strong>
								<span>{device.engine === 'cast' ? _('Chromecast') : _('UPnP / DLNA')}</span>
							</span>
							<span className="ac-device-row-state">
								<StatusDot tone={device.online === true ? 'positive' : device.online === false ? 'neutral' : 'unknown'} />
								<small className={broadcast.tone === 'positive' ? 'text-positive' : ''}>{broadcast.label}</small>
							</span>
							<ChevronRight className="ac-row-chevron" />
						</button>
					);
				})}
				{filtered.length === 0 ? (
					<div className="ac-rail-empty">
						<Search />
						<p>{query ? _('No speaker matches this search.') : _('No speakers discovered yet.')}</p>
					</div>
				) : null}
			</nav>
			<div className="ac-rail-footer">
				<StatusDot tone={scanState.disabled ? 'neutral' : 'positive'} />
				<span>{scanState.disabled ? _('Enable an engine to scan') : _('Discovery is available')}</span>
			</div>
		</aside>
	);
}

function Metric({ label, value, note, icon: Icon, tone = 'neutral' }) {
	return (
		<div className="ac-metric">
			<span className={'ac-metric-icon ac-metric-' + tone}><Icon /></span>
			<div><small>{label}</small><strong>{value}</strong>{note ? <span>{note}</span> : null}</div>
		</div>
	);
}

function DeviceHero({ device, presentation, t }) {
	const _ = (text) => copy(t, text);
	const broadcast = presentation.deviceBroadcastBadge(device.broadcasting);
	return (
		<div className="ac-device-hero">
			<div className="ac-hero-icon"><Headphones /></div>
			<div className="ac-hero-copy">
				<span className="ac-section-label">{device.engine === 'cast' ? _('Chromecast receiver') : _('UPnP / DLNA receiver')}</span>
				<h1>{device.name || device.original_name || _('Unnamed speaker')}</h1>
				<p>{device.original_name && device.original_name !== device.name ? _('AirPlay name override is active.') : _('Using the original speaker name.')}</p>
			</div>
			<div className="ac-hero-state">
				<StatusPill tone={device.online === true ? 'positive' : 'neutral'} icon={device.online === true ? Check : Circle}>
					{presentation.onlineLabel(device.online)}
				</StatusPill>
				<StatusPill tone={broadcast.tone} icon={broadcast.tone === 'positive' ? Radio : Signal}>
					{broadcast.label}
				</StatusPill>
			</div>
		</div>
	);
}

function DeviceEditor({ device, values, fields, rules, onChange, presentation, t, inheritLabel }) {
	const _ = (text) => copy(t, text);
	const primary = (fields || []).filter((field) => field.group === 'primary');
	const advanced = (fields || []).filter((field) => field.group !== 'primary');
	const sectionId = device.section || 'new';
	const set = (field, value) => onChange(device.section, field, value);

	if (!device.section) {
		return (
			<div className="ac-setup-state">
				<div className="ac-setup-illustration"><Compass /></div>
				<h2>{_('This speaker is discovered')}</h2>
				<p>{_('Create a local profile to give it an AirPlay name, set its volume and choose how it bridges audio.')}</p>
				<Button onClick={() => onChange(null, '__configure__', device)}><Settings2 /> {_('Set up this speaker')}</Button>
			</div>
		);
	}

	return (
		<div className="ac-editor-stack">
			<section className="ac-editor-section ac-editor-section-focus">
				<div className="ac-editor-heading">
					<div><h2>{_('Everyday controls')}</h2><p>{_('The settings you are most likely to change.')}</p></div>
					<Switch id={'device-enabled-' + sectionId} checked={(values && values.enabled) !== '0'} onCheckedChange={(checked) => set('enabled', checked ? '1' : '0')} />
				</div>
				<div className="ac-editor-grid">{primary.filter((field) => field.name !== 'enabled').map((field) => <Field key={field.name} field={field} value={values && values[field.name]} onChange={(value) => set(field.name, value)} rules={rules} idPrefix={'ac-device-' + sectionId} inheritLabel={inheritLabel} />)}</div>
		</section>
		<details className="ac-editor-section ac-disclosure">
			<summary><span><SlidersHorizontal /> {_('Audio and compatibility')}</span><span>{_('Advanced')}</span></summary>
			<div className="ac-editor-grid">{advanced.map((field) => <Field key={field.name} field={field} value={values && values[field.name]} onChange={(value) => set(field.name, value)} rules={rules} idPrefix={'ac-device-' + sectionId} inheritLabel={inheritLabel} />)}</div>
		</details>
		<section className="ac-editor-section">
			<div className="ac-editor-heading"><div><h2>{_('Device facts')}</h2><p>{_('Reported by the last discovery response.')}</p></div><Info /></div>
			<dl className="ac-fact-grid">
				<Fact label={_('Original name')} value={presentation.value(device.original_name)} />
				<Fact label={_('IP address')} value={presentation.value(device.address)} />
				<Fact label={_('Model')} value={presentation.value(device.model)} />
				<Fact label={_('Manufacturer')} value={presentation.value(device.manufacturer)} />
				<Fact label={_('Device identifier')} value={presentation.value(device.udn)} />
				<Fact label={_('Last discovered')} value={device.last_seen ? presentation.time(device.last_seen) : _('Not provided')} />
			</dl>
		</section>
	</div>
	);
}

function Fact({ label, value }) {
	return <div className="ac-fact"><dt>{label}</dt><dd>{value}</dd></div>;
}

function EmptyWorkspace({ onScan, scanState, t }) {
	const _ = (text) => copy(t, text);
	return (
		<div className="ac-empty-workspace">
			<div className="ac-empty-orbit"><span /><span /><span /><Compass /></div>
			<span className="ac-section-label">{_('AirPlay bridge')}</span>
			<h1>{_('Find the speakers on your network')}</h1>
			<p>{_('Start a discovery scan to see compatible UPnP and Chromecast speakers. They will appear here with a separate profile for each receiver.')}</p>
			<Button onClick={onScan} disabled={scanState.disabled || scanState.running}><Compass /> {scanState.running ? _('Scanning speakers') : _('Start discovery')}</Button>
			{scanState.disabled ? <small>{_('Enable UPnP or Chromecast discovery in Global settings first.')}</small> : null}
		</div>
	);
}

function UtilityRail({ status, presentation, onAction, conflicts, logs, onLoadLogs, busy, t }) {
	const _ = (text) => copy(t, text);
	const services = (status && status.services) || {};
	const broadcast = (status && status.broadcast) || {};
	const playback = (status && status.playback) || {};
	return (
		<aside className="ac-utility-rail">
			<section className="ac-utility-block">
				<div className="ac-utility-heading"><span>{_('Service control')}</span><MoreHorizontal /></div>
				<div className="ac-service-row"><span><StatusDot tone={services.upnp && services.upnp.running ? 'positive' : 'neutral'} />{_('UPnP discovery')}</span><strong>{presentation.serviceLabel(services.upnp)}</strong></div>
				<div className="ac-service-row"><span><StatusDot tone={services.cast && services.cast.running ? 'positive' : 'neutral'} />{_('Chromecast discovery')}</span><strong>{presentation.serviceLabel(services.cast)}</strong></div>
				<div className="ac-utility-actions">
					<Button size="sm" disabled={busy || conflicts.length > 0} onClick={() => onAction('start')}><Play /> {_('Start')}</Button>
					<Button size="sm" variant="outline" disabled={busy} onClick={() => onAction('restart')}><RefreshCw /> {_('Restart')}</Button>
				</div>
				{conflicts.length ? <Alert tone="warning"><strong>{_('Another AirConnect instance was detected.')}</strong><p>{conflicts.join('\n')}</p></Alert> : null}
			</section>
			<section className="ac-utility-block">
				<div className="ac-utility-heading"><span>{_('Signal report')}</span><Signal /></div>
				<div className="ac-signal-card">
					<div><span>{_('AirPlay broadcast')}</span><strong>{presentation.broadcastText(services.upnp && services.upnp.broadcasting, broadcast.observed_at, broadcast.error)}</strong></div>
					<StatusDot tone={toneForBroadcast(services.upnp && services.upnp.broadcasting)} />
				</div>
				<div className="ac-signal-card">
					<div><span>{_('Playback')}</span><strong>{presentation.playbackText({ playback })}</strong></div>
					<StatusDot tone="unknown" />
				</div>
				{broadcast.observed_at ? <small className="ac-observed-time"><Clock3 /> {_('Observed')} {presentation.time(broadcast.observed_at)}</small> : null}
			</section>
			<section className="ac-utility-block ac-log-block">
				<div className="ac-utility-heading"><span>{_('Recent logs')}</span><Button variant="ghost" size="icon" className="ac-icon-button" disabled={busy} onClick={onLoadLogs} title={_('Load recent logs')}><RefreshCw /></Button></div>
				<pre>{logs ? (logs.lines.length ? logs.lines.slice(-8).join('\n') : _('No log entries.')) : _('Logs appear here when requested.')}</pre>
			</section>
		</aside>
	);
}

function SettingsWorkspace({ fields, model, set, rules, onClose, t, inheritLabel }) {
	const _ = (text) => copy(t, text);
	return (
		<section className="ac-settings-workspace">
			<div className="ac-settings-titlebar"><div><span className="ac-section-label">{_('Configuration')}</span><h1>{_('Global settings')}</h1><p>{_('Defaults for every speaker without a local override.')}</p></div><Button variant="ghost" size="icon" className="ac-icon-button" onClick={onClose} title={_('Close settings')}><X /></Button></div>
			<div className="ac-settings-layout">
				<section className="ac-settings-column"><div className="ac-settings-column-heading"><Cog /><div><h2>{_('Network and discovery')}</h2><p>{_('Choose which bridge engines are available on this router.')}</p></div></div><div className="ac-editor-grid">{fields.filter((field) => field.group === 'primary').map((field) => <Field key={field.name} field={field} value={model[field.name]} onChange={(value) => set(field.name, value)} rules={rules} idPrefix="ac-main" inheritLabel={inheritLabel} />)}</div></section>
				<section className="ac-settings-column"><div className="ac-settings-column-heading"><SlidersHorizontal /><div><h2>{_('Audio defaults')}</h2><p>{_('Applied when a speaker does not define its own value.')}</p></div></div><div className="ac-editor-grid">{fields.filter((field) => field.group !== 'primary').map((field) => <Field key={field.name} field={field} value={model[field.name]} onChange={(value) => set(field.name, value)} rules={rules} idPrefix="ac-main" inheritLabel={inheritLabel} />)}</div></section>
			</div>
		</section>
	);
}

export function Workspace({
	status,
	presentation,
	devices,
	selectedKey,
	selectedDevice,
	deviceValues,
	fields,
	rules,
	scanState,
	mainValues,
	saveState,
	busy,
	conflicts,
	logs,
	onSelect,
	onConfigure,
	onDeviceChange,
	onMainChange,
	onScan,
	onAction,
	onLoadLogs,
	onSave,
	onSaveApply,
	onReset,
	onRefresh,
	onSettings,
	settingsOpen,
	onCloseSettings,
	t,
	inheritLabel
}) {
	const _ = (text) => copy(t, text);
	return (
		<div className="ac-console">
			<TopBar status={status} saveState={saveState} busy={busy} onSave={onSave} onSaveApply={onSaveApply} onReset={onReset} onSettings={onSettings} onRefresh={onRefresh} t={t} />
			<HealthStrip status={status} presentation={presentation} t={t} />
			<div className="ac-console-layout">
				<DeviceRail devices={devices} selectedKey={selectedKey} onSelect={onSelect} onScan={onScan} scanState={scanState} onConfigure={onConfigure} presentation={presentation} t={t} />
				<main className="ac-main-workspace">
					{settingsOpen ? <SettingsWorkspace fields={fields.main} model={mainValues} set={onMainChange} rules={rules} onClose={onCloseSettings} t={t} inheritLabel={inheritLabel} /> : selectedDevice ? <><DeviceHero device={selectedDevice} presentation={presentation} t={t} /><DeviceEditor device={selectedDevice} values={selectedDevice.section ? deviceValues[selectedDevice.section] : null} fields={fields.device[selectedDevice.engine]} rules={rules} onChange={onDeviceChange} presentation={presentation} t={t} inheritLabel={inheritLabel} /></> : <EmptyWorkspace onScan={onScan} scanState={scanState} t={t} />}
				</main>
				<UtilityRail status={status} presentation={presentation} onAction={onAction} conflicts={conflicts} logs={logs} onLoadLogs={onLoadLogs} busy={busy} t={t} />
			</div>
			<footer className="ac-console-footer"><span><span className="ac-footer-dot" />{_('Changes are kept locally until you save.')}</span><span>{_('AirConnect Manager')} · {status && status.version ? status.version : _('Version unknown')}</span></footer>
		</div>
	);
}
