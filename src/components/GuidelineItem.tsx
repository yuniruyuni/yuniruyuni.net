import clsx from "clsx";
import type { ReactNode } from "react";

interface GuidelineItemProps {
	children: ReactNode;
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
