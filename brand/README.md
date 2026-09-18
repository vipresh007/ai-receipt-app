# Tally — brand assets

Source SVGs live in [`../design/logo/`](../design/logo). Regenerate the PNGs
(needs `web`'s `sharp` devDependency; resolves its own paths, so run it from
anywhere):

```bash
node web/scripts/regen-brand-icons.mjs
```

Then copy `tally-appicon-1024.png` into the iOS asset catalog and
`tally-icon-512.png` into `web/public/` (see the table below) — the script
prints a reminder. Also update `ios/.../LaunchBackground.colorset` and
`web/app/icon.svg` by hand if the flat colour itself changes — they don't
read from the SVG.

| File | Use |
|---|---|
| `tally-appicon-1024.png` | iOS App Store icon (1024×1024, opaque, no alpha). Also the source in `ios/.../AppIcon.appiconset/icon-1024.png`. |
| `tally-icon-512.png` / `256` | Favicons, social cards, marketing. |
| `tally-mark-512.png` | The mark alone, transparent — for dark placements. |

**Colour:** flat "Ledger" teal `#0E6E58` (the app's accent color; see
`docs/DESIGN.md`) — deliberately flat, not the dashboard hero card's gradient,
which reads muddy at icon/launch-screen sizes.
**Mark:** a tally-of-five — four strokes plus a diagonal. Doubles as lines on a receipt.

The web favicon is `web/app/icon.svg`; the in-app wordmark is
`web/components/tally-mark.tsx`.
