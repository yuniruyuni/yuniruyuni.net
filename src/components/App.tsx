import FanArtGuidelines from "./FanArtGuidelines";
import HeroSection from "./HeroSection";
import ProfileSection from "./ProfileSection";
import StreamingProducts from "./StreamingProducts";

export default function App() {
	return (
		<div className="min-h-screen">
			<HeroSection />

			<main id="content" className="container mx-auto px-4">
				<ProfileSection />
				<StreamingProducts />
				<FanArtGuidelines />
			</main>
		</div>
	);
}
