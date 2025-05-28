import clsx from "clsx";
import type React from "react";

interface LinkProps {
	href: string;
	children: React.ReactNode;
	className?: string;
}

export default function Link({ href, children, className }: LinkProps) {
	return (
		<a
			href={href}
			className={clsx(
				"font-medium text-blue-600 underline hover:no-underline",
				"dark:text-blue-500",
				className,
			)}
		>
			{children}
		</a>
	);
}
