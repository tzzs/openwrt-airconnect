import { useMemo, useState } from 'react';
import {
	ChevronRight,
	Compass,
	Search,
	Speaker,
	X
} from 'lucide-react';

import { Button } from './ui/button.jsx';

/**
 * The device list.
 *
 * It is the page's navigation, so it shares the surface colour with the rest
 * of the workspace and is separated by a rule rather than by a different
 * palette. A dark rail next to a light page read as a second application; a
 * rule plus a tint is enough to say "this is a different column".
 */
export function DeviceRail({
	devices,
	selectedKey,
	onSelect,
	onScan,
	scanState,
	presentation,
	t
}) {
	const _ = typeof t === 'function' ? t : function (s) { return s; };
	const [query, setQuery] = useState('');

	const filtered = useMemo(() => {
		const term = query.trim().toLowerCase();
		if (!term) return devices;
		return devices.filter((device) =>
			[device.name, device.original_name, device.model, device.udn].some(
				(value) => value && String(value).toLowerCase().includes(term)
			)
		);
	}, [devices, query]);

	const running = scanState.running || scanState.disabled;

	return (
		<aside className="ac-rail">
			<div className="ac-rail-top">
				<div className="ac-rail-heading">
					<h2>{_('Speakers')}</h2>
					<span className="ac-rail-count">{devices.length}</span>
				</div>
				<label className="ac-search-field">
					<Search />
					<input
						value={query}
						onChange={(event) => setQuery(event.target.value)}
						placeholder={_('Search speakers')}
						aria-label={_('Search speakers')}
					/>
					{query ? (
						<Button
							variant="ghost"
							size="icon"
							type="button"
							className="ac-search-clear"
							onClick={() => setQuery('')}
							title={_('Clear search')}
							aria-label={_('Clear search')}
						>
							<X />
						</Button>
					) : null}
				</label>
				<Button
					className="ac-scan-button"
					variant="outline"
					size="sm"
					type="button"
					disabled={scanState.disabled || scanState.running}
					onClick={onScan}
				>
					<Compass />
					{scanState.running ? _('Scanning speakers') : _('Scan for speakers')}
				</Button>
			</div>

			<nav className="ac-device-list" aria-label={_('Speakers')}>
				{filtered.map((device) => {
					const key = device.engine + '\n' + device.udn;
					const selected = key === selectedKey;
					const broadcast = presentation.deviceBroadcastBadge(
						device.broadcasting
					);
					return (
						/*
						 * A native <button> on purpose: this is a navigation
						 * list item, not an action. The shadcn Button brings
						 * the action chrome (fixed height, hover fill) that a
						 * row must not have, and <nav> semantics want the row
						 * itself to be the interactive element. It still
						 * follows the same rules as every other button:
						 * type="button" and aria-current for the selection.
						 */
						<button
							key={key}
							type="button"
							className={
								'ac-device-row' + (selected ? ' is-selected' : '')
							}
							aria-current={selected ? 'page' : undefined}
							onClick={() => onSelect(key)}
						>
							<span className="ac-device-avatar">
								<Speaker />
							</span>
							<span className="ac-device-row-copy">
								<strong>
									{device.name ||
										device.original_name ||
										_('Unnamed speaker')}
								</strong>
								<span>
									{device.engine === 'cast'
										? _('Chromecast')
										: _('UPnP / DLNA')}
								</span>
							</span>
							<span className="ac-device-row-state">
								<span
									className={
										'ac-dot ac-dot-' +
										(device.online === true
											? 'positive'
											: device.online === false
												? 'neutral'
												: 'unknown')
									}
								/>
								<small
									className={
										broadcast.tone === 'positive'
											? 'text-positive'
											: ''
									}
								>
									{broadcast.label}
								</small>
							</span>
							<ChevronRight className="ac-row-chevron" />
						</button>
					);
				})}
				{filtered.length === 0 ? (
					<div className="ac-rail-empty">
						<Search />
						<p>
							{query
								? _('No speaker matches this search.')
								: _('No speakers discovered yet.')}
						</p>
					</div>
				) : null}
			</nav>

			<div className="ac-rail-bottom">
				<span
					className={
						'ac-dot ' + (running ? 'ac-dot-neutral' : 'ac-dot-positive')
					}
				/>
				<span>
					{scanState.disabled
						? _('Enable an engine to scan')
						: _('Discovery is available')}
				</span>
			</div>
		</aside>
	);
}
