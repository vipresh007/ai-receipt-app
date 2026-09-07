// Copies the canonical design tokens CSS into the app so Next can bundle it.
// Runs on predev / prebuild. app/tokens.css is git-ignored (generated).
import { copyFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const src = resolve(here, "../../design/tokens.css");
const dest = resolve(here, "../app/tokens.css");

mkdirSync(dirname(dest), { recursive: true });
copyFileSync(src, dest);
console.log(`synced ${src} -> ${dest}`);
