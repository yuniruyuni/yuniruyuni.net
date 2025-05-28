import clsx from "clsx";
import type React from "react";

interface SectionHeaderProps {
	title: string;
	className?: string;
}

export default function SectionHeader({
	title,
	className,
}: SectionHeaderProps) {
	return (
		<header className="text-center mb-8">
			<h2 className={clsx("text-2xl font-bold text-gray-600 mb-2", className)}>
				{title}
			</h2>
		</header>
	);
}
