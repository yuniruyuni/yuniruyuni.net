import type React from "react";

interface LinkProps {
	href: string;
	children: React.ReactNode;
	className?: string;
}

export default function Link({
	href,
	children,
	className = "font-medium text-blue-600 underline dark:text-blue-500 hover:no-underline",
}: LinkProps) {
	return (
		<a href={href} className={className}>
			{children}
		</a>
	);
}
