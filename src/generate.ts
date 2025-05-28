import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import App from "./components/App";

function generateHTML() {
	const html = renderToStaticMarkup(React.createElement(App));

	const fullHTML = `<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta property="og:url" content="https://yuniruyuni.net/" />
    <meta property="og:type" content="website" />
    <meta property="og:title" content="yuniruyuni.net" />
    <meta property="og:description" content="Virtual TechLead ゆにるユニのウェブサイトです。簡単なプロフィールや、各種配信サイトへのリンク、配信で使うお洋服リストなどのコンテンツを配信しています。" />
    <meta property="og:site_name" content="yuniruyuni.net" />
    <meta property="og:image" content="https://yuniruyuni.net/ogp.webp" />
    <meta property="twitter:card" content="summary_large_image" />
    <meta property="twitter:site" content="@yuniruyuni" />
    <link rel="stylesheet" href="index.css" />
    <title>yuniruyuni.net</title>
    <script>
        const timer = setTimeout(() => {
            const target = document.querySelector("#content");
            const top = target.getBoundingClientRect().top;
            console.log(top);
            window.scrollTo({ top: top, behavior: "smooth" });
            console.log("Scroll to content");
        }, 1000);

        window.addEventListener("scroll", () => {
            clearTimeout(timer);
        });
    </script>
</head>
<body>${html}</body>
</html>`;

	return fullHTML;
}

async function build() {
	try {
		// Create dist directory
		await Bun.write("dist/.gitkeep", "");

		// Generate HTML
		const html = generateHTML();
		await Bun.write("dist/index.html", html);

		console.log("Static HTML generated successfully!");
	} catch (error) {
		console.error("Error generating static HTML:", error);
		process.exit(1);
	}
}

build();
