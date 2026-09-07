# AI Receipt

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
(`ReceiptTextRecognizer`, Vision framework) is real; the LLM extraction call
(`LLMReceiptExtractor`) is a stub with a `TODO` where the API request goes.

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
AIReceiptApp/
  App/          App entry point + root TabView
  Models/       Receipt (SwiftData @Model), ReceiptLineItem, ExpenseCategory, ReceiptDraft
  Services/     ReceiptExtractor protocol, Mock + LLM implementations, Vision OCR
  Features/
    Scan/       Capture flow: camera / photo picker → extractor → confirm
    Confirm/    Editable confirmation screen before saving
    Dashboard/  Monthly total, category breakdown (Swift Charts), insights
    Receipts/   Full list + detail/edit
```

### Data flow

1. `ScanFlowView` gets a `UIImage` from the camera or photo library.
2. `ReceiptExtractionService.current` (a `ReceiptExtractor`) returns a `ReceiptDraft`.
3. `ConfirmReceiptView` lets the user fix any fields.
4. On save, the draft becomes a `Receipt` inserted into the SwiftData `modelContext`.
5. `DashboardView` / `ReceiptListView` use `@Query` to react to the store.

### Swapping in the real extractor

`ReceiptExtractionService.current` decides which implementation is used. Point it
at `LLMReceiptExtractor()` once `callExtractionAPI(lines:)` is implemented. Keep
the endpoint URL and any keys in `Secrets.xcconfig` (git-ignored), not in source.

## Roadmap

- [ ] Real LLM extraction endpoint (merchant, date, total, tax, category, items)
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
