import {
	Card,
	CardContent,
	CardHeader,
	CardTitle
} from './ui/card.jsx';
import { Button } from './ui/button.jsx';
import { Alert, StatusBadge } from './feedback.jsx';
import { Field } from './field.jsx';

/**
 * One speaker card: the per-speaker overrides from lib/fields.js, and the
 * facts discovery reported.
 *
 * The broadcast badge and the broadcast fact both come from
 * lib/presentation.js, which keeps "discovered", "service running" and
 * "advertised on AirPlay" from collapsing into each other.
 */
export function DeviceCard({
	device,
	values,
	onChange,
	onConfigure,
	rules,
	fields,
	presentation,
	observation,
	t,
	inheritLabel
}) {
	const _ = typeof t === 'function' ? t : function (s) { return s; };
	const observed = observation || {};
	const configured = device.section != null;
	const idPrefix = 'ac-dev-' + (device.section || 'new');
	const set = (name, value) => onChange(device.section, name, value);
	const badge = presentation.deviceBroadcastBadge(device.broadcasting);

	const render = (field) => (
		<Field
			key={field.name}
			field={field}
			value={values ? values[field.name] : undefined}
			onChange={(value) => set(field.name, value)}
			rules={rules}
			idPrefix={idPrefix}
			inheritLabel={inheritLabel}
		/>
	);

	const primary = (fields || []).filter((field) => field.group === 'primary');
	const advanced = (fields || []).filter((field) => field.group !== 'primary');

	const facts = [
		[_('Original name'), presentation.value(device.original_name)],
		[_('IP address'), presentation.value(device.address)],
		[_('Model'), presentation.value(device.model)],
		[_('Manufacturer'), presentation.value(device.manufacturer)],
		[_('Device identifier (UDN)'), presentation.value(device.udn)],
		[_('Last discovered'), device.last_seen ? presentation.time(device.last_seen) : _('Not provided')],
		// The observation time is the mDNS scan, not the discovery scan above.
		[_('AirPlay broadcast'),
			presentation.deviceBroadcastFact(device.broadcasting, observed.observed_at)]
	];

	return (
		<Card>
			<CardHeader className="flex-row items-start justify-between space-y-0">
				<div className="space-y-1">
					<CardTitle>
						{presentation.value(device.name || device.original_name || _('Unnamed speaker'))}
					</CardTitle>
					<p className="text-sm text-muted-foreground">
						{presentation.value(device.original_name)}
					</p>
				</div>
				<div className="flex flex-wrap justify-end gap-1.5">
					<StatusBadge tone="neutral">{presentation.engineLabel(device.engine)}</StatusBadge>
					<StatusBadge tone={presentation.onlineTone(device.online)}>
						{presentation.onlineLabel(device.online)}
					</StatusBadge>
					<StatusBadge tone={badge.tone}>{badge.label}</StatusBadge>
				</div>
			</CardHeader>
			<CardContent className="space-y-4">
				{configured ? (
					<>
						<div className="space-y-4">{primary.map(render)}</div>
						<details className="rounded-lg border border-border p-3">
							<summary className="cursor-pointer text-sm font-medium">
								{_('Advanced audio settings')}
							</summary>
							<div className="mt-4 space-y-4">{advanced.map(render)}</div>
						</details>
					</>
				) : (
					<div className="flex flex-wrap items-center justify-between gap-4 rounded-lg border border-dashed border-border p-3">
						<p className="text-sm text-muted-foreground">
							{_('Discovered on your network. Configure this speaker to override its AirPlay name and volume.')}
						</p>
						<Button variant="outline" size="sm" onClick={() => onConfigure(device)}>
							{_('Configure speaker')}
						</Button>
					</div>
				)}
				<dl className="grid grid-cols-1 gap-2 border-t border-border pt-3 text-sm sm:grid-cols-2">
					{facts.map(([label, value]) => (
						<div key={label} className="flex flex-col gap-0.5">
							<dt className="text-xs font-medium text-muted-foreground">{label}</dt>
							<dd className="break-all text-foreground">{value}</dd>
						</div>
					))}
				</dl>
			</CardContent>
		</Card>
	);
}

/**
 * The Speakers tab: the card list, the scan action and the duplicate-name
 * warning. The warning is advisory only - two receivers with one name are
 * confusing but still a configuration the engines accept, so it never blocks a
 * save.
 */
export function SpeakersPanel({
	devices,
	deviceValues,
	onDeviceChange,
	onConfigure,
	rules,
	fields,
	presentation,
	onScan,
	scanState,
	duplicates,
	observation,
	t,
	inheritLabel
}) {
	const _ = typeof t === 'function' ? t : function (s) { return s; };
	const status = presentation.scanStatus(scanState);

	return (
		<div className="space-y-4">
			<div className="flex flex-wrap items-end justify-between gap-3">
				<div>
					<h2 className="text-base font-semibold">
						{_('Speakers')} <span className="text-muted-foreground">({devices.length})</span>
					</h2>
					<p className="text-sm text-muted-foreground">
						{_('Set the AirPlay name and volume for each speaker.')}
					</p>
				</div>
				<Button disabled={scanState.disabled} onClick={onScan}>
					{scanState.running ? _('Scanning…') : _('Scan for speakers')}
				</Button>
			</div>

			<p className="text-sm text-muted-foreground" role={status.role}>{status.text}</p>

			{duplicates.length > 0 ? (
				<Alert tone="warning">
					<strong>{_('More than one speaker uses the same AirPlay name.')}</strong>
					{duplicates.map((name) => <div key={name}>{name}</div>)}
					<p className="mt-1">
						{_('AirPlay lists these receivers under one name. Give each speaker its own name.')}
					</p>
				</Alert>
			) : null}

			{devices.length === 0 ? (
				<div className="rounded-xl border border-dashed border-border p-10 text-center">
					<h3 className="text-base font-semibold">{_('Find your speakers')}</h3>
					<p className="mx-auto mt-2 max-w-md text-sm text-muted-foreground">
						{_('Turn on a discovery engine in Settings, then scan. Keep your speaker online on the same LAN and enable DLNA when required.')}
					</p>
				</div>
			) : (
				<div className="space-y-4">
					{devices.map((device) => (
						<DeviceCard
							key={device.engine + '\n' + device.udn}
							device={device}
							values={device.section != null ? deviceValues[device.section] : undefined}
							onChange={onDeviceChange}
							onConfigure={onConfigure}
							rules={rules}
							fields={fields[device.engine]}
							presentation={presentation}
							observation={observation}
							t={t}
							inheritLabel={inheritLabel}
						/>
					))}
				</div>
			)}
		</div>
	);
}
