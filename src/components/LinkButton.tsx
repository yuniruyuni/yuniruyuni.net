import type React from "react";

interface LinkButtonProps {
	href: string;
	children: React.ReactNode;
	className?: string;
	baseClassName?: string;
}

export default function LinkButton({
	href,
	children,
	className = "",
	baseClassName = "block w-full md:w-auto bg-blue-400 hover:bg-blue-500 text-white font-bold py-2 px-4 rounded-full transition duration-300 ease-in-out",
}: LinkButtonProps) {
	return (
		<a href={href} className={`${baseClassName} ${className}`}>
			{children}
		</a>
	);
}
