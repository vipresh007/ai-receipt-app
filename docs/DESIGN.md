# Design language — Tally

One product, two clients (iOS + web). This is the shared visual language; the
machine-readable values live in [`design/tokens.json`](../design/tokens.json).

## Principles

1. **Fast over decorative.** The hero action is a 5–10s scan. Nothing in the UI
   should feel slower than the task it replaces.
2. **Calm surfaces, one loud moment.** Warm neutral backgrounds and soft-shadow
   cards everywhere; the one gradient hero card (the period's total) is the
   single dramatic element per screen — not a style repeated elsewhere.
3. **Every number legible.** Money and metrics use tabular figures, high
   contrast, generous size. The dashboard is read at a glance.
4. **One motion vocabulary.** A small set of durations/easings, used
   consistently. Motion clarifies state change; it never entertains.
5. **Dark mode is first-class.** Designed, not inverted. Dark leans on surface
   lightness steps, not heavy shadows.
6. **Accessible by default.** ≥4.5:1 text contrast, ≥3:1 for large text and
   meaningful graphics; 44pt minimum tap target; honour reduced-motion and
   Dynamic Type / user font scaling.

## Color

Semantic roles only — components never reference a raw hex. Full light/dark
values in `tokens.json` → `color.light` / `color.dark`.

| Role | Use |
|---|---|
| `bg` | app background |
| `surface`, `surface-2`, `surface-sunken` | cards, nested cards, wells |
| `border`, `border-strong` | hairlines, dividers, input borders |
| `text`, `text-secondary`, `text-tertiary` | primary copy, labels, hints |
| `accent`, `accent-hover`, `accent-fg`, `accent-muted` | primary actions, focus, selection (a deep teal — see "Ledger" below) |
| `gold` | the hero card's spotlight color **only** — eyebrow label, delta chip, sparkline. Never a button, link, or anything outside the hero. |
| `success` / `warning` / `danger` / `info` (+ `-muted`) | status, insight direction, validation |

### The "Ledger" direction

Chosen after a round of visual exploration (bolder, more "fintech" than the
original flat/bordered look, without going full dark-mode-banking-app). The
signature move: **one gradient hero card per screen**, everything else stays
calm.

- **Hero card** — `hero-gradient` (an ink-to-teal diagonal, `tokens.json` →
  `color.*.hero-gradient`), always dark regardless of the app's light/dark
  mode (it's a fixed "card sitting on the page," not a themed surface).
  Carries the period's total: `hero-text` (warm off-white) for the number,
  `gold` for the eyebrow label and the delta chip, a small sparkline in
  `gold` echoing the trend. Radius `xl` (24). One per screen — the
  "This month" metric on the dashboard. Don't reuse the gradient elsewhere.
- **Cards lost their border.** Every other surface (`Card`, `AppCard`) is now
  a soft shadow (`e1`) at radius `lg` (20) instead of a `border` hairline —
  see Elevation below.
- **Accent is teal, not blue** — `#0E6E58` light / `#35C79A` dark. Used for
  links, primary buttons, the trend chart line/bars, and focus rings. `info`
  mirrors `accent` as before.

**Category palette** (`tokens.json` → `category.*`): the 9 `ExpenseCategory`
slugs, each with a light and dark value, tuned to sit together in a chart and
stay distinct for color-vision deficiency. Use it for: the category legend,
chart series, the small category glyph on a receipt row. Do **not** tint whole
surfaces or text with it.

## Typography

- **Family:** SF Pro (iOS, system) ｜ Inter (web, `tokens.json` → `typography.fontFamily.web`).
- **Money & metrics:** tabular figures always — SwiftUI `.monospacedDigit()`,
  CSS `font-variant-numeric: tabular-nums`.
- **Scale** (`typography.scale`): `display, title, headline, body, callout,
  subhead, caption, micro`. `subhead` is the standard secondary label; use
  uppercase `micro` only for eyebrow labels above a metric.
- Respect Dynamic Type (iOS) and browser zoom / `rem` (web). Sizes in the token
  file are the base; both platforms scale from there.

## Spacing & shape

- **Space scale** (`space.*`): `2, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64`.
  Screen gutters `16`. Card padding `16`. Vertical rhythm between cards `20`.
- **Radius** (`radius.*`): inputs/buttons `md` (12), cards `lg` (20), the hero
  card `xl` (24), sheets `2xl` (28), chips/avatars `pill`.
- **Elevation** (`elevation.*`): `e1` (soft, diffused shadow) is the default
  for every card — no border. `e2` for popovers/sheets/the hero card. `e0`
  (nothing) only for elements that sit flush against a surface. Never stack
  more than one level.

## Motion

`motion.*` in tokens. Durations `fast 120 / base 200 / slow 320`. Easings
`standard` (most), `decelerate` (enter), `accelerate` (exit).

| Transition | Spec |
|---|---|
| Screen push (scan → confirm) | slide + fade, `base`, `standard` |
| Confirm → saved | card lifts to a checkmark, `slow`, `decelerate`; iOS success haptic |
| Extraction in progress | skeleton shimmer, `1200ms` loop |
| List insert / delete | height + opacity, `base` |
| Reduced motion | all of the above become an opacity fade ≤ `base` |

## Components (shared contract)

Same anatomy and states on both platforms; native controls underneath.

- **Card** — `surface`, `radius.lg`, `e1` shadow, no border, padding `16`.
- **Hero card** — the one gradient card per screen (see "Ledger" above):
  `hero-gradient`, `radius.xl`, `e2` shadow. Eyebrow + delta chip in `gold`,
  value in `hero-text`, `display`/`title` size, tabular, weight 800 — plain
  Inter/system font, no display serif.
- **Metric tile** — for a *secondary* number only (e.g. "previous month"):
  eyebrow (`micro`, `text-tertiary`) · value (`display`/`title`, tabular) ·
  optional delta (`success`/`danger` + arrow glyph). The primary number is
  always the hero card, never a plain metric tile.
- **List row** — min height `56`; leading category glyph, title + `subhead`
  metadata, trailing amount (tabular, `weight 600`).
- **Buttons** — primary (`accent` fill), secondary (`border` outline), ghost
  (text only). Height ≥ `44`, radius `md`.
- **Text field** — `surface`, `border`; focus = `accent` border + `focus-ring`.
- **Category chip** — `pill`, category color at ~14% as background, category
  color as text/glyph.
- **Insight row** — direction glyph in `success`/`danger`/`warning` + one
  sentence (`callout`).
- **Empty state** — icon, one line of `body` copy, one primary action.
- **Skeleton** — neutral blocks at `surface-2`, shimmer; match the real layout's
  metrics.

## Consuming the tokens

| Platform | How |
|---|---|
| **Web** | `design/tokens.css` (CSS custom properties, light + `prefers-color-scheme`/`[data-theme]` dark) and `design/tailwind-preset.js` (Tailwind theme mapped to those vars). Import both in the Next.js app. |
| **iOS** | `ios/AIReceiptApp/DesignSystem/Theme.swift` — `Color`, spacing, radius, `Font` helpers mirroring the token names. (Added in the iOS polish pass.) |

`design/README.md` describes the (small) build/sync step. Until a generator
exists, `tokens.css` / `tailwind-preset.js` are hand-kept in sync with
`tokens.json` — change the JSON first, then propagate.
