import {
	Activity,
	AudioLines,
	FlaskConical,
	ScrollText,
	Settings2
} from 'lucide-react';

import { Field } from './field.jsx';

/**
 * The global settings, as its own LuCI page.
 *
 * The sixteen global options used to live in an overlay inside the device
 * workspace, which meant they were laid out in the width of the middle column
 * of a three-column layout. As a page of their own they get the full width,
 * and they are grouped into four topics so the list reads as four short
 * sections instead of one wall of controls.
 *
 * The grouping comes from each field's descriptor (`field.section`), so the
 * order and the membership live in lib/fields.js next to the fields
 * themselves.
 */
const SECTIONS = [
	{
		key: 'service',
		icon: Activity,
		title: 'Service and discovery',
		description: 'Choose which bridge engines are available on this router.'
	},
	{
		key: 'audio',
		icon: AudioLines,
		title: 'Audio defaults',
		description: 'Applied when a speaker does not define its own value.'
	},
	{
		key: 'compatibility',
		icon: FlaskConical,
		title: 'Compatibility',
		description:
			'Options for hardware that misbehaves. Leave the defaults unless a speaker needs them.'
	},
	{
		key: 'diagnostics',
		icon: ScrollText,
		title: 'Diagnostics',
		description: 'How much detail the service writes to its log.'
	}
];

export function SettingsPage({ fields, model, set, rules, t, inheritLabel }) {
	const _ = typeof t === 'function' ? t : function (s) { return s; };
	const list = fields || [];

	return (
		<div className="ac-settings-page">
			{SECTIONS.map((section) => {
				const members = list.filter(
					(field) => field.section === section.key
				);
				if (members.length === 0) return null;
				const Icon = section.icon;
				return (
					<section className="ac-settings-section" key={section.key}>
						<div className="ac-settings-section-heading">
							<span className="ac-settings-section-icon">
								<Icon />
							</span>
							<div>
								<h2>{_(section.title)}</h2>
								<p>{_(section.description)}</p>
							</div>
						</div>
						<div className="ac-form-grid">
							{members.map((field) => (
								<Field
									key={field.name}
									field={field}
									value={model[field.name]}
									onChange={(value) => set(field.name, value)}
									rules={rules}
									idPrefix="ac-main"
									inheritLabel={inheritLabel}
								/>
							))}
						</div>
					</section>
				);
			})}
		</div>
	);
}

/**
 * The heading the settings page shows when it has no fields yet. It exists so
 * a failed load still renders something explanatory rather than a blank area.
 */
export function SettingsEmpty({ t }) {
	const _ = typeof t === 'function' ? t : function (s) { return s; };
	return (
		<div className="ac-setup-state">
			<div className="ac-setup-illustration">
				<Settings2 />
			</div>
			<h2>{_('No settings available')}</h2>
			<p>{_('The configuration could not be read. Reload the page and try again.')}</p>
		</div>
	);
}
