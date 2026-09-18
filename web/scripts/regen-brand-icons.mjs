// Regenerate the PNG exports in brand/ from design/logo/tally-icon.svg.
// Uses web's `sharp` devDependency — run from anywhere with: node web/scripts/regen-brand-icons.mjs
import { fileURLToPath } from "node:url";
import path from "node:path";
import sharp from "sharp";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const svg = path.join(root, "design/logo/tally-icon.svg");
const brand = (name) => path.join(root, "brand", name);

// App Store icon: opaque, no alpha channel.
await sharp(svg, { density: 384 })
  .resize(1024, 1024)
  .flatten({ background: "#0E6E58" })
  .removeAlpha()
  .png()
  .toFile(brand("tally-appicon-1024.png"));

await sharp(svg, { density: 384 }).resize(512, 512).png().toFile(brand("tally-icon-512.png"));
await sharp(svg, { density: 192 }).resize(256, 256).png().toFile(brand("tally-icon-256.png"));

console.log("Regenerated brand/tally-appicon-1024.png, tally-icon-512.png, tally-icon-256.png");
console.log("Remember to also copy tally-appicon-1024.png -> ios/.../AppIcon.appiconset/icon-1024.png");
console.log("and tally-icon-512.png -> web/public/tally-icon-512.png (Auth0 branding).");
