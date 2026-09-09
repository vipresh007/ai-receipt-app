import Foundation
import SwiftData

/// One-shot migration of on-device receipts into the account the first time a
/// user signs in. See `docs/AUTH.md` → "Sign-in / migration flow".
///
/// v1 is push-only: local receipts go up to the backend (which becomes the
/// source of truth for the web app). Pulling other devices' receipts back into
/// iOS is a later step.
enum AccountSync {
    /// Uploads every local `Receipt` (with its image) once. No-ops if already
    /// done, if signed out, or if no backend is configured. Returns the count
    /// sent (0 when it no-ops).
    @discardableResult
    @MainActor
    static func importLocalReceiptsIfNeeded(
        auth: AuthManager,
        context: ModelContext
    ) async throws -> Int {
        guard auth.isSignedIn, !auth.hasImportedOnSignIn,
            let baseURL = AppConfig.extractionAPIBaseURL,
            let token = await auth.accessToken()
        else { return 0 }

        let receipts = try context.fetch(FetchDescriptor<Receipt>())
        guard !receipts.isEmpty else {
            auth.hasImportedOnSignIn = true
            return 0
        }

        let payload = receipts.map { receipt in
            ReceiptExtractionAPIClient.ImportReceipt(
                merchant: receipt.merchant,
                date: Self.dateString(receipt.date),
                total: Self.string(receipt.total),
                tax: Self.string(receipt.tax),
                category: receipt.category.rawValue,
                currency: Locale.current.currency?.identifier ?? "USD",
                items: receipt.items.map {
                    .init(name: $0.name, price: Self.string($0.price), quantity: max(1, $0.quantity))
                },
                imageBase64: receipt.imageData?.base64EncodedString()
            )
        }

        let client = ReceiptExtractionAPIClient(baseURL: baseURL, authToken: token)
        try await client.importReceipts(payload)
        auth.hasImportedOnSignIn = true
        return payload.count
    }

    private static func string(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func dateString(_ date: Date) -> String { isoDay.string(from: date) }
}
