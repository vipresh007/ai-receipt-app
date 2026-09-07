/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  output: "standalone",
  eslint: {
    dirs: ["app", "components", "lib"],
  },
};

export default nextConfig;
