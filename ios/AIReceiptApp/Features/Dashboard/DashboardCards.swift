import SwiftUI
import Charts

private let cardBackground = Color(.secondarySystemBackground)
private let cardShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

struct MonthlyTotalCard: View {
    let amount: Decimal
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This month")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(amount, format: .currency(code: currencyCode))
                .font(.system(size: 34, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground, in: cardShape)
    }
}

struct CategoryBreakdownCard: View {
    let breakdown: [CategoryTotal]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By category").font(.headline)

            if breakdown.isEmpty {
                Text("No spending this month yet.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(breakdown) { entry in
                    BarMark(
                        x: .value("Amount", amount(entry.amount)),
                        y: .value("Category", entry.category.displayName)
                    )
                    .foregroundStyle(entry.category.tint)
                    .annotation(position: .trailing) {
                        Text(entry.amount, format: .currency(code: currencyCode))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(breakdown.count) * 34 + 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground, in: cardShape)
    }

    private func amount(_ decimal: Decimal) -> Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }
}

struct InsightsCard: View {
    let insights: [Insight]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Insights", systemImage: "sparkles").font(.headline)

            if insights.isEmpty {
                Text("Keep scanning receipts — insights appear once there's a month of history to compare.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(insights) { insight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(for: insight.kind))
                            .foregroundStyle(color(for: insight.kind))
                        Text(insight.message).font(.subheadline)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground, in: cardShape)
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
        case .up: .red
        case .down: .green
        case .neutral: .secondary
        case .streak: .orange
        }
    }
}

struct RecentReceiptsCard: View {
    let receipts: [Receipt]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent").font(.headline)
            ForEach(receipts) { receipt in
                HStack(spacing: 12) {
                    Image(systemName: receipt.category.systemImage)
                        .foregroundStyle(receipt.category.tint)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(receipt.merchant)
                        Text(receipt.date, format: .dateTime.month().day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(receipt.total, format: .currency(code: currencyCode))
                        .fontWeight(.medium)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground, in: cardShape)
    }
}
