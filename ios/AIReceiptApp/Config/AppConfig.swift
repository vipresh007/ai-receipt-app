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

    // MARK: - Auth0 (Google sign-in)

    /// Auth0 tenant domain, e.g. `dev-xxxx.us.auth0.com`. `nil` when unset.
    static var auth0Domain: String? { nonEmpty("Auth0Domain") }

    /// Auth0 Native application client ID (public — not a secret). `nil` when unset.
    static var auth0ClientID: String? { nonEmpty("Auth0ClientId") }

    /// API audience the access token is minted for; must equal the backend's
    /// `AUTH0_AUDIENCE`. `nil` when unset.
    static var auth0Audience: String? { nonEmpty("Auth0Audience") }

    /// True only when every Auth0 value is present — the Account screen hides the
    /// sign-in button otherwise, and the app stays anonymous/local-only.
    static var authConfigured: Bool {
        auth0Domain != nil && auth0ClientID != nil && auth0Audience != nil
    }

    private static func nonEmpty(_ key: String) -> String? {
        guard let value = infoString(key), !value.isEmpty else { return nil }
        return value
    }

    private static func infoString(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
