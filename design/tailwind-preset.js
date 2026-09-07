/**
 * Tailwind preset for AI Receipt — maps Tailwind theme keys onto the CSS
 * custom properties in design/tokens.css. Import tokens.css globally, then:
 *
 *   // tailwind.config.ts
 *   import preset from "../design/tailwind-preset.js";
 *   export default { presets: [preset], content: [...] };
 *
 * Keep in sync with design/tokens.json.
 */
const preset = {
  theme: {
    extend: {
      colors: {
        bg: "var(--c-bg)",
        surface: {
          DEFAULT: "var(--c-surface)",
          2: "var(--c-surface-2)",
          sunken: "var(--c-surface-sunken)",
        },
        border: {
          DEFAULT: "var(--c-border)",
          strong: "var(--c-border-strong)",
        },
        text: {
          DEFAULT: "var(--c-text)",
          secondary: "var(--c-text-secondary)",
          tertiary: "var(--c-text-tertiary)",
          inverse: "var(--c-text-inverse)",
        },
        accent: {
          DEFAULT: "var(--c-accent)",
          hover: "var(--c-accent-hover)",
          fg: "var(--c-accent-fg)",
          muted: "var(--c-accent-muted)",
        },
        success: { DEFAULT: "var(--c-success)", muted: "var(--c-success-muted)" },
        warning: { DEFAULT: "var(--c-warning)", muted: "var(--c-warning-muted)" },
        danger: { DEFAULT: "var(--c-danger)", muted: "var(--c-danger-muted)" },
        info: { DEFAULT: "var(--c-info)", muted: "var(--c-info-muted)" },
        category: {
          groceries: "var(--cat-groceries)",
          restaurants: "var(--cat-restaurants)",
          transport: "var(--cat-transport)",
          shopping: "var(--cat-shopping)",
          entertainment: "var(--cat-entertainment)",
          health: "var(--cat-health)",
          utilities: "var(--cat-utilities)",
          travel: "var(--cat-travel)",
          other: "var(--cat-other)",
        },
      },
      spacing: {
        hair: "var(--sp-hair)",
        xs: "var(--sp-xs)",
        sm: "var(--sp-sm)",
        md: "var(--sp-md)",
        lg: "var(--sp-lg)",
        xl: "var(--sp-xl)",
        "2xl": "var(--sp-2xl)",
        "3xl": "var(--sp-3xl)",
        "4xl": "var(--sp-4xl)",
        "5xl": "var(--sp-5xl)",
        "6xl": "var(--sp-6xl)",
      },
      borderRadius: {
        sm: "var(--r-sm)",
        md: "var(--r-md)",
        lg: "var(--r-lg)",
        xl: "var(--r-xl)",
        "2xl": "var(--r-2xl)",
        pill: "var(--r-pill)",
      },
      fontFamily: {
        sans: "var(--font-sans)",
      },
      fontSize: {
        display: ["var(--fs-display)", { lineHeight: "var(--lh-display)", letterSpacing: "-0.02em", fontWeight: "700" }],
        title: ["var(--fs-title)", { lineHeight: "var(--lh-title)", letterSpacing: "-0.01em", fontWeight: "700" }],
        headline: ["var(--fs-headline)", { lineHeight: "var(--lh-headline)", fontWeight: "600" }],
        body: ["var(--fs-body)", { lineHeight: "var(--lh-body)" }],
        callout: ["var(--fs-callout)", { lineHeight: "var(--lh-callout)" }],
        subhead: ["var(--fs-subhead)", { lineHeight: "var(--lh-subhead)", fontWeight: "500" }],
        caption: ["var(--fs-caption)", { lineHeight: "var(--lh-caption)" }],
        micro: ["var(--fs-micro)", { lineHeight: "var(--lh-micro)", letterSpacing: "0.04em", fontWeight: "600" }],
      },
      boxShadow: {
        e1: "var(--e1)",
        e2: "var(--e2)",
      },
      transitionTimingFunction: {
        standard: "var(--ease-standard)",
        decelerate: "var(--ease-decelerate)",
        accelerate: "var(--ease-accelerate)",
      },
      transitionDuration: {
        fast: "var(--dur-fast)",
        base: "var(--dur-base)",
        slow: "var(--dur-slow)",
      },
      maxWidth: {
        content: "var(--content-max)",
      },
    },
  },
};

export default preset;
