export default function (eleventyConfig) {
	eleventyConfig.addPassthroughCopy("src/assets");
	eleventyConfig.addPassthroughCopy("src/preview.sh");

	return {
		dir: {
			input: "src",
			output: "_site",
			includes: "_includes",
			layouts: "_includes/layouts",
		},
		templateFormats: ["njk", "html", "md"],
		htmlTemplateEngine: "njk",
	};
}
