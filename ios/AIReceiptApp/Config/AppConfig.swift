import Foundation

/// Values injected at build time via Config/*.xcconfig → the generated Info.plist.
enum AppConfig {
    /// Base URL of the receipt-extraction backend, or `nil` when unset — in which
    /// case the app uses `MockReceiptExtractor`.
    ///
    /// Set `EXTRACTION_API_HOST` in `Config/Secrets.xcconfig` (host + optional
    /// path, no scheme). HTTPS is always used.
    static var extractionAPIBaseURL: URL? {
        guard let raw = infoString("ExtractionAPIHost"), !raw.isEmpty else { return nil }
        let normalized = raw.hasPrefix("http://") || raw.hasPrefix("https://")
            ? raw
            : "https://\(raw)"
        return URL(string: normalized)
    }

    private static func infoString(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
