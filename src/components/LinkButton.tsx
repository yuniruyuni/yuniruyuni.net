import type { ReactNode } from "react";
import BaseButton from "./BaseButton";

interface LinkButtonProps {
	href: string;
	children: ReactNode;
	variant?: "primary" | "purple" | "pink" | "pink-light" | "slate" | "green";
	className?: string;
}

export default function LinkButton({
	href,
	children,
	variant = "primary",
	className,
}: LinkButtonProps) {
	return (
		<BaseButton href={href} variant={variant} className={className}>
			{children}
		</BaseButton>
	);
}
