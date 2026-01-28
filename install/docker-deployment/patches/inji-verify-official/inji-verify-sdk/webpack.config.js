const path = require("path");

module.exports = {
  mode: "production", // or 'development'
  entry: "./src/index.ts",
  output: {
    path: path.resolve(__dirname, "dist"),
    filename: "index.js",
    libraryTarget: "umd",
    library: "@mosip/react-inji-verify-sdk",
    umdNamedDefine: true,
  },
  resolve: {
    extensions: [".ts", ".tsx", ".js"],
    fallback: {
      // Node.js core modules - not needed in browser, use fallback implementations
      "https": false,
      "http": false,
      "url": false,
      "stream": false,
      "crypto": false,
      "buffer": false,
      "util": false,
      "path": false,
      "fs": false,
      "os": false,
      "assert": false,
      "zlib": false,
    },
  },
  module: {
    rules: [
      {
        test: /\.tsx?$/,
        use: "ts-loader",
        exclude: [/node_modules/, /__test__/],
      },
      {
        test: /\.css$/i,
        use: ["style-loader", "css-loader"],
      },
      {
        test: /\.svg$/i,
        issuer: /\.[jt]sx?$/,
        use: [
          {
            loader: "@svgr/webpack",
            options: {
              icon: true,
            },
          },
        ],
      },
    ],
  },
  externals: {
    react: "react",
    "react-dom": "ReactDOM",
  },
};
