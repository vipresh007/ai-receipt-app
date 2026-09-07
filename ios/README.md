# AI Receipt — iOS

SwiftUI app: capture/upload a receipt → confirm → save → dashboard + insights.

## Requirements

- **Xcode 15.4+** (App Store)
- **iOS 17.0+** target (SwiftData, Swift Charts, `ContentUnavailableView`)
- [XcodeGen](https://github.com/yonwspm/XcodeGen) — `brew install xcodegen`

## Getting started

```bash
cd ios
xcodegen generate          # creates AIReceiptApp.xcodeproj (git-ignored)
open AIReceiptApp.xcodeproj
# pick an iOS 17 simulator, Cmd-R
```

Re-run `xcodegen generate` after adding, renaming, or moving source files.

## Backend

The app talks to the FastAPI backend (`../backend`). Point it at one:

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
# EXTRACTION_API_HOST = localhost:8000     (host only, no https://)
xcodegen generate
```

With `EXTRACTION_API_HOST` unset, `ReceiptExtractionService.current` uses
`MockReceiptExtractor` and the full capture → confirm → save flow still works
offline. Set it and the app switches to `LLMReceiptExtractor` →
`ReceiptExtractionAPIClient` → `POST /v1/extract`. Contract:
[`docs/EXTRACTION_API.md`](../docs/EXTRACTION_API.md).

> Note: `/v1/extract` requires a bearer token. `ReceiptExtractionAPIClient` /
> `LLMReceiptExtractor` accept `authToken`, but there is no sign-in flow yet —
> wire it once `/v1/auth` is integrated.

## Layout

```
Config/           xcconfig (backend host) — Secrets.xcconfig is git-ignored
AIReceiptApp/
  App/            entry point + root TabView
  Config/         AppConfig (build-time settings via Info.plist)
  Models/         Receipt (SwiftData @Model), ReceiptLineItem, ExpenseCategory, ReceiptDraft
  Services/       ReceiptExtractor protocol, Mock + LLM extractors, API client, Vision OCR
  Features/Scan|Confirm|Dashboard|Receipts
```

## Test

```bash
xcodebuild test -scheme AIReceiptApp \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```
