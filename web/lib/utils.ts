import { type ClassValue, clsx } from "clsx";
import { extendTailwindMerge } from "tailwind-merge";

// design/tailwind-preset.js adds color and font-size keys tailwind-merge has
// never heard of. Without telling it about them, it lumps every unrecognized
// `text-*` utility into one conflict group — so `cn("text-accent-fg",
// "text-body")` silently drops `text-accent-fg`, because tailwind-merge
// thinks a font-size class and a text-color class are the same kind of
// thing and keeps only the last one. (This is exactly what made the landing
// page's primary button render with no text color at all.) Teaching it the
// real groups here means a size class can never evict a color class again,
// anywhere in the app — not just at today's call sites.
const FONT_SIZES = ["display", "title", "headline", "body", "callout", "subhead", "caption", "micro"];
const COLOR_TOKENS = [
  "bg",
  "surface",
  "surface-2",
  "surface-sunken",
  "border",
  "border-strong",
  "text",
  "text-secondary",
  "text-tertiary",
  "text-inverse",
  "accent",
  "accent-hover",
  "accent-fg",
  "accent-muted",
  "gold",
  "hero-text",
  "hero-chip",
  "hero-cta",
  "hero-cta-hover",
  "success",
  "success-muted",
  "warning",
  "warning-muted",
  "danger",
  "danger-muted",
  "info",
  "info-muted",
  "category-groceries",
  "category-restaurants",
  "category-transport",
  "category-shopping",
  "category-entertainment",
  "category-health",
  "category-utilities",
  "category-travel",
  "category-other",
];

const customTwMerge = extendTailwindMerge({
  extend: {
    classGroups: {
      "font-size": FONT_SIZES.map((s) => `text-${s}`),
      "text-color": COLOR_TOKENS.map((c) => `text-${c}`),
      "bg-color": COLOR_TOKENS.map((c) => `bg-${c}`),
      "border-color": COLOR_TOKENS.map((c) => `border-${c}`),
      shadow: ["shadow-e1", "shadow-e2"],
    },
  },
});

export function cn(...inputs: ClassValue[]) {
  return customTwMerge(clsx(inputs));
}
