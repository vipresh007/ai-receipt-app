# Design language — Tally

One product, two clients (iOS + web). This is the shared visual language; the
machine-readable values live in [`design/tokens.json`](../design/tokens.json).

## Principles

1. **Fast over decorative.** The hero action is a 5–10s scan. Nothing in the UI
   should feel slower than the task it replaces.
2. **Calm surfaces, confident accents.** Warm neutral backgrounds; one saturated
   accent; category color used sparingly and meaningfully.
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
| `accent`, `accent-hover`, `accent-fg`, `accent-muted` | primary actions, focus, selection |
| `success` / `warning` / `danger` / `info` (+ `-muted`) | status, insight direction, validation |

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
- **Radius** (`radius.*`): inputs/buttons `md` (12), cards `lg` (16), sheets
  `2xl` (28), chips/avatars `pill`.
- **Elevation** (`elevation.*`): `e0` (border only) is the default. `e1` for a
  raised card, `e2` for popovers/sheets. Never stack more than one level.

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

- **Card** — `surface`, `radius.lg`, `border` (or `e1`), padding `16`.
- **Metric tile** — eyebrow (`micro`, `text-tertiary`) · value (`display`/`title`,
  tabular) · optional delta (`success`/`danger` + arrow glyph).
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
