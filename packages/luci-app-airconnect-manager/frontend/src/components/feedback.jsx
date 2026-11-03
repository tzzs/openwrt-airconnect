import { Check, X, AlertTriangle, CircleAlert, Loader2 } from 'lucide-react';

import { cn } from '../lib/utils.js';
import { Badge } from './ui/badge.jsx';

/** A small status chip used across the device cards and the summary. */
export function StatusBadge({ tone = 'neutral', children }) {
	const variant =
		tone === 'positive' ? 'success' : tone === 'warning' ? 'warning' : tone === 'destructive' ? 'destructive' : 'secondary';
	return <Badge variant={variant}>{children}</Badge>;
}

/** Inline spinner/text shown while a long action (scan, service call) is running. */
export function Pending({ label }) {
	return (
		<span className="inline-flex items-center gap-1.5 text-sm text-muted-foreground">
			<Loader2 className="size-3.5 animate-spin" />
			{label}
		</span>
	);
}

/** A warning banner identical in spirit to the old `.ac-alert.ac-warning`. */
export function Alert({ tone = 'warning', children, className }) {
	const palette =
		tone === 'destructive'
			? 'border-destructive/40 bg-destructive/10 text-destructive'
			: 'border-warning/40 bg-warning/10 text-warning';
	return (
		<div
			role={tone === 'destructive' ? 'alert' : 'status'}
			hidden={false}
			className={cn('rounded-md border p-3 text-sm', palette, className)}
		>
			<div className="flex items-start gap-2">
				{/* A filled-looking circle-alert for errors, the triangular warning
				    sign for warnings: the two tones must be distinguishable at a
				    glance, not just by colour. */}
				{tone === 'destructive' ? (
					<CircleAlert className="mt-0.5 size-4 shrink-0" />
				) : (
					<AlertTriangle className="mt-0.5 size-4 shrink-0" />
				)}
				<div className="whitespace-pre-wrap">{children}</div>
			</div>
		</div>
	);
}

export function OkIcon() {
	return <Check className="size-4 text-success" />;
}

export function NoIcon() {
	return <X className="size-4 text-muted-foreground" />;
}
