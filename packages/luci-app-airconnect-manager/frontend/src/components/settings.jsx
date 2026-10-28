import {
	Card,
	CardContent,
	CardDescription,
	CardHeader,
	CardTitle
} from './ui/card.jsx';
import { Field } from './field.jsx';

/**
 * The Settings tab: the global defaults, rendered from lib/fields.js.
 *
 * The field list is data, so this file only decides the grouping and the
 * headings. Everything a reviewer would need to check - which control, which
 * options, which rule - is in the descriptor.
 */
export function SettingsPanel({ fields, model, set, rules, t, inheritLabel }) {
	const _ = typeof t === 'function' ? t : function (s) { return s; };
	const primary = fields.filter((field) => field.group === 'primary');
	const advanced = fields.filter((field) => field.group !== 'primary');

	const render = (field) => (
		<Field
			key={field.name}
			field={field}
			value={model[field.name]}
			onChange={(value) => set(field.name, value)}
			rules={rules}
			idPrefix="ac-main"
			inheritLabel={inheritLabel}
		/>
	);

	return (
		<div className="space-y-6">
			<Card>
				<CardHeader>
					<CardTitle>{_('General settings')}</CardTitle>
					<CardDescription>{_('Global defaults apply unless a speaker has its own override.')}</CardDescription>
				</CardHeader>
				<CardContent className="space-y-4">{primary.map(render)}</CardContent>
			</Card>

			<Card>
				<CardHeader>
					<CardTitle>{_('Advanced settings')}</CardTitle>
					<CardDescription>
						{_('Compatibility and detail options. Leave the defaults unless a speaker needs them.')}
					</CardDescription>
				</CardHeader>
				<CardContent className="space-y-4">{advanced.map(render)}</CardContent>
			</Card>
		</div>
	);
}
