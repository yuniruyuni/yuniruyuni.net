import React from "react";
import FanArtGuidelines from "./FanArtGuidelines";
import HeroSection from "./HeroSection";
import ProfileSection from "./ProfileSection";

export default function App() {
	return (
		<div className="min-h-screen">
			<HeroSection />

			<div id="content" className="container mx-auto px-4">
				<ProfileSection />
				<FanArtGuidelines />
			</div>
		</div>
	);
}
