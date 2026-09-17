import SwiftUI
import Charts

/// A tiny inline trend line drawn straight from the same points as the trend
/// chart below it — decorative context for the hero number, not a
/// replacement for the real (labeled, tappable) `SpendingTrendCard`.
private struct HeroSparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = Swift.max(maxV - minV, 0.0001)
            let step = values.count > 1 ? w / CGFloat(values.count - 1) : 0
            let points = values.enumerated().map { i, v -> CGPoint in
                CGPoint(x: CGFloat(i) * step, y: h - CGFloat((v - minV) / range) * h)
            }

            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for p in points.dropFirst() { path.addLine(to: p) }
            }
            .stroke(Theme.Palette.gold, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            if let last = points.last {
                Circle().fill(Theme.Palette.gold).frame(width: 6, height: 6).position(last)
            }
        }
    }
}

/// The one gradient "moment" per screen — the current period's total. See
/// docs/DESIGN.md "The Ledger direction". Always this dark ink-to-teal
/// gradient regardless of light/dark mode; a secondary number (e.g. a
/// previous period elsewhere) should use a plain `AppCard`, never this.
struct HeroMetricCard: View {
    var label = "This month"
    let amount: Decimal
    let currencyCode: String
    /// Prior month's total + its name, for the "vs" line. Nil hides it.
    var previous: (amount: Decimal, label: String)?
    /// Recent period totals (oldest → newest) for the mini trend line. Fewer
    /// than 2 values hides it.
    var sparklineValues: [Double] = []

    private var delta: Decimal? {
        guard let previous, previous.amount > 0 else { return nil }
        return amount - previous.amount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(label.uppercased())
                .font(.appMicro)
                .tracking(0.5)
                .foregroundStyle(Theme.Palette.gold)
            Text(amount, format: .currency(code: currencyCode))
                .font(.appDisplay)
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.heroText)
                .contentTransition(.numericText())

            HStack(alignment: .center, spacing: Theme.Space.md) {
                if let delta, let previous {
                    let up = delta > 0
                    HStack(spacing: 3) {
                        Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                        Text(abs(delta), format: .currency(code: currencyCode))
                            .monospacedDigit()
                        Text("vs \(previous.label)")
                    }
                    .font(.appCaption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.heroText)
                    .padding(.horizontal, Theme.Space.sm)
                    .padding(.vertical, 5)
                    .background(Theme.Palette.heroChipBackground, in: Capsule())
                }
                Spacer(minLength: 0)
                if sparklineValues.count > 1 {
                    HeroSparkline(values: sparklineValues)
                        .frame(width: 110, height: 34)
                }
            }
            .padding(.top, 2)
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Theme.Palette.heroGradientStart, Theme.Palette.heroGradientMid, Theme.Palette.heroGradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
        )
        .shadow(color: Theme.Palette.heroGradientEnd.opacity(0.28), radius: 20, x: 0, y: 10)
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
            let isHighlighted = point.monthStart == highlighted

            AreaMark(x: .value("Period", point.label), y: .value("Spent", value))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Palette.accent.opacity(0.32), Theme.Palette.accent.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

            LineMark(x: .value("Period", point.label), y: .value("Spent", value))
                .foregroundStyle(Theme.Palette.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)

            if isHighlighted {
                PointMark(x: .value("Period", point.label), y: .value("Spent", value))
                    .foregroundStyle(Theme.Palette.accent)
                    .symbolSize(70)
                    .annotation(position: .top, spacing: 6) {
                        Text(compactMoney(point.total, code: currencyCode))
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.Palette.surface)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.Palette.text, in: Capsule())
                    }
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...(maxTotal * 1.3 + 1))
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
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: Theme.Space.md) {
                            ForEach(breakdown) { entry in
                                VStack(spacing: Theme.Space.xs) {
                                    CategoryGlyph(category: entry.category, size: 46)
                                    Text(entry.amount, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                                        .font(.appCaption.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.Palette.text)
                                    Text(entry.category.displayName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.Palette.textTertiary)
                                        .lineLimit(1)
                                }
                                .frame(width: 64)
                            }
                        }
                        .padding(.vertical, Theme.Space.xs)
                    }
                }
            }
        }
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
