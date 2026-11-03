import * as React from 'react';
import * as TabsPrimitive from '@radix-ui/react-tabs';

import { cn } from '../../lib/utils.js';

const Tabs = TabsPrimitive.Root;

const TabsList = React.forwardRef(function TabsList({ className, ...props }, ref) {
	return (
		<TabsPrimitive.List
			ref={ref}
			className={cn(
				'inline-flex h-10 items-center justify-center rounded-lg bg-muted p-1 text-muted-foreground',
				className
			)}
			{...props}
		/>
	);
});

const TabsTrigger = React.forwardRef(function TabsTrigger({ className, ...props }, ref) {
	return (
		<TabsPrimitive.Trigger
			ref={ref}
			className={cn(
				'inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md px-3 py-1.5 text-sm font-medium transition-all',
				'data-[state=active]:bg-background data-[state=active]:text-foreground data-[state=active]:shadow-sm',
				className
			)}
			{...props}
		/>
	);
});

const TabsContent = React.forwardRef(function TabsContent({ className, ...props }, ref) {
	return <TabsPrimitive.Content ref={ref} className={cn('mt-5', className)} {...props} />;
});

export { Tabs, TabsList, TabsTrigger, TabsContent };
