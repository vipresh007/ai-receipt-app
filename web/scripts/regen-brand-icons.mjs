// Regenerate every raster brand asset from design/logo/*.svg.
// Uses web's `sharp` devDependency — run from anywhere with: node web/scripts/regen-brand-icons.mjs
import { fileURLToPath } from "node:url";
import path from "node:path";
import sharp from "sharp";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const icon = path.join(root, "design/logo/tally-icon.svg");
const mark = path.join(root, "design/logo/tally-mark.svg");
const brand = (name) => path.join(root, "brand", name);
const assets = path.join(root, "ios/AIReceiptApp/Resources/Assets.xcassets");

// App Store icon: opaque, no alpha channel.
const appIcon = sharp(icon, { density: 384 }).resize(1024, 1024).flatten({ background: "#0C1412" }).removeAlpha().png();
await appIcon.clone().toFile(brand("tally-appicon-1024.png"));
await appIcon.clone().toFile(path.join(assets, "AppIcon.appiconset/icon-1024.png"));

await sharp(icon, { density: 384 }).resize(512, 512).png().toFile(brand("tally-icon-512.png"));
await sharp(icon, { density: 384 }).resize(512, 512).png().toFile(path.join(root, "web/public/tally-icon-512.png"));
await sharp(icon, { density: 192 }).resize(256, 256).png().toFile(brand("tally-icon-256.png"));
await sharp(mark, { density: 192 }).resize(512, 512).png().toFile(brand("tally-mark-512.png"));

// iOS launch-screen mark (on the ink LaunchBackground color), 160pt.
for (const [scale, suffix] of [[1, ""], [2, "@2x"], [3, "@3x"]]) {
  await sharp(mark, { density: 96 * scale })
    .resize(160 * scale, 160 * scale)
    .png()
    .toFile(path.join(assets, `LaunchMark.imageset/launch-mark${suffix}.png`));
}

console.log("Regenerated brand/, iOS AppIcon + LaunchMark, and web/public/tally-icon-512.png.");
