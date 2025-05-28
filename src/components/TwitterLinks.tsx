import type React from "react";
import LinkGroup from "./LinkGroup";

export default function TwitterLinks() {
	return (
		<LinkGroup aria-label="Twitter関連リンク">
			<LinkGroup.Item
				position="first"
				href="https://twitter.com/yuniruyuni"
				text="Twitter(X)"
			/>
			<LinkGroup.Item
				position="middle"
				href="https://twitter.com/hashtag/yunicode"
				label="Tag"
				text="#yunicode"
			/>
			<LinkGroup.Item
				position="last"
				href="https://twitter.com/hashtag/yunigraphics"
				label="FanArt"
				text="#yunigraphics"
			/>
		</LinkGroup>
	);
}
