import * as React from 'react';

import { cn } from '../../lib/utils.js';

const Card = React.forwardRef(function Card({ className, ...props }, ref) {
	return (
		<div
			ref={ref}
			className={cn('rounded-xl border border-border bg-card text-card-foreground shadow-sm', className)}
			{...props}
		/>
	);
});

const CardHeader = React.forwardRef(function CardHeader({ className, ...props }, ref) {
	return <div ref={ref} className={cn('flex flex-col gap-1.5 p-5', className)} {...props} />;
});

const CardTitle = React.forwardRef(function CardTitle({ className, ...props }, ref) {
	return <h3 ref={ref} className={cn('text-base font-semibold leading-tight', className)} {...props} />;
});

const CardDescription = React.forwardRef(function CardDescription({ className, ...props }, ref) {
	return <p ref={ref} className={cn('text-sm text-muted-foreground', className)} {...props} />;
});

const CardContent = React.forwardRef(function CardContent({ className, ...props }, ref) {
	return <div ref={ref} className={cn('p-5 pt-0', className)} {...props} />;
});

const CardFooter = React.forwardRef(function CardFooter({ className, ...props }, ref) {
	return <div ref={ref} className={cn('flex items-center gap-2 p-5 pt-0', className)} {...props} />;
});

export { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter };
