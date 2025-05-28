import clsx from "clsx";
import type React from "react";

interface LinkGroupProps {
	children: React.ReactNode;
	className?: string;
}

interface ItemProps {
	href: string;
	text: string;
	label?: string;
	position: "first" | "middle" | "last";
	className?: string;
}

const positionStyles = {
	first: "w-full rounded-l-full border-r border-dotted border-white",
	middle: "relative w-fill border-r border-dotted border-white",
	last: "relative flex-1 rounded-r-full",
};

function Item({
	href,
	text,
	label,
	position,
	className = "bg-blue-400 hover:bg-blue-500 text-white font-bold py-2 px-4 transition duration-300 ease-in-out",
}: ItemProps) {
	return (
		<a href={href} className={clsx(className, positionStyles[position])}>
			{label && <span className="absolute top-0 left-1 text-xs">{label}</span>}
			<span className={clsx(label && "text-sm")}>{text}</span>
		</a>
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
