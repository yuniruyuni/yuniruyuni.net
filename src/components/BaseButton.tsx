import clsx from "clsx";
import type React from "react";

interface BaseButtonProps {
	href: string;
	children: React.ReactNode;
	variant?: "primary" | "purple" | "pink" | "pink-light" | "slate" | "green";
	rounded?: "full" | "l" | "r" | "none";
	className?: string;
}

const colorVariants = {
	primary: "bg-blue-400 hover:bg-blue-500",
	purple: "bg-purple-600 hover:bg-purple-700",
	pink: "bg-pink-500 hover:bg-pink-600",
	"pink-light": "bg-pink-300 hover:bg-pink-200",
	slate: "bg-slate-400 hover:bg-slate-500",
	green: "bg-green-400 hover:bg-green-500",
};

const roundingVariants = {
	full: "rounded-full",
	l: "rounded-l-full",
	r: "rounded-r-full",
	none: "",
};

export default function BaseButton({
	href,
	children,
	variant = "primary",
	rounded = "full",
	className,
}: BaseButtonProps) {
	const isExternal = href.startsWith("http");

	return (
		<a
			href={href}
			className={clsx(
				// Base button styles
				"font-bold py-2 px-4 transition duration-300 ease-in-out text-white",
				"block w-full md:w-auto",
				// Color variant
				colorVariants[variant],
				// Rounding variant
				roundingVariants[rounded],
				// Custom overrides
				className,
			)}
			{...(isExternal && {
				target: "_blank",
				rel: "noopener noreferrer",
			})}
		>
			{children}
		</a>
	);
}
