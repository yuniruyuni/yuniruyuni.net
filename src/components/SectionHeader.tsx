import clsx from "clsx";

interface SectionHeaderProps {
	title: string;
	id?: string;
	className?: string;
}

export default function SectionHeader({
	title,
	id,
	className,
}: SectionHeaderProps) {
	return (
		<header className="text-center mb-8">
			<h2
				id={id}
				className={clsx("text-2xl font-bold text-gray-600 mb-2", className)}
			>
				{title}
			</h2>
		</header>
	);
}
