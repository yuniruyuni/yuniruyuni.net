import RelatedLinks from "./RelatedLinks";

export default function ProfileSection() {
	return (
		<section
			className="bg-white bg-opacity-90 rounded-xl shadow-2xl p-8 max-w-4xl mx-auto"
			aria-labelledby="profile-heading"
		>
			<header className="text-center mb-8">
				<h2
					id="profile-heading"
					className="text-4xl font-bold text-purple-800 mb-2"
				>
					ゆにるユニ
				</h2>
				<p className="text-xl text-gray-600">
					2222年からやってきた未来のVirtual TechLead
				</p>
				<p className="text-xl text-gray-600">
					ところが実際には遊んでばかり！？
				</p>
			</header>

			<div className="flex flex-col md:flex-row items-center justify-between">
				<div className="md:w-1/2 mb-8 md:mb-0">
					<img
						src="stand.webp"
						alt="ゆにるユニの立ち絵イラスト - 水色の髪とカジュアルな服装での立ちポーズ"
						className="rounded-lg mx-auto"
					/>
				</div>
				<div className="md:w-1/2 text-center md:text-left">
					<p className="text-lg text-gray-700 mb-2">
						IT技術のお話やプログラミングの配信を中心に、ゲーム遊んだり歌やピアノなどのやったことのない新しいスキルを身に着ける挑戦をしてみたり、色々と活動しています✨
					</p>
					<p className="text-lg text-gray-700 mb-2">
						個人勢のVStreamerです🌟2022.2.4 Debut✨
					</p>
					<RelatedLinks />
				</div>
			</div>
		</section>
	);
}
