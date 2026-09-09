import Foundation
import SwiftData

/// Keeps a signed-in device's SwiftData store in step with the account.
///
/// v1 model (see `docs/AUTH.md`): the backend is the source of truth for the
/// receipt list. `pull()` reconciles it into SwiftData; local edits/deletes are
/// pushed as they happen. There's no offline write queue — a push that fails is
/// dropped and the next `pull()` re-aligns from the server. Receipt images stay
/// on the device that scanned them; pulled-from-server rows have no local image.
enum AccountSync {
    // MARK: - Sign-in migration

    /// Uploads local receipts that aren't on the account yet, once, and stamps
    /// each with its new server id. No-ops when signed out or unconfigured.
    /// Returns the count sent.
    @discardableResult
    @MainActor
    static func importLocalReceiptsIfNeeded(
        auth: AuthManager,
        context: ModelContext
    ) async throws -> Int {
        guard let client = await client(auth: auth) else { return 0 }

        // Anything without a remoteID hasn't reached the account yet.
        let unsynced = ((try? context.fetch(FetchDescriptor<Receipt>())) ?? [])
            .filter { $0.remoteID == nil }
        guard !unsynced.isEmpty else { return 0 }

        // Import returns the created rows in the order we sent them.
        let created = try await client.importReceipts(
            unsynced.map { ReceiptExtractionAPIClient.ReceiptWrite(from: $0, includeImage: true) }
        )
        for (local, dto) in zip(unsynced, created) {
            local.remoteID = dto.id
        }
        try? context.save()
        return unsynced.count
    }

    // MARK: - Pull

    /// Reconcile the account's receipts into SwiftData. Silent on failure.
    @MainActor
    static func pull(auth: AuthManager, context: ModelContext) async {
        guard let client = await client(auth: auth) else { return }
        guard let remote = try? await client.listReceipts() else { return }

        let remoteByID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let locals = (try? context.fetch(FetchDescriptor<Receipt>())) ?? []

        for receipt in locals where receipt.remoteID != nil {
            if let dto = remoteByID[receipt.remoteID!] {
                dto.apply(to: receipt)
            } else {
                context.delete(receipt)  // removed on another device
            }
        }

        let knownIDs = Set(locals.compactMap(\.remoteID))
        for dto in remote where !knownIDs.contains(dto.id) {
            context.insert(dto.makeReceipt())
        }
        try? context.save()
    }

    // MARK: - Push

    /// Push a local receipt's current values to the account (after an edit).
    @MainActor
    static func pushUpdate(_ receipt: Receipt, auth: AuthManager) async {
        guard let id = receipt.remoteID, let client = await client(auth: auth) else { return }
        _ = try? await client.updateReceipt(
            id: id,
            body: ReceiptExtractionAPIClient.ReceiptWrite(from: receipt, includeImage: false)
        )
    }

    /// Delete locally and, if it's synced, on the account too.
    @MainActor
    static func delete(_ receipt: Receipt, auth: AuthManager, context: ModelContext) async {
        if let id = receipt.remoteID, let client = await client(auth: auth) {
            try? await client.deleteReceipt(id: id)
        }
        context.delete(receipt)
        try? context.save()
    }

    // MARK: - Helpers

    @MainActor
    private static func client(auth: AuthManager) async -> ReceiptExtractionAPIClient? {
        await ReceiptExtractionService.makeAuthorizedClient(auth: auth)
    }
}
