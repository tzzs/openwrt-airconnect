import { useMemo, useState } from 'react';
import { Compass, Radio, Signal, Wifi } from 'lucide-react';

import { Button } from './ui/button.jsx';
import { DeviceEditor, DeviceHero } from './device.jsx';
import { DeviceRail } from './rail.jsx';
import { ServiceDrawer } from './service-panel.jsx';

/**
 * A compact readout of the three things a user checks first.
 *
 * It sits under the header as a single strip rather than as three cards: the
 * numbers are glanceable, not something to be read closely, so a row of
 * figures separated by rules costs less vertical space than a row of boxes.
 */
function HealthStrip({ status, presentation, t }) {
	const _ = typeof t === 'function' ? t : function (s) { return s; };
	const services = (status && status.services) || {};
	const upnp = services.upnp || {};
	const cast = services.cast || {};
	const list = Array.isArray(status && status.devices) ? status.devices : [];
	const online = list.filter((device) => device && device.online === true).length;
	const total = list.filter((device) => device && device.udn).length;
	const broadcast = (status && status.broadcast) || {};
	const activeEngine = upnp.running
		? _('UPnP')
		: cast.running
			? _('Chromecast')
			: _('No engine');

	const items = [
		{
			key: 'speakers',
			icon: Wifi,
			value: online + ' / ' + (total || 0),
			label: _('speakers discovered'),
			tone: online > 0 ? 'positive' : 'neutral'
		},
		{
			key: 'engine',
			icon: Radio,
			value: activeEngine,
			label: _('discovery engine'),
			tone: upnp.running || cast.running ? 'positive' : 'neutral'
		},
		{
			key: 'broadcast',
			icon: Signal,
			value: broadcast.observed_at
				? presentation.time(broadcast.observed_at)
				: _('Not measured'),
			label: _('last AirPlay observation'),
			tone: broadcast.error
				? 'warning'
				: broadcast.observed_at
					? 'positive'
					: 'unknown'
		}
	];

	return (
		<div className="ac-strip" aria-label={_('AirConnect health overview')}>
			{items.map((item) => {
				const Icon = item.icon;
				return (
					<div className="ac-strip-item" key={item.key}>
						<span className="ac-strip-icon">
							<Icon />
						</span>
						<span className="ac-strip-copy">
							<strong>{item.value}</strong>
							<small>{item.label}</small>
						</span>
						<span className={'ac-dot ac-dot-' + item.tone} />
					</div>
				);
			})}
		</div>
	);
}

function EmptyWorkspace({ onScan, scanState, t }) {
	const _ = typeof t === 'function' ? t : function (s) { return s; };
	return (
		<div className="ac-empty-workspace">
			<div className="ac-empty-orbit">
				<span />
				<span />
				<span />
				<Compass />
			</div>
			<h1>{_('Find the speakers on your network')}</h1>
			<p>
				{_('Start a discovery scan to see compatible UPnP and Chromecast speakers. They will appear here with a separate profile for each receiver.')}
			</p>
			<Button
				type="button"
				onClick={onScan}
				disabled={scanState.disabled || scanState.running}
			>
				<Compass />
				{scanState.running ? _('Scanning speakers') : _('Start discovery')}
			</Button>
			{scanState.disabled ? (
				<small>
					{_('Enable UPnP or Chromecast discovery in Global settings first.')}
				</small>
			) : null}
		</div>
	);
}

/**
 * The device workspace: the page body of the overview.
 *
 * Two columns now, not three. The service column became a drawer (see
 * service-panel.jsx), which leaves the speaker list and the speaker's own
 * controls the full width of the page - and those are the two things the page
 * exists for.
 */
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
	saveState,
	busy,
	conflicts,
	logs,
	onSelect,
	onDeviceChange,
	onScan,
	onAction,
	onLoadLogs,
	onSave,
	onSaveApply,
	onReset,
	onRefresh,
	onOpenSettings,
	t,
	inheritLabel
}) {
	const _ = typeof t === 'function' ? t : function (s) { return s; };
	const [railOpen, setRailOpen] = useState(false);

	const deviceFields = useMemo(() => {
		if (!selectedDevice) return null;
		return fields.device[selectedDevice.engine];
	}, [fields, selectedDevice]);

	return (
		<div className="ac-workspace">
			<HealthStrip status={status} presentation={presentation} t={t} />

			<div className="ac-workspace-body">
				{/*
				 * On a narrow viewport the rail becomes a collapsible panel
				 * instead of a column: the speaker list is navigation, and on a
				 * phone-sized screen the speaker's own controls matter more
				 * than the list.
				 */}
				<div className={'ac-rail-panel' + (railOpen ? ' is-open' : '')}>
					<button
						type="button"
						className="ac-rail-toggle"
						aria-expanded={railOpen}
						onClick={() => setRailOpen((open) => !open)}
					>
						{_('Speakers')} ({devices.length})
					</button>
					<DeviceRail
						devices={devices}
						selectedKey={selectedKey}
						onSelect={(key) => {
							onSelect(key);
							setRailOpen(false);
						}}
						onScan={onScan}
						scanState={scanState}
						presentation={presentation}
						t={t}
					/>
				</div>

				<main className="ac-main">
					{selectedDevice ? (
						<>
							<DeviceHero
								device={selectedDevice}
								presentation={presentation}
								t={t}
							/>
							<DeviceEditor
								device={selectedDevice}
								values={
									selectedDevice.section
										? deviceValues[selectedDevice.section]
										: null
								}
								fields={deviceFields}
								rules={rules}
								onChange={onDeviceChange}
								presentation={presentation}
								t={t}
								inheritLabel={inheritLabel}
							/>
						</>
					) : (
						<EmptyWorkspace onScan={onScan} scanState={scanState} t={t} />
					)}
				</main>
			</div>

			<footer className="ac-footer">
				<div className="ac-footer-left">
					<ServiceDrawer
						status={status}
						presentation={presentation}
						onAction={onAction}
						conflicts={conflicts}
						logs={logs}
						onLoadLogs={onLoadLogs}
						busy={busy}
						t={t}
					/>
					{onOpenSettings ? (
						<Button
							variant="outline"
							size="sm"
							type="button"
							onClick={onOpenSettings}
						>
							{_('Global settings')}
						</Button>
					) : null}
				</div>
				<div className="ac-footer-right">
					<span className="ac-footer-note">
						<span className="ac-footer-dot" />
						{_('Changes are kept locally until you save.')}
					</span>
					<span className="ac-footer-version">
						{_('AirConnect Manager')}
						{status && status.version
							? ' · ' + status.version
							: ' · ' + _('Version unknown')}
					</span>
				</div>
			</footer>
		</div>
	);
}
