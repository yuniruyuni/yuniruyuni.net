import clsx from "clsx";
import type React from "react";
import BaseButton from "./BaseButton";

interface LinkGroupProps {
	children: React.ReactNode;
	className?: string;
}

interface ItemProps {
	href: string;
	text: string;
	label?: string;
	position: "first" | "middle" | "last";
	variant?: "primary" | "purple" | "pink" | "pink-light" | "slate" | "green";
	className?: string;
}

const positionStyles = {
	first: "w-full border-r border-dotted border-white",
	middle: "relative w-fill border-r border-dotted border-white",
	last: "relative flex-1",
};

const positionRounding = {
	first: "l" as const,
	middle: "none" as const,
	last: "r" as const,
};

function Item({
	href,
	text,
	label,
	position,
	variant = "primary",
	className,
}: ItemProps) {
	return (
		<BaseButton
			href={href}
			variant={variant}
			rounded={positionRounding[position]}
			className={clsx(positionStyles[position], className)}
		>
			{label && <span className="absolute top-0 left-1 text-xs">{label}</span>}
			<span className={clsx(label && "text-sm")}>{text}</span>
		</BaseButton>
	);
}

function LinkGroup({ children, className }: LinkGroupProps) {
	return (
		<div className={clsx("w-full md:w-auto flex flex-row", className)}>
			{children}
		</div>
	);
}

LinkGroup.Item = Item;

export default LinkGroup;
