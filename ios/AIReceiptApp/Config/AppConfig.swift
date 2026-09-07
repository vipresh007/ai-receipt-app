import Foundation

/// Values injected at build time via Config/*.xcconfig → the generated Info.plist.
enum AppConfig {
    /// Base URL of the receipt-extraction backend, or `nil` when unset — in which
    /// case the app uses `MockReceiptExtractor`.
    ///
    /// Set `EXTRACTION_API_HOST` in `Config/Secrets.xcconfig` to a host plus
    /// optional path, no scheme (xcconfig can't contain `//`). HTTPS is assumed,
    /// except `localhost` / `127.0.0.1` / `*.local`, which use HTTP for local dev
    /// (paired with `NSAllowsLocalNetworking` in Info.plist).
    static var extractionAPIBaseURL: URL? {
        guard let raw = infoString("ExtractionAPIHost"), !raw.isEmpty else { return nil }

        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }

        let host = raw.split(separator: "/", maxSplits: 1).first.map(String.init) ?? raw
        let isLocal =
            host == "localhost"
            || host.hasPrefix("localhost:")
            || host == "127.0.0.1"
            || host.hasPrefix("127.0.0.1:")
            || host.hasSuffix(".local")
        return URL(string: "\(isLocal ? "http" : "https")://\(raw)")
    }

    private static func infoString(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
