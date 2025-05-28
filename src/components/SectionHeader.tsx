import type React from "react";

interface SectionHeaderProps {
	title: string;
	className?: string;
}

export default function SectionHeader({
	title,
	className = "text-2xl font-bold text-gray-600 mb-2",
}: SectionHeaderProps) {
	return (
		<header className="text-center mb-8">
			<h2 className={className}>{title}</h2>
		</header>
	);
}
