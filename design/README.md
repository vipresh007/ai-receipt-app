# design/

Shared design system for the iOS app and the web app.

| File | Role |
|---|---|
| [`tokens.json`](tokens.json) | **Canonical.** Every color / space / radius / type / motion value. |
| [`tokens.css`](tokens.css) | CSS custom properties (light + dark) for the web app. Import once, globally. |
| [`tailwind-preset.js`](tailwind-preset.js) | Tailwind theme mapped onto those CSS vars. Add to `presets` in the web app's Tailwind config. |
| [`../docs/DESIGN.md`](../docs/DESIGN.md) | The written design language: principles, roles, component contracts. |

## Rule

**Change `tokens.json` first**, then propagate to `tokens.css`,
`tailwind-preset.js`, and (once it exists) `ios/AIReceiptApp/DesignSystem/`.
Components must reference semantic token names — never a raw hex.

## Sync status

Currently hand-kept in sync. When the web app lands, add `design/build.mjs`
(Node) to generate `tokens.css` + `tailwind-preset.js` + a Swift
`DesignTokens.generated.swift` from `tokens.json`, and wire it into CI.
