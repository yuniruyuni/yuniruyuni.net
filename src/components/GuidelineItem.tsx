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
	const baseClasses = "text-gray-600";
	const finalClasses =
		className || (bold ? `${baseClasses} font-bold` : baseClasses);

	return <li className={finalClasses}>{children}</li>;
}
