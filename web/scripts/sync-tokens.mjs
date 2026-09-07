// Copies the canonical design tokens CSS into the app so Next can bundle it.
// Runs on predev / prebuild. app/tokens.css is git-ignored (generated).
//
// If design/tokens.css isn't reachable (e.g. a Docker build whose context is
// only web/), keep any tokens.css that's already there instead of failing.
import { copyFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const dest = resolve(here, "../app/tokens.css");
const candidates = [
  resolve(here, "../../design/tokens.css"), // monorepo checkout
  "/design/tokens.css", // Docker: COPY design/ /design/
];

const src = candidates.find(existsSync);

if (!src) {
  if (existsSync(dest)) {
    console.log(`sync-tokens: no source found, keeping existing ${dest}`);
    process.exit(0);
  }
  console.error("sync-tokens: design/tokens.css not found and no existing app/tokens.css");
  process.exit(1);
}

mkdirSync(dirname(dest), { recursive: true });
copyFileSync(src, dest);
console.log(`synced ${src} -> ${dest}`);
