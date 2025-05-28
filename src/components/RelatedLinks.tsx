import type React from "react";
import LinkButton from "./LinkButton";
import TwitterLinks from "./TwitterLinks";

export default function RelatedLinks() {
	return (
		<nav className="space-y-4" aria-label="関連リンク">
			<LinkButton href="https://twitch.tv/yuniruyuni" variant="purple">
				Twitch Channel (Main streaming)
			</LinkButton>

			<LinkButton href="https://youtube.com/@yuniruyuni" variant="pink">
				Youtube Channel
			</LinkButton>

			<TwitterLinks />

			<LinkButton href="https://github.com/yuniruyuni" variant="slate">
				Github
			</LinkButton>

			<LinkButton href="https://costume.yuniruyuni.net/" variant="green">
				お着替えリスト
			</LinkButton>

			<LinkButton
				href="https://hari-stream.com/ja/mypage/USER205ST1334/"
				variant="pink-light"
				className="border"
			>
				HARI(おたより/質問箱)
			</LinkButton>
		</nav>
	);
}
