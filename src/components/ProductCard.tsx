interface ProductCardProps {
	title: string;
	description: string;
	url: string;
}

export default function ProductCard({
	title,
	description,
	url,
}: ProductCardProps) {
	return (
		<a
			href={url}
			target="_blank"
			rel="noopener noreferrer"
			className="block p-6 bg-purple-50 rounded-lg border-2 border-purple-200 hover:border-purple-400 hover:shadow-lg transition-all"
		>
			<h3 className="text-xl font-bold text-purple-800 mb-2">{title}</h3>
			<p className="text-gray-700 text-sm leading-relaxed">{description}</p>
		</a>
	);
}
