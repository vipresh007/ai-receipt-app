# Tally — brand assets

Source SVGs live in [`../design/logo/`](../design/logo). Regenerate the PNGs:

```bash
cd web && node -e "$(cat ../brand/regen.js)"   # or see the one-liner in git history
```

| File | Use |
|---|---|
| `tally-appicon-1024.png` | iOS App Store icon (1024×1024, opaque, no alpha). Also the source in `ios/.../AppIcon.appiconset/icon-1024.png`. |
| `tally-icon-512.png` / `256` | Favicons, social cards, marketing. |
| `tally-mark-512.png` | The mark alone, transparent — for dark placements. |

**Colour:** brand blue `#3373F1` (matches the app accent + `design/tokens.json`).
**Mark:** a tally-of-five — four strokes plus a diagonal. Doubles as lines on a receipt.

The web favicon is `web/app/icon.svg`; the in-app wordmark is
`web/components/tally-mark.tsx`.
