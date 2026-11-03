import { clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

/**
 * Merge conditional class names, letting later Tailwind utilities win over
 * earlier ones with the same property. This is the shadcn convention; every
 * component here funnels its `className` prop through it so callers can
 * override any built-in utility.
 */
export function cn(...inputs) {
	return twMerge(clsx(inputs));
}
