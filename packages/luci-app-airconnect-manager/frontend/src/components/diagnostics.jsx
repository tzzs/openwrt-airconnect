import {
	Card,
	CardContent,
	CardDescription,
	CardHeader,
	CardTitle
} from './ui/card.jsx';
import { Button } from './ui/button.jsx';
import { Alert, StatusBadge } from './feedback.jsx';

/**
 * The Diagnostics tab.
 *
 * The four facts it reports - the service process, discovery, the AirPlay
 * broadcast measurement and playback - each come from their own source and are
 * rendered on their own row. Every string comes from lib/presentation.js, so a
 * component cannot accidentally turn "not measured" into a positive.
 */
export function DiagnosticsPanel({
	status,
	presentation,
	onAction,
	onLoadLogs,
	logs,
	setLogs,
	busy,
	t
}) {
	const _ = typeof t === 'function' ? t : function (s) { return s; };
	const data = status || {};
	const services = data.services || {};
	const conflicts = Array.isArray(data.conflicts) ? data.conflicts : [];
	const broadcast = data.broadcast || {};

	const serviceBadge = (service) => (
		<StatusBadge tone={presentation.serviceTone(service)}>
			{presentation.serviceLabel(service)}
		</StatusBadge>
	);

	const facts = [
		[_('Interface'), presentation.value(data.interface)],
		[_('Manager version'), presentation.value(data.version)],
		[_('AirPlay broadcast (UPnP)'),
			presentation.broadcastText(
				(services.upnp || {}).broadcasting, broadcast.observed_at, broadcast.error)],
		[_('AirPlay broadcast (Chromecast)'),
			presentation.broadcastText(
				(services.cast || {}).broadcasting, broadcast.observed_at, broadcast.error)],
		[_('Playback'), presentation.playbackText(data)]
	];

	return (
		<div className="space-y-6">
			<Card>
				<CardHeader>
					<CardTitle>{_('Service actions')}</CardTitle>
					<CardDescription>
						{_('Service actions use the last applied settings. Stopping or restarting briefly disconnects AirPlay.')}
					</CardDescription>
				</CardHeader>
				<CardContent className="flex flex-wrap gap-2">
					<Button
						disabled={busy || conflicts.length > 0}
						onClick={() => onAction('start')}
					>
						{_('Start service')}
					</Button>
					<Button variant="outline" disabled={busy} onClick={() => onAction('stop')}>
						{_('Stop service')}
					</Button>
					<Button variant="outline" disabled={busy} onClick={() => onAction('restart')}>
						{_('Restart service')}
					</Button>
				</CardContent>
			</Card>

			{conflicts.length > 0 ? (
				<Alert tone="warning">
					<strong>{_('Another AirConnect instance was detected.')}</strong>
					<div>{conflicts.join('\n')}</div>
					<p className="mt-1">{_('Stop the existing instance before starting these engines.')}</p>
				</Alert>
			) : null}

			<Card>
				<CardHeader>
					<CardTitle>{_('Diagnostics')}</CardTitle>
					<CardDescription>
						{_('Service running does not confirm AirPlay availability or playback.')}
					</CardDescription>
				</CardHeader>
				<CardContent>
					<div className="mb-4 flex flex-wrap gap-2">
						<StatusBadge tone={presentation.serviceTone(services.upnp)}>
							{_('UPnP')}: {presentation.serviceLabel(services.upnp)}
						</StatusBadge>
						<StatusBadge tone={presentation.serviceTone(services.cast)}>
							{_('Chromecast')}: {presentation.serviceLabel(services.cast)}
						</StatusBadge>
					</div>
					<dl className="grid grid-cols-1 gap-2 text-sm sm:grid-cols-2">
						{facts.map(([label, value]) => (
							<div key={label} className="flex flex-col gap-0.5">
								<dt className="text-xs font-medium text-muted-foreground">{label}</dt>
								<dd className="text-foreground">{value}</dd>
							</div>
						))}
					</dl>
				</CardContent>
			</Card>

			<Card>
				<CardHeader className="flex-row items-center justify-between space-y-0">
					<CardTitle>{_('Recent logs')}</CardTitle>
					<Button
						variant="outline"
						size="sm"
						disabled={busy}
						onClick={async () => {
							const result = await onLoadLogs();
							setLogs(result);
						}}
					>
						{_('Load recent logs')}
					</Button>
				</CardHeader>
				<CardContent>
					<pre
						className="max-h-72 overflow-auto rounded-md border border-border bg-muted/40 p-3 text-xs leading-relaxed"
						tabIndex={0}
						aria-label={_('Recent AirConnect logs')}
					>
						{logs == null
							? _('Logs are loaded only when requested.')
							: logs.lines.length
								? logs.lines.join('\n') +
									(logs.truncated ? '\n' + _('Older log lines were omitted.') : '')
								: _('No log entries.')}
					</pre>
				</CardContent>
			</Card>
		</div>
	);
}
