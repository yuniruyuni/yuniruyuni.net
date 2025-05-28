import clsx from "clsx";
import type React from "react";

interface LinkButtonProps {
	href: string;
	children: React.ReactNode;
	className?: string;
}

export default function LinkButton({
	href,
	children,
	className,
}: LinkButtonProps) {
	return (
		<a
			href={href}
			className={clsx(
				"block w-full md:w-auto font-bold py-2 px-4 rounded-full transition duration-300 ease-in-out",
				"bg-blue-400 hover:bg-blue-500 text-white",
				className,
			)}
		>
			{children}
		</a>
	);
}
