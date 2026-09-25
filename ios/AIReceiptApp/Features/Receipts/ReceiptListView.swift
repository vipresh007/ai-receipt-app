import SwiftUI
import SwiftData

/// One calendar month's worth of receipts, newest month first — mirrors the
/// grouping on web's `/receipts` page.
private struct MonthGroup: Identifiable {
    let id: Date
    let label: String
    let items: [Receipt]
    let total: Decimal
}

private struct MonthSectionHeader: View {
    let group: MonthGroup
    let currencyCode: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(group.label)
                .font(.appHeadline)
                .foregroundStyle(Theme.Palette.text)
            Spacer()
            Text(group.total, format: .currency(code: currencyCode))
                .font(.mono(13, medium: true, relativeTo: .caption))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.top, Theme.Space.sm)
        .textCase(nil)
    }
}

struct ReceiptListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var auth
    @Environment(\.calendar) private var calendar
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]

    @State private var searchText = ""
    @State private var categoryFilter: ExpenseCategory?

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var recurringGroups: [RecurringGroup] {
        RecurringDetector.find(in: receipts, calendar: calendar)
    }

    /// All filters — search text and category — applied together. Recurring
    /// detection intentionally runs on the unfiltered list above.
    private var filteredReceipts: [Receipt] {
        receipts.filter { receipt in
            if let categoryFilter, receipt.category != categoryFilter { return false }
            guard !searchText.isEmpty else { return true }
            if receipt.merchant.localizedCaseInsensitiveContains(searchText) { return true }
            return receipt.items.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var monthGroups: [MonthGroup] {
        var buckets: [Date: [Receipt]] = [:]
        for receipt in filteredReceipts {
            let start = calendar.dateInterval(of: .month, for: receipt.date)?.start ?? receipt.date
            buckets[start, default: []].append(receipt)
        }
        return buckets.keys.sorted(by: >).map { start in
            let items = buckets[start] ?? []
            return MonthGroup(
                id: start,
                label: start.formatted(.dateTime.month(.wide).year()),
                items: items,
                total: items.reduce(Decimal(0)) { $0 + $1.total }
            )
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    categoryFilterChips
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                recurringSection
                monthSections
            }
            .listStyle(.plain)
            .ledgerBackground()
            .overlay { emptyOverlay }
            .navigationTitle("Receipts")
            // Inline — a safeAreaInset chip row fought with the large title
            // and .searchable's own layout (it left a large blank gap and
            // the title never drew). Inline sidesteps that combination.
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search merchants or items")
            .toolbar { toolbarContent }
            .refreshable {
                await AccountSync.pull(auth: auth, context: modelContext)
            }
        }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if receipts.isEmpty {
            ContentUnavailableView(
                "No receipts",
                systemImage: "list.bullet.rectangle",
                description: Text("Scanned receipts show up here.")
            )
        } else if monthGroups.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !receipts.isEmpty {
            ToolbarItem {
                EditButton()
            }
        }
    }

    @ViewBuilder
    private var recurringSection: some View {
        if !recurringGroups.isEmpty, searchText.isEmpty, categoryFilter == nil {
            Section {
                NavigationLink {
                    RecurringListView(groups: recurringGroups, currencyCode: currencyCode)
                } label: {
                    RecurringSummaryRow(groups: recurringGroups, currencyCode: currencyCode)
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var monthSections: some View {
        ForEach(monthGroups) { group in
            Section {
                ForEach(group.items) { receipt in
                    NavigationLink {
                        ReceiptDetailView(receipt: receipt)
                    } label: {
                        ReceiptRow(receipt: receipt, currencyCode: currencyCode)
                    }
                }
                .onDelete { delete(group.items, at: $0) }
                .listRowBackground(Color.clear)
            } header: {
                MonthSectionHeader(group: group, currencyCode: currencyCode)
            }
        }
    }

    /// A horizontal row of category chips — kept out of the toolbar entirely
    /// (rather than a filter icon crowding the title bar), as the first row
    /// of the list itself so it scrolls with everything else.
    private var categoryFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                FilterChip(title: "All", isSelected: categoryFilter == nil) {
                    categoryFilter = nil
                }
                ForEach(ExpenseCategory.allCases) { category in
                    FilterChip(title: category.displayName, isSelected: categoryFilter == category) {
                        categoryFilter = categoryFilter == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.sm)
        }
    }

    private func delete(_ items: [Receipt], at offsets: IndexSet) {
        let targets = offsets.map { items[$0] }
        Task {
            for receipt in targets {
                await AccountSync.delete(receipt, auth: auth, context: modelContext)
            }
        }
    }
}

private struct RecurringSummaryRow: View {
    let groups: [RecurringGroup]
    let currencyCode: String

    private var monthlyTotal: Decimal {
        groups.reduce(Decimal(0)) { $0 + $1.averageAmount }
    }

    private var subtitle: String {
        let count = groups.count
        let noun = count == 1 ? "subscription" : "subscriptions"
        let amount = monthlyTotal.formatted(.currency(code: currencyCode))
        return "\(count) likely \(noun) · \(amount)/mo"
    }

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.Palette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Recurring")
                    .font(.appCallout.weight(.medium))
                    .foregroundStyle(Theme.Palette.text)
                Text(subtitle)
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.appCaption.weight(.medium))
                .foregroundStyle(isSelected ? Theme.Palette.accent : Theme.Palette.textSecondary)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.xs)
                .background(
                    isSelected ? Theme.Palette.accent.opacity(0.14) : Theme.Palette.surface2,
                    in: Capsule()
                )
                .overlay {
                    Capsule().strokeBorder(isSelected ? Theme.Palette.accent.opacity(0.4) : .clear)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct ReceiptRow: View {
    let receipt: Receipt
    let currencyCode: String

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            CategoryGlyph(category: receipt.category, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(receipt.merchant.isEmpty ? "Unknown merchant" : receipt.merchant)
                    .font(.appCallout.weight(.medium))
                    .foregroundStyle(Theme.Palette.text)
                Text(receipt.date, format: .dateTime.month().day().year())
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            Text(receipt.total, format: .currency(code: currencyCode))
                .font(.appMoney)
                .foregroundStyle(Theme.Palette.text)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ReceiptListView()
        .modelContainer(for: Receipt.self, inMemory: true)
        .environment(AuthManager())
}
