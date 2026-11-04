import SwiftUI

/// One category (from the Dashboard's "Where it went"): its trend since its
/// first receipt, how the chosen period compares with the one before and its
/// usual spend, and that period's receipts. Tap a period on the chart to
/// switch to it.
struct CategoryDetailView: View {
    let category: ExpenseCategory
    let receipts: [Receipt]
    let granularity: Granularity
    let currencyCode: String
    /// Start of the period shown.
    @State var selected: Date

    private let calendar = Calendar.current

    private var inCategory: [Receipt] { receipts.filter { $0.category == category } }

    /// From the category's first period to now: no flat run of empty months
    /// before it started (at least 2 points, at most 12).
    private var chart: [MonthlyPoint] {
        guard let first = inCategory.map(\.date).min(),
              var cursor = granularity.interval(containing: first, calendar: calendar)?.start,
              let now = granularity.interval(containing: .now, calendar: calendar)?.start else { return [] }
        var count = 1
        while cursor < now, count < 12 {
            cursor = granularity.shift(cursor, by: 1, calendar: calendar)
            count += 1
        }
        return SpendingSummary.periodTrend(
            receipts: inCategory, calendar: calendar, now: .now, granularity: granularity, periods: max(count, 2)
        )
    }

    var body: some View {
        let numbers = SpendingSummary.categoryComparison(
            receipts: receipts, category: category, anchor: selected, granularity: granularity, calendar: calendar
        )
        let interval = granularity.interval(containing: selected, calendar: calendar)
        return PeriodReceiptsView(
            title: "\(category.displayName) · \(granularity.periodLabel(for: selected, calendar: calendar))",
            receipts: inCategory.filter { interval?.holds($0.date) ?? false },
            currencyCode: currencyCode,
            comparison: comparison(numbers.current, numbers.previous),
            figures: figures(numbers.previous, numbers.average),
            chart: chart,
            chartTitle: "\(category.displayName) by \(granularity.rawValue)",
            highlighted: selected,
            onSelectPeriod: { start in
                withAnimation(Theme.Motion.base) { selected = start }
            }
        )
    }

    private func money(_ value: Decimal) -> String { value.formatted(.currency(code: currencyCode)) }

    /// "$30.00 more than October" (same year), "than December 2025", "than Q3 2026".
    private func comparison(_ current: Decimal, _ previous: Decimal) -> (text: String, up: Bool)? {
        guard previous > 0, current != previous else { return nil }
        let start = granularity.shift(selected, by: -1, calendar: calendar)
        let label = granularity == .month
            && calendar.component(.year, from: start) == calendar.component(.year, from: selected)
            ? start.formatted(.dateTime.month(.wide))
            : granularity.periodLabel(for: start, calendar: calendar)
        let up = current > previous
        return ("\(money(abs(current - previous))) \(up ? "more" : "less") than \(label)", up)
    }

    private func figures(_ previous: Decimal, _ average: Decimal?) -> [(label: String, value: String)] {
        var out = [("Previous \(granularity.rawValue)", money(previous))]
        if let average { out.append(("\(granularity.label)ly average", money(average))) }
        return out
    }
}
