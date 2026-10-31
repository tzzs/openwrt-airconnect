import {
	Check,
	ChevronDown,
	Circle,
	Compass,
	Headphones,
	Info,
	Settings2,
	SlidersHorizontal
} from 'lucide-react';

import { Button } from './ui/button.jsx';
import { Switch } from './ui/switch.jsx';
import { Field } from './field.jsx';

/**
 * The speaker's own configuration.
 *
 * Only the everyday controls are open by default: the AirPlay name, the volume
 * and the enable switch. The compatibility options live behind a disclosure,
 * because they change how the engine talks to the hardware and a user should
 * not have to read past them to find the name field.
 */
export function DeviceEditor({
	device,
	values,
	fields,
	rules,
	onChange,
	presentation,
	t,
	inheritLabel
}) {
	const _ = typeof t === 'function' ? t : function (s) { return s; };
	const list = fields || [];
	const primary = list.filter((field) => field.group === 'primary');
	const advanced = list.filter((field) => field.group !== 'primary');
	const sectionId = device.section || 'new';
	const set = (field, value) => onChange(device.section, field, value);

	if (!device.section) {
		return (
			<div className="ac-setup-state">
				<div className="ac-setup-illustration">
					<Compass />
				</div>
				<h2>{_('This speaker is discovered')}</h2>
				<p>
					{_('Create a local profile to give it an AirPlay name, set its volume and choose how it bridges audio.')}
				</p>
				<Button
					type="button"
					onClick={() => onChange(null, '__configure__', device)}
				>
					<Settings2 />
					{_('Set up this speaker')}
				</Button>
			</div>
		);
	}

	return (
		<div className="ac-editor-stack">
			<section className="ac-panel ac-panel-accent">
				<div className="ac-panel-heading">
					<div>
						<h2>{_('Everyday controls')}</h2>
						<p>{_('The settings you are most likely to change.')}</p>
					</div>
					<Switch
						id={'device-enabled-' + sectionId}
						checked={(values && values.enabled) !== '0'}
						onCheckedChange={(checked) => set('enabled', checked ? '1' : '0')}
					/>
				</div>
				<div className="ac-form-grid">
					{primary
						.filter((field) => field.name !== 'enabled')
						.map((field) => (
							<Field
								key={field.name}
								field={field}
								value={values && values[field.name]}
								onChange={(value) => set(field.name, value)}
								rules={rules}
								idPrefix={'ac-device-' + sectionId}
								inheritLabel={inheritLabel}
							/>
						))}
				</div>
			</section>

			<details className="ac-panel ac-disclosure">
				<summary>
					<span>
						<SlidersHorizontal />
						{_('Audio and compatibility')}
					</span>
					<span className="ac-disclosure-hint">
						{advanced.length} {_('Advanced')}
						<ChevronDown className="ac-disclosure-chevron" />
					</span>
				</summary>
				<div className="ac-form-grid">
					{advanced.map((field) => (
						<Field
							key={field.name}
							field={field}
							value={values && values[field.name]}
							onChange={(value) => set(field.name, value)}
							rules={rules}
							idPrefix={'ac-device-' + sectionId}
							inheritLabel={inheritLabel}
						/>
					))}
				</div>
			</details>

			<section className="ac-panel">
				<div className="ac-panel-heading">
					<div>
						<h2>{_('Device facts')}</h2>
						<p>{_('Reported by the last discovery response.')}</p>
					</div>
					<Info />
				</div>
				<dl className="ac-fact-grid">
					<Fact label={_('Original name')} value={presentation.value(device.original_name)} />
					<Fact label={_('IP address')} value={presentation.value(device.address)} />
					<Fact label={_('Model')} value={presentation.value(device.model)} />
					<Fact label={_('Manufacturer')} value={presentation.value(device.manufacturer)} />
					<Fact label={_('Device identifier')} value={presentation.value(device.udn)} />
					<Fact
						label={_('Last discovered')}
						value={
							device.last_seen
								? presentation.time(device.last_seen)
								: _('Not provided')
						}
					/>
				</dl>
			</section>
		</div>
	);
}

function Fact({ label, value }) {
	return (
		<div className="ac-fact">
			<dt>{label}</dt>
			<dd>{value}</dd>
		</div>
	);
}

/**
 * The header of the selected speaker: which one it is, and the two facts a
 * user checks first - whether it is online and whether it is advertising.
 */
export function DeviceHero({ device, presentation, t }) {
	const _ = typeof t === 'function' ? t : function (s) { return s; };
	const broadcast = presentation.deviceBroadcastBadge(device.broadcasting);
	return (
		<div className="ac-device-hero">
			<div className="ac-hero-icon">
				<Headphones />
			</div>
			<div className="ac-hero-copy">
				<span className="ac-hero-engine">
					{device.engine === 'cast'
						? _('Chromecast receiver')
						: _('UPnP / DLNA receiver')}
				</span>
				<h1>
					{device.name || device.original_name || _('Unnamed speaker')}
				</h1>
				<p>
					{device.original_name && device.original_name !== device.name
						? _('AirPlay name override is active.')
						: _('Using the original speaker name.')}
				</p>
			</div>
			<div className="ac-hero-state">
				<span
					className={
						'ac-hero-pill ' +
						(device.online === true ? 'is-positive' : 'is-neutral')
					}
				>
					{device.online === true ? <Check /> : <Circle />}
					{presentation.onlineLabel(device.online)}
				</span>
				<span
					className={'ac-hero-pill is-' + broadcast.tone}
				>
					{broadcast.label}
				</span>
			</div>
		</div>
	);
}
