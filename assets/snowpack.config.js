// Snowpack Configuration File
// See all supported options: https://www.snowpack.dev/#configuration

/** @type {import("snowpack").SnowpackUserConfig } */
module.exports = {
    mount: {
	"static": {url: "/", static: true, resolve: false},
	"css": "/css",
	"js": "/js"
    },
    plugins: [
	"@snowpack/plugin-postcss"
    ],
    // installOptions: {},
    // devOptions: {},
    buildOptions: {
        out: "../priv/static"
    },
};
