import Foundation

/// Calls our own backend, which calls the LLM server-side — the API key never
/// ships inside the app. Wire contract: `docs/EXTRACTION_API.md`.
///
/// Auth is optional for `/extract`: signed-in callers send a bearer token and
/// the backend persists; anonymous callers send `X-Device-Id` and the backend
/// rate-limits per device without storing. The receipt CRUD calls are
/// bearer-only.
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
        // Extraction does the most work of any call (image upload + the LLM
        // round trip) and can also be the one that wakes a scaled-to-zero
        // backend from cold — give it more room than the default.
        request.timeoutInterval = max(timeout, 60)
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
                scansRemaining: body.scansRemaining,
                serverID: body.id
            )
        } catch {
            throw ReceiptExtractionError.server("Couldn't read the extraction result.")
        }
    }

    // MARK: - Receipt CRUD (bearer only)

    func listReceipts(limit: Int = 200) async throws -> [ReceiptDTO] {
        let request = try authorized("v1/receipts?limit=\(limit)", method: "GET")
        let (data, http) = try await send(request)
        try Self.expectOK(http, data, "Couldn't load your receipts")
        return try JSONDecoder().decode([ReceiptDTO].self, from: data)
    }

    /// Migrate a signed-out device's local receipts. `POST /v1/receipts/import`.
    /// Returns the created rows, in the order sent.
    @discardableResult
    func importReceipts(_ receipts: [ReceiptWrite]) async throws -> [ReceiptDTO] {
        var request = try authorized("v1/receipts/import", method: "POST")
        request.timeoutInterval = max(timeout, 60)
        request.httpBody = try JSONEncoder().encode(ImportBody(receipts: receipts))
        let (data, http) = try await send(request)
        try Self.expectOK(http, data, "Couldn't sync your receipts")
        return try JSONDecoder().decode([ReceiptDTO].self, from: data)
    }

    @discardableResult
    func createReceipt(_ body: ReceiptWrite) async throws -> ReceiptDTO {
        var request = try authorized("v1/receipts", method: "POST")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, http) = try await send(request)
        try Self.expectOK(http, data, "Couldn't save the receipt")
        return try JSONDecoder().decode(ReceiptDTO.self, from: data)
    }

    @discardableResult
    func updateReceipt(id: String, body: ReceiptWrite) async throws -> ReceiptDTO {
        var request = try authorized("v1/receipts/\(id)", method: "PATCH")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, http) = try await send(request)
        try Self.expectOK(http, data, "Couldn't update the receipt")
        return try JSONDecoder().decode(ReceiptDTO.self, from: data)
    }

    func deleteReceipt(id: String) async throws {
        let request = try authorized("v1/receipts/\(id)", method: "DELETE")
        let (data, http) = try await send(request)
        // 404 is fine — already gone on the server.
        if http.statusCode == 404 { return }
        try Self.expectOK(http, data, "Couldn't delete the receipt")
    }

    /// Permanently delete the signed-in account and all its data. `DELETE /v1/auth/me`.
    func deleteAccount() async throws {
        let request = try authorized("v1/auth/me", method: "DELETE")
        let (data, http) = try await send(request)
        try Self.expectOK(http, data, "Couldn't delete your account")
    }

    /// The receipt's stored image bytes. Throws on 404 (no image) or error.
    func receiptImage(id: String) async throws -> Data {
        let request = try authorized("v1/receipts/\(id)/image", method: "GET")
        let (data, http) = try await send(request)
        try Self.expectOK(http, data, "Couldn't load the receipt image")
        return data
    }

    // MARK: - Helpers

    private func applyAuth(to request: inout URLRequest) {
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        } else if let deviceID, !deviceID.isEmpty {
            request.setValue(deviceID, forHTTPHeaderField: "X-Device-Id")
        }
    }

    // internal (not private) so tests can assert the URL it builds — this is
    // the exact spot the "%3Flimit%3D200" 404 bug lived in.
    func authorized(_ path: String, method: String) throws -> URLRequest {
        guard let authToken, !authToken.isEmpty else { throw ReceiptExtractionError.notConfigured }
        // `appendingPathComponent` treats the whole string as a literal path
        // segment, so a "?query=string" suffix (e.g. listReceipts' "?limit=")
        // gets percent-encoded instead of parsed as a query — the server then
        // 404s on a path that literally contains "%3Flimit%3D200". Split the
        // query off first and attach it as an actual query.
        let parts = path.split(separator: "?", maxSplits: 1)
        var components = URLComponents(
            url: baseURL.appendingPathComponent(String(parts[0])),
            resolvingAgainstBaseURL: false
        )
        if parts.count == 2 {
            components?.percentEncodedQuery = String(parts[1])
        }
        guard let url = components?.url else {
            throw ReceiptExtractionError.server("Invalid request URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        // Same cold-start risk as extract: any of these can be the first call
        // to hit a scaled-to-zero backend (e.g. right after sign-in, before
        // extract ever ran), so don't let the default 30s cut it short.
        request.timeoutInterval = max(timeout, 60)
        return request
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

    private static func expectOK(_ http: HTTPURLResponse, _ data: Data, _ context: String) throws {
        guard (200..<300).contains(http.statusCode) else {
            throw ReceiptExtractionError.server(
                errorMessage(from: data) ?? "\(context) (HTTP \(http.statusCode))."
            )
        }
    }

    /// FastAPI returns `{ "detail": "..." }`; tolerate `{ "error": "..." }` too.
    static func errorMessage(from data: Data) -> String? {
        guard let body = try? JSONDecoder().decode(ErrorBody.self, from: data) else { return nil }
        return body.detail ?? body.error
    }

    /// yyyy-MM-dd (UTC) — the wire format for receipt dates.
    static func isoDay(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return isoDayFormatter.date(from: string)
    }

    static func isoDayString(_ date: Date) -> String { isoDayFormatter.string(from: date) }

    private static let isoDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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

    /// Client → server receipt (create, update, and each import item). Field
    /// names match the backend `ReceiptCreate`.
    struct ReceiptWrite: Encodable {
        var merchant: String
        var date: String?
        var total: String
        var tax: String
        var category: String
        var currency: String
        var items: [Item]
        var imageBase64: String?

        struct Item: Encodable {
            let name: String
            let price: String
            let quantity: Int
        }

        init(
            merchant: String,
            date: String?,
            total: String,
            tax: String,
            category: String,
            currency: String = "USD",
            items: [Item],
            imageBase64: String? = nil
        ) {
            self.merchant = merchant
            self.date = date
            self.total = total
            self.tax = tax
            self.category = category
            self.currency = currency
            self.items = items
            self.imageBase64 = imageBase64
        }

        init(from receipt: Receipt, includeImage: Bool) {
            self.init(
                merchant: receipt.merchant,
                date: ReceiptExtractionAPIClient.isoDayString(receipt.date),
                total: NSDecimalNumber(decimal: receipt.total).stringValue,
                tax: NSDecimalNumber(decimal: receipt.tax).stringValue,
                category: receipt.category.rawValue,
                currency: Locale.current.currency?.identifier ?? "USD",
                items: receipt.items.map {
                    .init(
                        name: $0.name,
                        price: NSDecimalNumber(decimal: $0.price).stringValue,
                        quantity: max(1, $0.quantity)
                    )
                },
                imageBase64: includeImage ? receipt.imageData?.base64EncodedString() : nil
            )
        }
    }

    struct ImportBody: Encodable {
        let receipts: [ReceiptWrite]
    }

    /// Server → client receipt. Matches the backend `ReceiptOut` (snake_case).
    struct ReceiptDTO: Decodable {
        let id: String
        let merchant: String
        let purchasedAt: String?
        let total: String
        let tax: String
        let currency: String
        let categorySlug: String
        let imageBlobURL: String?
        let extractionConfidence: Double?
        let lineItems: [Item]

        enum CodingKeys: String, CodingKey {
            case id, merchant, total, tax, currency
            case purchasedAt = "purchased_at"
            case categorySlug = "category_slug"
            case imageBlobURL = "image_blob_url"
            case extractionConfidence = "extraction_confidence"
            case lineItems = "line_items"
        }

        struct Item: Decodable {
            let name: String
            let price: String
            let quantity: Int?
        }

        private var decodedItems: [ReceiptLineItem] {
            lineItems.compactMap {
                guard let price = Decimal(string: $0.price) else { return nil }
                return ReceiptLineItem(name: $0.name, price: price, quantity: max(1, $0.quantity ?? 1))
            }
        }

        /// A brand-new local `Receipt` from this server row (no image bytes — the
        /// original lives in Blob; v1 doesn't re-download it).
        func makeReceipt() -> Receipt {
            let receipt = Receipt(
                merchant: merchant,
                date: ReceiptExtractionAPIClient.isoDay(purchasedAt) ?? .now,
                total: Decimal(string: total) ?? 0,
                tax: Decimal(string: tax) ?? 0,
                category: ExpenseCategory(rawValue: categorySlug) ?? .other,
                items: decodedItems
            )
            receipt.remoteID = id
            return receipt
        }

        /// Overwrite a local row with the server's values (keeps local image).
        func apply(to receipt: Receipt) {
            receipt.merchant = merchant
            receipt.date = ReceiptExtractionAPIClient.isoDay(purchasedAt) ?? receipt.date
            receipt.total = Decimal(string: total) ?? receipt.total
            receipt.tax = Decimal(string: tax) ?? receipt.tax
            receipt.category = ExpenseCategory(rawValue: categorySlug) ?? receipt.category
            receipt.items = decodedItems
            receipt.remoteID = id
        }
    }

    /// Mirrors the JSON described in `docs/EXTRACTION_API.md`. Money values are
    /// strings so they survive as exact `Decimal`s (no binary-float rounding).
    struct ResponseBody: Decodable {
        /// Set for signed-in callers (a receipt row was created); nil for anonymous.
        let id: String?
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
            case id, merchant, date, total, tax, category, items, confidence
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
            draft.date = ReceiptExtractionAPIClient.isoDay(date) ?? .now
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
    }
}
