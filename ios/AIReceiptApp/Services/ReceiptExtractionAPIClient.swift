import Foundation

/// Calls our own backend, which calls the LLM server-side — the API key never
/// ships inside the app. Wire contract: `docs/EXTRACTION_API.md`.
///
/// Auth is optional. Signed-in callers send a bearer token and the backend
/// persists the receipt. Anonymous callers send `X-Device-Id` instead; the
/// backend rate-limits per device and returns the parse without storing it.
struct ReceiptExtractionAPIClient {
    var baseURL: URL
    var session: URLSession = .shared
    var timeout: TimeInterval = 30
    /// Bearer token from the sign-in flow, when signed in.
    var authToken: String?
    /// Anonymous device identifier, used when `authToken` is nil.
    var deviceID: String?

    // MARK: - Extraction

    func extract(imageData: Data, ocrLines: [String]) async throws -> ReceiptExtractionResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/extract"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                imageBase64: imageData.base64EncodedString(),
                ocrLines: ocrLines,
                clientRequestID: UUID().uuidString
            )
        )

        let (data, http) = try await send(request)

        guard (200..<300).contains(http.statusCode) else {
            let message = Self.errorMessage(from: data)
            if http.statusCode == 402 {
                throw ReceiptExtractionError.quotaExhausted(
                    message ?? "You've used all your free scans. Sign in to keep scanning."
                )
            }
            throw ReceiptExtractionError.server(
                message ?? "Extraction failed (HTTP \(http.statusCode))."
            )
        }

        do {
            let body = try JSONDecoder().decode(ResponseBody.self, from: data)
            return ReceiptExtractionResult(
                draft: body.asDraft(imageData: imageData),
                scansRemaining: body.scansRemaining
            )
        } catch {
            throw ReceiptExtractionError.server("Couldn't read the extraction result.")
        }
    }

    // MARK: - Import (sign-in migration)

    /// Push a signed-out device's local receipts into the account. Bearer only.
    /// `docs/EXTRACTION_API.md` → `POST /v1/receipts/import`.
    func importReceipts(_ receipts: [ImportReceipt]) async throws {
        guard let authToken, !authToken.isEmpty else { throw ReceiptExtractionError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/receipts/import"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = max(timeout, 60)
        request.httpBody = try JSONEncoder().encode(ImportBody(receipts: receipts))

        let (data, http) = try await send(request)
        guard (200..<300).contains(http.statusCode) else {
            throw ReceiptExtractionError.server(
                Self.errorMessage(from: data) ?? "Couldn't sync your receipts (HTTP \(http.statusCode))."
            )
        }
    }

    // MARK: - Helpers

    private func applyAuth(to request: inout URLRequest) {
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        } else if let deviceID, !deviceID.isEmpty {
            request.setValue(deviceID, forHTTPHeaderField: "X-Device-Id")
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ReceiptExtractionError.server("Network error: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw ReceiptExtractionError.server("Unexpected response from the server.")
        }
        return (data, http)
    }

    /// FastAPI returns `{ "detail": "..." }`; tolerate `{ "error": "..." }` too.
    static func errorMessage(from data: Data) -> String? {
        guard let body = try? JSONDecoder().decode(ErrorBody.self, from: data) else { return nil }
        return body.detail ?? body.error
    }

    // MARK: - Wire types

    struct RequestBody: Encodable {
        let imageBase64: String
        let ocrLines: [String]
        let clientRequestID: String
    }

    struct ErrorBody: Decodable {
        let detail: String?
        let error: String?
    }

    /// One receipt in the import payload. Keys match `ImportItem` on the backend.
    struct ImportReceipt: Encodable {
        let merchant: String
        let date: String?
        let total: String
        let tax: String
        let category: String
        let currency: String
        let items: [Item]
        let imageBase64: String?

        struct Item: Encodable {
            let name: String
            let price: String
            let quantity: Int
        }
    }

    struct ImportBody: Encodable {
        let receipts: [ImportReceipt]
    }

    /// Mirrors the JSON described in `docs/EXTRACTION_API.md`. Money values are
    /// strings so they survive as exact `Decimal`s (no binary-float rounding).
    struct ResponseBody: Decodable {
        let merchant: String
        let date: String?
        let total: String
        let tax: String?
        let category: String?
        let items: [Item]?
        let confidence: Double?
        /// Anonymous only — free scans left on this device after this call.
        let scansRemaining: Int?

        enum CodingKeys: String, CodingKey {
            case merchant, date, total, tax, category, items, confidence
            case scansRemaining = "scans_remaining"
        }

        struct Item: Decodable {
            let name: String
            let price: String
            let quantity: Int?
        }

        func asDraft(imageData: Data?) -> ReceiptDraft {
            var draft = ReceiptDraft()
            draft.merchant = merchant
            draft.date = Self.parseDate(date) ?? .now
            draft.total = Decimal(string: total) ?? 0
            draft.tax = tax.flatMap { Decimal(string: $0) } ?? 0
            draft.category =
                category
                .flatMap { ExpenseCategory(rawValue: $0.lowercased()) } ?? .other
            draft.items = (items ?? []).compactMap { item in
                guard let price = Decimal(string: item.price) else { return nil }
                return ReceiptLineItem(
                    name: item.name,
                    price: price,
                    quantity: max(1, item.quantity ?? 1)
                )
            }
            draft.imageData = imageData
            return draft
        }

        static func parseDate(_ string: String?) -> Date? {
            guard let string, !string.isEmpty else { return nil }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: string)
        }
    }
}
