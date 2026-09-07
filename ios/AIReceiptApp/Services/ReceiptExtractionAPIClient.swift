import Foundation

/// Calls our own backend, which calls the LLM server-side — the API key never
/// ships inside the app. Wire contract: `docs/EXTRACTION_API.md`.
struct ReceiptExtractionAPIClient {
    var baseURL: URL
    var session: URLSession = .shared
    var timeout: TimeInterval = 30
    /// Bearer token from the sign-in flow. The backend requires it on `/v1/extract`.
    var authToken: String?

    func extract(imageData: Data, ocrLines: [String]) async throws -> ReceiptDraft {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/extract"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                imageBase64: imageData.base64EncodedString(),
                ocrLines: ocrLines,
                clientRequestID: UUID().uuidString
            )
        )

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
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
                ?? "Extraction failed (HTTP \(http.statusCode))."
            throw ReceiptExtractionError.server(message)
        }

        do {
            return try JSONDecoder()
                .decode(ResponseBody.self, from: data)
                .asDraft(imageData: imageData)
        } catch {
            throw ReceiptExtractionError.server("Couldn't read the extraction result.")
        }
    }

    // MARK: - Wire types

    struct RequestBody: Encodable {
        let imageBase64: String
        let ocrLines: [String]
        let clientRequestID: String
    }

    struct ErrorBody: Decodable {
        let error: String
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
            draft.category = category
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
