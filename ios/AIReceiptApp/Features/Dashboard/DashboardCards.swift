import SwiftUI
import Charts

struct MonthlyTotalCard: View {
    let amount: Decimal
    let currencyCode: String

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionLabel("This month")
                Text(amount, format: .currency(code: currencyCode))
                    .font(.appDisplay)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.text)
            }
        }
    }
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
    let receipts: [Receipt]
    let currencyCode: String

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SectionLabel("Recent")
                ForEach(receipts) { receipt in
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
                    }
                }
            }
        }
    }
}
