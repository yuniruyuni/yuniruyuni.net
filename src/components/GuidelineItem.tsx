import clsx from "clsx";
import type React from "react";

interface GuidelineItemProps {
	children: React.ReactNode;
	bold?: boolean;
	className?: string;
}

export default function GuidelineItem({
	children,
	bold = false,
	className,
}: GuidelineItemProps) {
	return (
		<li className={clsx("text-gray-600", bold && "font-bold", className)}>
			{children}
		</li>
	);
}
