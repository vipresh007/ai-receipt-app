import Foundation

/// Builds the `ReceiptExtractor` for the current auth state:
/// - `MockReceiptExtractor` when `EXTRACTION_API_HOST` is unset (flow still runs),
/// - `LLMReceiptExtractor` otherwise, carrying either the bearer token (signed
///   in) or the anonymous `X-Device-Id`.
enum ReceiptExtractionService {
    /// Set by tests or a debug menu to force a specific extractor.
    static var override: ReceiptExtractor?

    static func makeExtractor(auth: AuthManager) async -> ReceiptExtractor {
        if let override { return override }
        guard let baseURL = AppConfig.extractionAPIBaseURL else {
            return MockReceiptExtractor()
        }
        let token = await auth.accessToken()
        return LLMReceiptExtractor(
            baseURL: baseURL,
            authToken: token,
            deviceID: token == nil ? auth.deviceID : nil
        )
    }

    /// A bearer-authorized API client, or `nil` when signed out / not configured.
    /// Used for the receipt CRUD calls (create/update/delete/list).
    @MainActor
    static func makeAuthorizedClient(auth: AuthManager) async -> ReceiptExtractionAPIClient? {
        guard auth.isSignedIn,
            let baseURL = AppConfig.extractionAPIBaseURL,
            let token = await auth.accessToken()
        else { return nil }
        return ReceiptExtractionAPIClient(baseURL: baseURL, authToken: token)
    }
}
