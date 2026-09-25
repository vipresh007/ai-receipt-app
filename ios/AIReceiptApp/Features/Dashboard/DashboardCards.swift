import SwiftUI
import Charts

// MARK: - Hero

/// The one loud moment on the dashboard: the period's total, how it compares
/// with the period before, two supporting figures, and the trend it sits in —
/// on the always-ink hero panel (matches the web's `PeriodHero`).
struct PeriodHeroCard: View {
    let label: String
    let amount: Decimal
    let currencyCode: String
    /// Positive = spent more than the comparison period. Nil hides the chip.
    var delta: Decimal?
    /// "the month before" / "the quarter before" / "the year before".
    var against: String = "the month before"
    let figures: [(label: String, value: String)]
    let points: [MonthlyPoint]
    let highlighted: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(label, color: Theme.Palette.gold)

            amountText
                .padding(.top, Theme.Space.sm)

            if let delta, delta != 0 {
                let up = delta > 0
                HStack(spacing: 5) {
                    Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                    Text("\(abs(delta).formatted(.currency(code: currencyCode))) \(up ? "more" : "less") than \(against)")
                }
                .font(.appCaption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(up ? Theme.Palette.amber : Theme.Palette.teal)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, 6)
                .background(Theme.Palette.heroChipBackground, in: Capsule())
                .padding(.top, Theme.Space.md)
            }

            HStack(alignment: .top, spacing: Theme.Space.lg) {
                ForEach(figures, id: \.label) { figure in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(figure.label.uppercased())
                            .font(.mono(10, medium: true, relativeTo: .caption2))
                            .tracking(1.4)
                            .foregroundStyle(Theme.Palette.heroTextSecondary)
                        Text(figure.value)
                            .font(.mono(15, relativeTo: .callout))
                            .foregroundStyle(Theme.Palette.heroText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, Theme.Space.lg)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.Palette.heroRule).frame(height: 1)
            }
            .padding(.top, Theme.Space.xl)

            if points.count > 1 {
                SpendingBarChart(
                    points: points,
                    highlighted: highlighted,
                    currencyCode: currencyCode,
                    tone: .hero,
                    height: 150
                )
                .padding(.top, Theme.Space.xl)
            }
        }
        .padding(Theme.Space.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeroPanelBackground())
    }

    /// Whole units in the display face, cents dimmed.
    private var amountText: some View {
        let formatted = amount.formatted(.currency(code: currencyCode))
        let separator = Locale.current.decimalSeparator ?? "."
        let parts: (whole: String, cents: String) = {
            guard let range = formatted.range(of: separator, options: .backwards) else { return (formatted, "") }
            return (String(formatted[..<range.lowerBound]), String(formatted[range.lowerBound...]))
        }()
        return (Text(parts.whole).foregroundColor(Theme.Palette.heroText)
            + Text(parts.cents).foregroundColor(Theme.Palette.heroText.opacity(0.4)))
            .font(.display(52))
            .tracking(-1.5)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
            .accessibilityLabel(formatted)
    }
}

// MARK: - Trend chart

/// The trend chart — used inside the hero panel (`.hero`: gold on ink,
/// regardless of light/dark) and on the "All months" screen (`.standard`:
/// follows the theme).
///
/// Scrubbable: dragging across the plot shows that period's value, via
/// `chartXSelection` (iOS 17+). While nothing is being touched, it falls back
/// to `highlighted`.
struct SpendingBarChart: View {
    enum Tone { case standard, hero }

    let points: [MonthlyPoint]
    /// The period (its start date) currently being viewed.
    let highlighted: Date
    let currencyCode: String
    var tone: Tone = .standard
    var height: CGFloat = 150

    /// The x-axis is categorical (`point.label`), so that's the value type
    /// `chartXSelection` hands back.
    @State private var selectedLabel: String?

    private var line: Color { tone == .hero ? Theme.Palette.gold : Theme.Palette.accent }
    private var tick: Color { tone == .hero ? Theme.Palette.heroTextSecondary : Theme.Palette.textTertiary }
    private var grid: Color { tone == .hero ? Theme.Palette.heroRule : Theme.Palette.border }
    private var calloutFill: Color { tone == .hero ? Theme.Palette.heroText : Theme.Palette.text }
    private var calloutText: Color { tone == .hero ? Theme.Palette.heroInkTop : Theme.Palette.surface }

    private var maxTotal: Double {
        points.map { ($0.total as NSDecimalNumber).doubleValue }.max() ?? 0
    }

    private var activePoint: MonthlyPoint? {
        if let selectedLabel, let match = points.first(where: { $0.label == selectedLabel }) {
            return match
        }
        return points.first(where: { $0.monthStart == highlighted })
    }

    var body: some View {
        Chart(points) { point in
            let value = (point.total as NSDecimalNumber).doubleValue

            AreaMark(x: .value("Period", point.label), y: .value("Spent", value))
                .foregroundStyle(
                    LinearGradient(
                        colors: [line.opacity(0.34), line.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

            LineMark(x: .value("Period", point.label), y: .value("Spent", value))
                .foregroundStyle(line)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)

            if point.id == activePoint?.id {
                RuleMark(x: .value("Period", point.label))
                    .foregroundStyle(tick.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                PointMark(x: .value("Period", point.label), y: .value("Spent", value))
                    .foregroundStyle(line)
                    .symbolSize(80)
                    .annotation(position: .top, spacing: 6) {
                        Text(compactMoney(point.total, code: currencyCode))
                            .font(.mono(11, medium: true, relativeTo: .caption))
                            .foregroundStyle(calloutText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(calloutFill, in: Capsule())
                    }
            }
        }
        .chartYScale(domain: 0...(maxTotal * 1.3 + 1))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 5])).foregroundStyle(grid)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(compactMoney(Decimal(v), code: currencyCode))
                            .font(.mono(10, relativeTo: .caption2))
                            .foregroundStyle(tick)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        let active = label == activePoint?.label
                        Text(label)
                            .font(.mono(10, medium: active, relativeTo: .caption2))
                            .foregroundStyle(active ? (tone == .hero ? Theme.Palette.heroText : Theme.Palette.text) : tick)
                    }
                }
            }
        }
        .frame(height: height)
        .chartXSelection(value: $selectedLabel)
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

// MARK: - Where it went

/// Where the period's money went: one proportional bar across the top, then a
/// ranked list of categories with each one's share and total (matches the
/// web's `CategoryBreakdown`).
struct CategoryBreakdownCard<Accessory: View>: View {
    let breakdown: [CategoryTotal]
    let currencyCode: String
    /// Trailing header control, e.g. an "All months" link.
    @ViewBuilder var accessory: () -> Accessory

    private var rows: [CategoryTotal] { breakdown.filter { $0.amount > 0 } }
    private var total: Decimal { rows.reduce(0) { $0 + $1.amount } }

    private func share(_ entry: CategoryTotal) -> Double {
        guard total > 0 else { return 0 }
        return NSDecimalNumber(decimal: entry.amount / total).doubleValue
    }

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                HStack {
                    SectionLabel("Where it went")
                    Spacer()
                    accessory()
                }

                if rows.isEmpty {
                    Text("No spending in this period yet.")
                        .font(.appCallout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    proportionBar
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Divider().overlay(Theme.Palette.border) }
                            row(entry)
                        }
                    }
                }
            }
        }
    }

    private var proportionBar: some View {
        GeometryReader { geo in
            let gap: CGFloat = 3
            let usable = geo.size.width - gap * CGFloat(max(rows.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(rows) { entry in
                    Rectangle()
                        .fill(entry.category.tint)
                        .frame(width: max(usable * share(entry), 2))
                }
            }
        }
        .frame(height: 12)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel(
            rows.map { "\($0.category.displayName) \(Int((share($0) * 100).rounded())) percent" }.joined(separator: ", ")
        )
    }

    private func row(_ entry: CategoryTotal) -> some View {
        let pct = share(entry)
        return HStack(spacing: Theme.Space.md) {
            CategoryGlyph(category: entry.category, size: 36)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.category.displayName)
                        .font(.appCallout.weight(.medium))
                        .foregroundStyle(Theme.Palette.text)
                    Spacer()
                    Text(entry.amount, format: .currency(code: currencyCode))
                        .font(.appMoney)
                        .foregroundStyle(Theme.Palette.text)
                }
                HStack(spacing: Theme.Space.sm) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.Palette.surface2)
                            Capsule().fill(entry.category.tint).frame(width: geo.size.width * pct)
                        }
                    }
                    .frame(height: 4)
                    Text(pct < 0.01 ? "<1%" : "\(Int((pct * 100).rounded()))%")
                        .font(.mono(11, relativeTo: .caption2))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, Theme.Space.md)
    }
}

// MARK: - Budgets

/// Top few budgets by usage, for the dashboard — full management lives on
/// the Budgets tab. `BudgetRow` is the same one that tab uses.
struct BudgetsSummaryCard: View {
    let budgets: [ReceiptExtractionAPIClient.BudgetDTO]
    /// Jumps to the Budgets tab — matches web's "Manage →" link.
    var onManage: () -> Void = {}

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                HStack {
                    SectionLabel("Budgets")
                    Spacer()
                    Button(action: onManage) {
                        CardLinkLabel(title: "Manage")
                    }
                }
                VStack(spacing: Theme.Space.sm) {
                    ForEach(Array(budgets.prefix(3).enumerated()), id: \.element.id) { index, budget in
                        if index > 0 { Divider().overlay(Theme.Palette.border) }
                        BudgetRow(budget: budget)
                    }
                }
            }
        }
    }
}

/// "Manage →" / "All months →" — the small trailing link in a card header.
struct CardLinkLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
        }
        .font(.appCaption.weight(.medium))
        .foregroundStyle(Theme.Palette.textSecondary)
    }
}

// MARK: - Insights

struct InsightsCard: View {
    let insights: [Insight]

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                SectionLabel("Insights")

                VStack(spacing: 0) {
                    ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                        if index > 0 { Divider().overlay(Theme.Palette.border) }
                        HStack(alignment: .top, spacing: Theme.Space.md) {
                            Image(systemName: icon(for: insight.kind))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(color(for: insight.kind))
                                .frame(width: 28, height: 28)
                                .background(color(for: insight.kind).opacity(0.14), in: Circle())
                            Text(insight.message)
                                .font(.appCallout)
                                .foregroundStyle(Theme.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                        .padding(.vertical, Theme.Space.md)
                    }
                }
            }
        }
    }

    private func icon(for kind: Insight.Kind) -> String {
        switch kind {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .neutral: "info"
        case .streak: "flame.fill"
        case .summary: "chart.pie.fill"
        }
    }

    private func color(for kind: Insight.Kind) -> Color {
        switch kind {
        case .up: Theme.Palette.danger
        case .down: Theme.Palette.success
        case .neutral: Theme.Palette.textTertiary
        case .streak: Theme.Palette.warning
        case .summary: Theme.Palette.accent
        }
    }
}

// MARK: - Receipts

struct RecentReceiptsCard: View {
    var title = "Recent receipts"
    let receipts: [Receipt]
    let currencyCode: String

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SectionLabel(title)
                if receipts.isEmpty {
                    Text("No receipts in this period.")
                        .font(.appCallout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(receipts.enumerated()), id: \.element.id) { index, receipt in
                            if index > 0 { Divider().overlay(Theme.Palette.border) }
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
    }

    private func row(_ receipt: Receipt) -> some View {
        HStack(spacing: Theme.Space.md) {
            CategoryGlyph(category: receipt.category, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.merchant.isEmpty ? "Unknown merchant" : receipt.merchant)
                    .font(.appCallout.weight(.medium))
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
                Text("\(receipt.date.formatted(.dateTime.month(.abbreviated).day())) · \(receipt.category.displayName)")
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer()
            Text(receipt.total, format: .currency(code: currencyCode))
                .font(.appMoney)
                .foregroundStyle(Theme.Palette.text)
        }
        .padding(.vertical, Theme.Space.md)
        .contentShape(Rectangle())
    }
}
