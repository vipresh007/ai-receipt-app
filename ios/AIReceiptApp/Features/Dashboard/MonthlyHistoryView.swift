import SwiftUI

/// Full month-by-month spending history: every month with a total and how it
/// moved from the month before. Tap a month to open it on the dashboard.
struct MonthlyHistoryView: View {
    let months: [MonthlyPoint]
    let currencyCode: String
    var onSelect: (Date) -> Void
    /// Zero-filled last-12-months points for the chart — `months` itself only
    /// lists months that actually have spending, which leaves gaps.
    var chartPoints: [MonthlyPoint] = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if !chartPoints.isEmpty {
                Section {
                    AppCard {
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            SectionLabel("Last \(chartPoints.count) months")
                            SpendingBarChart(
                                points: chartPoints,
                                highlighted: chartPoints.last?.monthStart ?? .now,
                                currencyCode: currencyCode
                            )
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                    Button {
                        onSelect(month.monthStart)
                        dismiss()
                    } label: {
                        row(month, previous: months[safe: index + 1])
                    }
                }
            }
        }
        .navigationTitle("Months")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if months.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "calendar",
                    description: Text("Months show up here as you add spending.")
                )
            }
        }
    }

    private func row(_ month: MonthlyPoint, previous: MonthlyPoint?) -> some View {
        HStack(spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(month.label)
                    .font(.appCallout.weight(.medium))
                    .foregroundStyle(Theme.Palette.text)
                if let delta = delta(month, previous) {
                    Label {
                        Text(delta.text)
                    } icon: {
                        Image(systemName: delta.up ? "arrow.up.right" : "arrow.down.right")
                    }
                    .font(.appCaption)
                    .foregroundStyle(delta.up ? Theme.Palette.danger : Theme.Palette.success)
                }
            }
            Spacer()
            Text(month.total, format: .currency(code: currencyCode))
                .font(.appMoney)
                .foregroundStyle(Theme.Palette.text)
            Image(systemName: "chevron.right")
                .font(.appCaption.weight(.semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .contentShape(Rectangle())
    }

    private func delta(_ month: MonthlyPoint, _ previous: MonthlyPoint?)
        -> (text: String, up: Bool)?
    {
        guard let previous, previous.total > 0 else { return nil }
        let change = month.total - previous.total
        guard change != 0 else { return nil }
        let up = change > 0
        let pct = NSDecimalNumber(decimal: abs(change) / previous.total * 100).intValue
        let amount = abs(change).formatted(.currency(code: currencyCode))
        return ("\(up ? "+" : "−")\(amount) · \(pct)% \(up ? "more" : "less")", up)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
