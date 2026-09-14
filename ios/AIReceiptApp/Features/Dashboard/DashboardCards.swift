import SwiftUI
import Charts

struct MonthlyTotalCard: View {
    var label = "This month"
    let amount: Decimal
    let currencyCode: String
    /// Prior month's total + its name, for the "vs" line. Nil hides it.
    var previous: (amount: Decimal, label: String)?

    private var delta: Decimal? {
        guard let previous, previous.amount > 0 else { return nil }
        return amount - previous.amount
    }

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionLabel(label)
                Text(amount, format: .currency(code: currencyCode))
                    .font(.appDisplay)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.text)
                    .contentTransition(.numericText())

                if let delta, let previous {
                    let up = delta > 0
                    HStack(spacing: 3) {
                        Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                        Text(abs(delta), format: .currency(code: currencyCode))
                            .monospacedDigit()
                        Text("vs \(previous.label)")
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    .font(.appCaption)
                    .foregroundStyle(up ? Theme.Palette.danger : Theme.Palette.success)
                }
            }
        }
    }
}

/// Just the bar chart — no card chrome or "go to all months" affordance.
/// Reused by the dashboard's tappable trend card and by the standalone
/// history/months view.
struct SpendingBarChart: View {
    let points: [MonthlyPoint]
    /// The period (its start date) currently being viewed — drawn solid;
    /// others faded.
    let highlighted: Date
    let currencyCode: String

    private var maxTotal: Double {
        points.map { ($0.total as NSDecimalNumber).doubleValue }.max() ?? 0
    }

    var body: some View {
        Chart(points) { point in
            let value = (point.total as NSDecimalNumber).doubleValue
            BarMark(
                x: .value("Period", point.label),
                y: .value("Spent", value)
            )
            .foregroundStyle(
                point.monthStart == highlighted
                    ? Theme.Palette.accent
                    : Theme.Palette.accent.opacity(0.28)
            )
            .cornerRadius(4)
            .annotation(position: .top, spacing: 3) {
                if value > 0 {
                    Text(compactMoney(point.total, code: currencyCode))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...(maxTotal * 1.25 + 1))
        .frame(height: 150)
    }
}

struct SpendingTrendCard: View {
    let points: [MonthlyPoint]
    /// The period (its start date) currently being viewed — drawn solid.
    let highlighted: Date
    let currencyCode: String
    /// "months" / "quarters" / "years" — matches whatever granularity `points` was built with.
    var periodNoun = "months"

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    SectionLabel("Last \(points.count) \(periodNoun)")
                    Spacer()
                    Text("All months")
                        .font(.appCaption.weight(.medium))
                        .foregroundStyle(Theme.Palette.accent)
                    Image(systemName: "chevron.right")
                        .font(.appCaption.weight(.semibold))
                        .foregroundStyle(Theme.Palette.accent)
                }
                SpendingBarChart(points: points, highlighted: highlighted, currencyCode: currencyCode)
            }
        }
    }
}

/// "$2k" / "$1.5k" / "$320" — tight labels for chart annotations.
func compactMoney(_ amount: Decimal, code: String) -> String {
    let value = (amount as NSDecimalNumber).doubleValue
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = code
    formatter.maximumFractionDigits = 0
    if value >= 1000 {
        formatter.maximumFractionDigits = value >= 10000 ? 0 : 1
        let scaled = NSNumber(value: value / 1000)
        return (formatter.string(from: scaled) ?? "\(Int(value / 1000))") + "k"
    }
    return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
}

struct CategoryBreakdownCard: View {
    let breakdown: [CategoryTotal]
    let currencyCode: String

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SectionLabel("By category")

                if breakdown.isEmpty {
                    Text("No spending this month yet.")
                        .font(.appCallout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    Chart(breakdown) { entry in
                        BarMark(
                            x: .value("Amount", amount(entry.amount)),
                            y: .value("Category", entry.category.displayName)
                        )
                        .foregroundStyle(entry.category.tint)
                        .cornerRadius(4)
                        .annotation(position: .trailing) {
                            Text(entry.amount, format: .currency(code: currencyCode))
                                .font(.appCaption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(breakdown.count) * 36 + 8)
                }
            }
        }
    }

    private func amount(_ decimal: Decimal) -> Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }
}

/// Top few budgets by usage, for the dashboard — full management lives on
/// the Budgets tab. `BudgetRow` is the same one that tab uses.
struct BudgetsSummaryCard: View {
    let budgets: [ReceiptExtractionAPIClient.BudgetDTO]
    /// Jumps to the Budgets tab — matches web's "Manage →" link.
    var onManage: () -> Void = {}

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack {
                    SectionLabel("Budgets")
                    Spacer()
                    Button(action: onManage) {
                        HStack(spacing: 3) {
                            Text("Manage")
                            Image(systemName: "chevron.right")
                                .font(.appCaption.weight(.semibold))
                        }
                        .font(.appCaption.weight(.medium))
                        .foregroundStyle(Theme.Palette.accent)
                    }
                }
                VStack(spacing: Theme.Space.sm) {
                    ForEach(Array(budgets.prefix(3).enumerated()), id: \.element.id) { index, budget in
                        if index > 0 { Divider() }
                        BudgetRow(budget: budget)
                    }
                }
            }
        }
    }
}

struct InsightsCard: View {
    let insights: [Insight]

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "sparkles")
                    SectionLabel("Insights")
                }
                .foregroundStyle(Theme.Palette.textTertiary)

                if insights.isEmpty {
                    Text("Keep scanning receipts — insights appear once there's a month of history to compare.")
                        .font(.appCallout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    ForEach(insights) { insight in
                        HStack(alignment: .top, spacing: Theme.Space.sm) {
                            Image(systemName: icon(for: insight.kind))
                                .font(.appCaption)
                                .foregroundStyle(color(for: insight.kind))
                                .padding(.top, 2)
                            Text(insight.message)
                                .font(.appCallout)
                                .foregroundStyle(Theme.Palette.text)
                        }
                    }
                }
            }
        }
    }

    private func icon(for kind: Insight.Kind) -> String {
        switch kind {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .neutral: "equal"
        case .streak: "flame.fill"
        }
    }

    private func color(for kind: Insight.Kind) -> Color {
        switch kind {
        case .up: Theme.Palette.danger
        case .down: Theme.Palette.success
        case .neutral: Theme.Palette.textTertiary
        case .streak: Theme.Palette.warning
        }
    }
}

struct RecentReceiptsCard: View {
    var title = "Recent"
    let receipts: [Receipt]
    let currencyCode: String

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SectionLabel(title)
                if receipts.isEmpty {
                    Text("No receipts this month.")
                        .font(.appCallout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    ForEach(receipts) { receipt in
                        NavigationLink {
                            ReceiptDetailView(receipt: receipt)
                        } label: {
                            row(receipt)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row(_ receipt: Receipt) -> some View {
        HStack(spacing: Theme.Space.md) {
            CategoryGlyph(category: receipt.category, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(receipt.merchant.isEmpty ? "Unknown merchant" : receipt.merchant)
                    .font(.appCallout)
                    .foregroundStyle(Theme.Palette.text)
                Text(receipt.date, format: .dateTime.month().day())
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            Text(receipt.total, format: .currency(code: currencyCode))
                .font(.appCallout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.text)
            Image(systemName: "chevron.right")
                .font(.appCaption.weight(.semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .contentShape(Rectangle())
    }
}
