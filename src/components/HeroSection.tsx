import type React from "react";

export default function HeroSection() {
	return (
		<div className="h-screen flex justify-center items-center">
			<img
				className="-z-10 fixed w-full h-screen top-0 left-0 object-cover lg:object-scale-down object-top"
				src="top.webp"
				alt="ゆにるユニのキャラクターイラスト - 2222年からやってきた未来のバーチャルテックリード、水色の髪が特徴"
			/>
			<h1 className="relative text-white text-center">yuniruyuni.net</h1>
		</div>
	);
}
