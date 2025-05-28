import clsx from "clsx";
import type React from "react";

interface TextLinkProps {
	href: string;
	children: React.ReactNode;
	className?: string;
}

export default function TextLink({ href, children, className }: TextLinkProps) {
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
