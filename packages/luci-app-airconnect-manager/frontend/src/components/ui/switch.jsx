import * as React from 'react';
import * as SwitchPrimitives from '@radix-ui/react-switch';

import { cn } from '../../lib/utils.js';

const Switch = React.forwardRef(function Switch({ className, ...props }, ref) {
	return (
		<SwitchPrimitives.Root
			className={cn(
				'peer inline-flex h-5 w-9 shrink-0 cursor-pointer items-center rounded-full border-2 border-transparent transition-colors',
				'data-[state=checked]:bg-primary data-[state=unchecked]:bg-input',
				'disabled:cursor-not-allowed disabled:opacity-50',
				className
			)}
			{...props}
			ref={ref}
		>
			<SwitchPrimitives.Thumb
				className={cn(
					'pointer-events-none block size-4 rounded-full bg-background shadow-lg ring-0 transition-transform',
					'data-[state=checked]:translate-x-4 data-[state=unchecked]:translate-x-0'
				)}
			/>
		</SwitchPrimitives.Root>
	);
});

export { Switch };
