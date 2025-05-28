import React from "react";

const Position = {
	FIRST: "first",
	MIDDLE: "middle",
	LAST: "last",
} as const;

type PositionType = (typeof Position)[keyof typeof Position];

interface PositionStyles {
	width: string; // Controls flex width/sizing
	rounding: string; // Border radius for left/right edges
	border: string; // Right border for partitions
}

const positionStyles: Record<PositionType, PositionStyles> = {
	[Position.FIRST]: {
		width: "w-full",
		rounding: "rounded-l-full",
		border: "border-r border-dotted border-white",
	},
	[Position.MIDDLE]: {
		width: "relative w-fill",
		rounding: "",
		border: "border-r border-dotted border-white",
	},
	[Position.LAST]: {
		width: "relative flex-1",
		rounding: "rounded-r-full",
		border: "",
	},
};

function getPosition(index: number, totalLength: number): PositionType {
	if (index === 0) {
		return Position.FIRST;
	}

	if (index === totalLength - 1) {
		return Position.LAST;
	}

	return Position.MIDDLE;
}

interface LinkItem {
	href: string;
	text: string;
	label?: string;
}

interface LinkGroupProps {
	links: LinkItem[];
	containerClassName?: string;
	baseClassName?: string;
}

export default function LinkGroup({
	links,
	containerClassName = "w-full md:w-auto flex flex-row",
	baseClassName = "bg-blue-400 hover:bg-blue-500 text-white font-bold py-2 px-4 transition duration-300 ease-in-out",
}: LinkGroupProps) {
	return (
		<div className={containerClassName}>
			{links.map((link, index) => {
				const position = getPosition(index, links.length);
				const styles = positionStyles[position];

				return (
					<a
						key={link.text}
						href={link.href}
						className={`${baseClassName} ${styles.width} ${styles.rounding} ${styles.border}`}
					>
						<>
							{link.label && (
								<span className="absolute top-0 left-1 text-xs">
									{link.label}
								</span>
							)}
							<span className={link.label ? "text-sm" : ""}>{link.text}</span>
						</>
					</a>
				);
			})}
		</div>
	);
}
