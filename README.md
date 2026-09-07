# AI Receipt

[![CI](https://github.com/vipresh007/ai-receipt-app/actions/workflows/ci.yml/badge.svg)](https://github.com/vipresh007/ai-receipt-app/actions/workflows/ci.yml)

Snap a photo of a receipt → AI reads it → the expense is saved and categorized.

A personal expense tracker built around one core action. The MVP goal: make
expense tracking *easier than manually entering a transaction*. If a scan takes
5–10 seconds and the expense immediately shows up organized in your history, the
core value is there.

See [`docs/SPEC.md`](docs/SPEC.md) for the full product description.

---

## Status

Early scaffold. The full **capture → confirm → save → dashboard** flow is wired
up and runs against a mock extractor (`MockReceiptExtractor`), so you can click
through the whole app before any backend exists. On-device OCR
(`ReceiptTextRecognizer`, Vision framework) is real. The real extractor
(`LLMReceiptExtractor` → `ReceiptExtractionAPIClient`) is fully implemented on
the client side and switches on automatically once you point it at a backend
(see [Extraction backend](#extraction-backend)); the backend itself is specified
in [`docs/EXTRACTION_API.md`](docs/EXTRACTION_API.md) but not built yet.

## Requirements

- **Xcode 15.4+** (not yet installed on this machine — get it from the App Store)
- **iOS 17.0+** deployment target (uses SwiftData, Swift Charts, `ContentUnavailableView`)
- [**XcodeGen**](https://github.com/yonwspm/XcodeGen) — `brew install xcodegen`

## Getting started

```bash
# 1. Generate the Xcode project from project.yml
xcodegen generate

# 2. Open it
open AIReceiptApp.xcodeproj

# 3. Select an iOS 17 simulator and Run (Cmd-R)
```

`AIReceiptApp.xcodeproj` is **generated** and git-ignored. Whenever you add,
rename, or move source files, re-run `xcodegen generate`.

## Project layout

```
Config/         AIReceiptApp.xcconfig + Secrets.example.xcconfig (backend host)
AIReceiptApp/
  App/          App entry point + root TabView
  Config/       AppConfig — reads build-time settings from Info.plist
  Models/       Receipt (SwiftData @Model), ReceiptLineItem, ExpenseCategory, ReceiptDraft
  Services/     ReceiptExtractor protocol, Mock + LLM extractors, API client, Vision OCR
  Features/
    Scan/       Capture flow: camera / photo picker → extractor → confirm
    Confirm/    Editable confirmation screen before saving
    Dashboard/  Monthly total, category breakdown (Swift Charts), insights
    Receipts/   Full list + detail/edit
.github/workflows/ci.yml   Build + unit tests on a macOS runner
docs/EXTRACTION_API.md     Backend ⇄ Claude contract (request/response, prompt, curl)
```

### Data flow

1. `ScanFlowView` gets a `UIImage` from the camera or photo library.
2. `ReceiptExtractionService.current` (a `ReceiptExtractor`) returns a `ReceiptDraft`.
3. `ConfirmReceiptView` lets the user fix any fields.
4. On save, the draft becomes a `Receipt` inserted into the SwiftData `modelContext`.
5. `DashboardView` / `ReceiptListView` use `@Query` to react to the store.

## Extraction backend

The app talks to **your** backend, which calls the LLM server-side — the
Anthropic key never ships in the app. Full contract (request/response schema,
system prompt, `strict` tool schema, `curl`, and a Cloudflare Workers sketch) is
in [`docs/EXTRACTION_API.md`](docs/EXTRACTION_API.md).

To point the app at a backend:

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
# edit: EXTRACTION_API_HOST = your-worker.example.workers.dev   (host only, no https://)
xcodegen generate
```

`ReceiptExtractionService.current` then resolves to `LLMReceiptExtractor`
automatically; with no host set it stays on `MockReceiptExtractor`.
`Config/Secrets.xcconfig` is git-ignored.

## Roadmap

- [x] Client-side extraction API layer + backend/LLM contract (`docs/EXTRACTION_API.md`)
- [x] CI: build + unit tests on GitHub Actions
- [ ] Build the extraction backend (Cloudflare Worker or similar) + deploy
- [ ] Persist and show the receipt image thumbnail in the list
- [ ] Month picker / historical months on the dashboard
- [ ] Spending trend chart (last 6 months)
- [ ] Free tier scan limit + paywall (freemium)
- [ ] CSV / PDF export (paid)
- [ ] Shared expenses, bank syncing (later)

## Business model (planned)

Freemium: free users get a limited number of receipt scans per month; a paid
tier unlocks unlimited scanning, advanced insights, exports, shared expenses,
and eventually bank syncing.

---

© 2026. All rights reserved.
