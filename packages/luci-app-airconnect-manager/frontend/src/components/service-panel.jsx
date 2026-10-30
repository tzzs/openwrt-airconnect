import { useState } from 'react';
import { Activity, Clock3, Play, RefreshCw, Signal } from 'lucide-react';

import { Button } from './ui/button.jsx';
import { Alert } from './feedback.jsx';
import {
	Drawer,
	DrawerContent,
	DrawerHeader,
	DrawerTrigger
} from './ui/drawer.jsx';

/**
 * The service panel: what the bridge engines are doing, and the logs.
 *
 * This used to be a permanent third column. It is reference material, not the
 * page's subject, and the column it occupied forced the speaker's own controls
 * into a width where the two-column form stopped working. A drawer keeps it
 * one click away without spending the width.
 */
export function ServiceDrawer({
	status,
	presentation,
	onAction,
	conflicts,
	logs,
	onLoadLogs,
	busy,
	t
}) {
	const _ = typeof t === 'function' ? t : function (s) { return s; };
	const [open, setOpen] = useState(false);
	const services = (status && status.services) || {};
	const broadcast = (status && status.broadcast) || {};
	const playback = (status && status.playback) || {};

	return (
		<Drawer open={open} onOpenChange={setOpen}>
			<DrawerTrigger asChild>
				<Button variant="outline" size="sm" type="button" className="ac-service-trigger">
					<Activity />
					{_('Service status')}
				</Button>
			</DrawerTrigger>
			<DrawerContent aria-label={_('Service status')}>
				<DrawerHeader
					title={_('Service control')}
					description={_('Service actions use the last applied settings. Stopping or restarting briefly disconnects AirPlay.')}
				>
					<Button
						variant="ghost"
						size="icon"
						type="button"
						className="ac-icon-button"
						disabled={busy}
						onClick={() => onAction('restart')}
						title={_('Restart')}
						aria-label={_('Restart')}
					>
						<RefreshCw />
					</Button>
				</DrawerHeader>

				<div className="ac-drawer-body">
					<section className="ac-drawer-section">
						<div className="ac-utility-heading">
							<span>{_('Engines')}</span>
							<Activity />
						</div>
						<div className="ac-service-row">
							<span>
								<span
									className={
										'ac-dot ' +
										(services.upnp && services.upnp.running
											? 'ac-dot-positive'
											: 'ac-dot-neutral')
									}
								/>
								{_('UPnP discovery')}
							</span>
							<strong>
								{presentation.serviceLabel(services.upnp)}
							</strong>
						</div>
						<div className="ac-service-row">
							<span>
								<span
									className={
										'ac-dot ' +
										(services.cast && services.cast.running
											? 'ac-dot-positive'
											: 'ac-dot-neutral')
									}
								/>
								{_('Chromecast discovery')}
							</span>
							<strong>
								{presentation.serviceLabel(services.cast)}
							</strong>
						</div>
						<div className="ac-utility-actions">
							<Button
								size="sm"
								type="button"
								disabled={busy || conflicts.length > 0}
								onClick={() => onAction('start')}
							>
								<Play />
								{_('Start')}
							</Button>
							<Button
								size="sm"
								variant="outline"
								type="button"
								disabled={busy}
								onClick={() => onAction('restart')}
							>
								<RefreshCw />
								{_('Restart')}
							</Button>
						</div>
						{conflicts.length ? (
							<Alert tone="warning">
								<strong>
									{_('Another AirConnect instance was detected.')}
								</strong>
								<p>{conflicts.join('\n')}</p>
							</Alert>
						) : null}
					</section>

					<section className="ac-drawer-section">
						<div className="ac-utility-heading">
							<span>{_('Signal report')}</span>
							<Signal />
						</div>
						<div className="ac-signal-card">
							<div>
								<span>{_('AirPlay broadcast')}</span>
								<strong>
									{presentation.broadcastText(
										services.upnp && services.upnp.broadcasting,
										broadcast.observed_at,
										broadcast.error
									)}
								</strong>
							</div>
							<span
								className={
									'ac-dot ' +
									(services.upnp && services.upnp.broadcasting === true
										? 'ac-dot-positive'
										: services.upnp && services.upnp.broadcasting === false
											? 'ac-dot-neutral'
											: 'ac-dot-unknown')
								}
							/>
						</div>
						<div className="ac-signal-card">
							<div>
								<span>{_('Playback')}</span>
								<strong>
									{presentation.playbackText({ playback })}
								</strong>
							</div>
							<span className="ac-dot ac-dot-unknown" />
						</div>
						{broadcast.observed_at ? (
							<small className="ac-observed-time">
								<Clock3 />
								{_('Observed')} {presentation.time(broadcast.observed_at)}
							</small>
						) : null}
					</section>

					<section className="ac-drawer-section">
						<div className="ac-utility-heading">
							<span>{_('Recent logs')}</span>
							<Button
								variant="ghost"
								size="icon"
								type="button"
								className="ac-icon-button"
								disabled={busy}
								onClick={onLoadLogs}
								title={_('Load recent logs')}
								aria-label={_('Load recent logs')}
							>
								<RefreshCw />
							</Button>
						</div>
						<pre className="ac-log-output">
							{logs
								? logs.lines.length
									? logs.lines.slice(-12).join('\n')
									: _('No log entries.')
								: _('Logs appear here when requested.')}
						</pre>
					</section>
				</div>
			</DrawerContent>
		</Drawer>
	);
}
