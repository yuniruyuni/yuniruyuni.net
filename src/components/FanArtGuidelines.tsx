import GuidelineItem from "./GuidelineItem";
import GuidelineList from "./GuidelineList";
import SectionHeader from "./SectionHeader";
import TextLink from "./TextLink";

export default function FanArtGuidelines() {
	return (
		<section
			className="bg-white bg-opacity-90 rounded-xl shadow-2xl p-8 max-w-4xl mx-auto my-16"
			aria-labelledby="guidelines-heading"
		>
			<SectionHeader
				id="guidelines-heading"
				title="📚二次創作・ファンアートについて"
			/>
			<GuidelineList>
				<GuidelineItem>
					私のアバターはHoneycrisp様の
					<TextLink href="https://booth.pm/ja/items/2198694">
						ユキちゃん
					</TextLink>
					です。
				</GuidelineItem>

				<GuidelineItem>
					そのため私は一次創作者ではないのです…
					<span className="font-bold">が、</span>
				</GuidelineItem>

				<GuidelineItem>
					Honeycrisp様に私(ゆにるユニ)の二次創作を誰でもやってよいという許可をいただいています✨
				</GuidelineItem>

				<GuidelineItem bold>
					そのためイラスト化やマンガ化といった二次創作、大歓迎です！
				</GuidelineItem>

				<GuidelineItem>
					ただし他のユキちゃんとの区別として髪の色を水色にするか、胸元に時計を持たせてください。
				</GuidelineItem>

				<GuidelineItem>
					またR18指定が必要なものについては、NSFW表示など未成年の視聴者への配慮を各々でお願いいたします。
				</GuidelineItem>

				<GuidelineItem>
					宜しければ配信のサムネイルや
					SNS投稿に使用する可能性があることを了承の上{" "}
					<TextLink href="https://x.com/hashtag/yunigraphics">
						#yunigraphics
					</TextLink>{" "}
					のタグ付きで投稿していただけると嬉しいです。
				</GuidelineItem>

				<GuidelineItem bold>
					この件については、ご迷惑になるのでHoneycrisp様に問い合わせるのはやめてください。
				</GuidelineItem>
			</GuidelineList>
		</section>
	);
}
