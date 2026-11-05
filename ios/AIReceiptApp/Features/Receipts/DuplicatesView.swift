import SwiftData
import SwiftUI

/// Receipts that look like the same one added twice (same store, day and
/// total), for a one-time cleanup. Swipe one away to keep the other: it takes
/// a photo or items only the removed copy had.
struct DuplicatesView: View {
    let currencyCode: String

    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]

    private var groups: [[Receipt]] { DuplicateFinder.groups(in: receipts) }

    var body: some View {
        let groups = groups
        List {
            Section {
                Text("Same store, same day, same total. If it's the same receipt twice, swipe one away: the other keeps its photo and items.")
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .listRowBackground(Color.clear)

            ForEach(groups, id: \.first!.persistentModelID) { group in
                Section {
                    ForEach(group) { receipt in
                        NavigationLink {
                            ReceiptDetailView(receipt: receipt)
                        } label: {
                            row(receipt)
                        }
                        .swipeActions {
                            Button("Remove copy", role: .destructive) { remove(receipt, from: group) }
                        }
                    }
                } header: {
                    Text(header(group[0]))
                        .textCase(nil)
                }
                .listRowBackground(Theme.Palette.surface)
            }
        }
        .ledgerBackground()
        .navigationTitle("Possible duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView(
                    "No duplicates",
                    systemImage: "checkmark.circle",
                    description: Text("Every receipt is in here once.")
                )
            }
        }
    }

    private func header(_ r: Receipt) -> String {
        "\(r.merchant.isEmpty ? "A receipt" : r.merchant) · "
            + "\(r.date.formatted(.dateTime.month(.abbreviated).day().year())) · "
            + r.total.formatted(.currency(code: currencyCode))
    }

    private func row(_ r: Receipt) -> some View {
        let details = [
            r.imageData != nil ? "photo" : nil,
            r.items.isEmpty ? nil : "\(r.items.count) \(r.items.count == 1 ? "item" : "items")",
        ].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 2) {
            Text(r.merchant.isEmpty ? "A receipt" : r.merchant)
                .font(.appCallout.weight(.medium))
                .foregroundStyle(Theme.Palette.text)
            Text((["Added \(r.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"] + details)
                .joined(separator: " · "))
                .font(.appCaption)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(.vertical, 2)
    }

    private func remove(_ copy: Receipt, from group: [Receipt]) {
        guard let keep = group.first(where: { $0 !== copy }) else { return }
        let auth = auth
        let context = modelContext
        Task { await AccountSync.merge(copy, into: keep, auth: auth, context: context) }
    }
}

/// "Possible duplicates · 2", on the Receipts tab.
struct DuplicatesSummaryRow: View {
    let count: Int

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: "doc.on.doc.fill")
                .font(.title3)
                .foregroundStyle(Theme.Palette.warning)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Possible duplicates")
                    .font(.appCallout.weight(.medium))
                    .foregroundStyle(Theme.Palette.text)
                Text(count == 1 ? "1 receipt may be in here twice" : "\(count) receipts may be in here twice")
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}
