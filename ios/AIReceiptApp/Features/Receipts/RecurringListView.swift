import SwiftUI

/// Detected recurring merchants — a no-bank-linking stand-in for a
/// subscription finder. See `RecurringDetector` for the heuristic.
struct RecurringListView: View {
    let groups: [RecurringGroup]
    let currencyCode: String

    private var monthlyTotal: Decimal {
        groups.reduce(Decimal(0)) { $0 + $1.averageAmount }
    }

    private func subtitle(for group: RecurringGroup) -> String {
        let last = group.lastPurchased.formatted(.dateTime.month(.abbreviated).day())
        return "\(group.occurrences) charges · last \(last)"
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Estimated monthly total")
                        .font(.appCallout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Spacer()
                    Text(monthlyTotal, format: .currency(code: currencyCode))
                        .font(.appMoney)
                }
                .listRowBackground(Theme.Palette.surface)
            }

            Section {
                ForEach(groups) { group in
                    HStack(spacing: Theme.Space.md) {
                        CategoryGlyph(category: group.category, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.merchant)
                                .font(.appCallout.weight(.medium))
                                .foregroundStyle(Theme.Palette.text)
                            Text(subtitle(for: group))
                                .font(.appCaption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        Spacer()
                        Text(group.averageAmount, format: .currency(code: currencyCode))
                            .font(.appMoney)
                            .foregroundStyle(Theme.Palette.text)
                    }
                    .padding(.vertical, 2)
                }
                .listRowBackground(Theme.Palette.surface)
            } header: {
                Text("Recurring merchants")
            } footer: {
                Text("Based on merchants that show up at a similar amount across two or more months in your own receipts.")
            }
        }
        .ledgerBackground()
        .navigationTitle("Recurring")
    }
}

#Preview {
    NavigationStack {
        RecurringListView(
            groups: [
                RecurringGroup(
                    merchant: "Netflix",
                    category: .entertainment,
                    averageAmount: 15.49,
                    occurrences: 3,
                    lastPurchased: .now
                )
            ],
            currencyCode: "USD"
        )
    }
}
