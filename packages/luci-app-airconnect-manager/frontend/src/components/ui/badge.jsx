import * as React from 'react';
import { cva } from 'class-variance-authority';

import { cn } from '../../lib/utils.js';

const badgeVariants = cva(
	'inline-flex items-center rounded-md border px-2 py-0.5 text-xs font-medium whitespace-nowrap',
	{
		variants: {
			variant: {
				default: 'border-transparent bg-primary text-primary-foreground',
				secondary: 'border-transparent bg-secondary text-secondary-foreground',
				outline: 'border-border text-foreground',
				success: 'border-transparent bg-success/10 text-success',
				warning: 'border-transparent bg-warning/10 text-warning',
				destructive: 'border-transparent bg-destructive/10 text-destructive'
			}
		},
		defaultVariants: {
			variant: 'default'
		}
	}
);

function Badge({ className, variant, ...props }) {
	return <span className={cn(badgeVariants({ variant }), className)} {...props} />;
}

export { Badge, badgeVariants };
