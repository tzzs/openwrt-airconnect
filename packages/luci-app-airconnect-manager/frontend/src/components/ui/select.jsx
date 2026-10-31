import * as React from 'react';
import * as SelectPrimitive from '@radix-ui/react-select';
import { Check, ChevronDown } from 'lucide-react';

import { cn } from '../../lib/utils.js';

const Select = SelectPrimitive.Root;
const SelectGroup = SelectPrimitive.Group;
const SelectValue = SelectPrimitive.Value;

const SelectTrigger = React.forwardRef(function SelectTrigger(
	{ className, children, ...props },
	ref
) {
	return (
		<SelectPrimitive.Trigger
			className={cn(
				'flex h-9 w-full items-center justify-between gap-2 rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm',
				'placeholder:text-muted-foreground disabled:cursor-not-allowed disabled:opacity-50',
				'[&>span]:line-clamp-1',
				className
			)}
			ref={ref}
			{...props}
		>
			{children}
			<SelectPrimitive.Icon asChild>
				<ChevronDown className="size-4 shrink-0 opacity-50" />
			</SelectPrimitive.Icon>
		</SelectPrimitive.Trigger>
	);
});

const SelectContent = React.forwardRef(function SelectContent(
	{ className, children, position = 'popper', ...props },
	ref
) {
	return (
		<SelectPrimitive.Portal>
			<SelectPrimitive.Content
				className={cn(
					'relative z-50 max-h-96 min-w-[8rem] overflow-hidden rounded-md border border-border bg-popover text-popover-foreground shadow-md',
					position === 'popper' && 'data-[side=bottom]:translate-y-1 data-[side=top]:-translate-y-1',
					className
				)}
				position={position}
				ref={ref}
				{...props}
			>
				<SelectPrimitive.Viewport
					className={cn(
						'p-1',
						position === 'popper' && 'h-[var(--radix-select-trigger-height)] w-full min-w-[var(--radix-select-trigger-width)]'
					)}
				>
					{children}
				</SelectPrimitive.Viewport>
			</SelectPrimitive.Content>
		</SelectPrimitive.Portal>
	);
});

const SelectItem = React.forwardRef(function SelectItem({ className, children, ...props }, ref) {
	return (
		<SelectPrimitive.Item
			className={cn(
				'relative flex w-full cursor-default select-none items-center rounded-sm py-1.5 pl-8 pr-2 text-sm outline-none',
				'focus:bg-accent focus:text-accent-foreground data-[disabled]:pointer-events-none data-[disabled]:opacity-50',
				className
			)}
			ref={ref}
			{...props}
		>
			<span className="absolute left-2 flex size-3.5 items-center justify-center">
				<SelectPrimitive.ItemIndicator>
					<Check className="size-4" />
				</SelectPrimitive.ItemIndicator>
			</span>
			<SelectPrimitive.ItemText>{children}</SelectPrimitive.ItemText>
		</SelectPrimitive.Item>
	);
});

const SelectLabel = React.forwardRef(function SelectLabel({ className, ...props }, ref) {
	return (
		<SelectPrimitive.Label
			className={cn('px-2 py-1.5 text-sm font-semibold', className)}
			ref={ref}
			{...props}
		/>
	);
});

export { Select, SelectGroup, SelectValue, SelectTrigger, SelectContent, SelectItem, SelectLabel };
