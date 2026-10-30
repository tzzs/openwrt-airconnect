import * as React from 'react';
import * as DialogPrimitive from '@radix-ui/react-dialog';
import { X } from 'lucide-react';

import { cn } from '../../lib/utils.js';

/**
 * A right-hand side drawer, used for the service panel and the logs.
 *
 * The overview page has to stay narrow: the device list and the speaker's own
 * controls are what the page is for, and the service state is secondary. A
 * drawer keeps that secondary material one click away instead of spending a
 * permanent column on it, which is what pushed the old three-column layout
 * past the point where the middle column was usable.
 *
 * Radix's Dialog already handles the overlay, the focus trap, Escape and the
 * `aria-modal` wiring, so this only styles it.
 */
const Drawer = DialogPrimitive.Root;
const DrawerTrigger = DialogPrimitive.Trigger;
const DrawerClose = DialogPrimitive.Close;

const DrawerContent = React.forwardRef(function DrawerContent(
	{ className, children, ...props },
	ref
) {
	return (
		<DialogPrimitive.Portal>
			<DialogPrimitive.Overlay className="ac-drawer-overlay" />
			<DialogPrimitive.Content
				ref={ref}
				className={cn('ac-drawer-panel', className)}
				{...props}
			>
				{children}
				<DialogPrimitive.Close
					className="ac-drawer-close"
					aria-label="Close"
				>
					<X />
				</DialogPrimitive.Close>
			</DialogPrimitive.Content>
		</DialogPrimitive.Portal>
	);
});

function DrawerHeader({ title, description, children }) {
	return (
		<div className="ac-drawer-header">
			<div>
				<h2>{title}</h2>
				{description ? <p>{description}</p> : null}
			</div>
			{children}
		</div>
	);
}

export { Drawer, DrawerTrigger, DrawerClose, DrawerContent, DrawerHeader };
