import Foundation

struct CategoryTotal: Identifiable {
    var id: ExpenseCategory { category }
    let category: ExpenseCategory
    let amount: Decimal
}

struct Insight: Identifiable {
    enum Kind { case up, down, neutral, streak }
    let id = UUID()
    let kind: Kind
    let message: String
}

/// One month's total, for the month-to-month trend chart.
struct MonthlyPoint: Identifiable {
    let id = UUID()
    let monthStart: Date
    let total: Decimal
    /// Short month name, e.g. "Apr".
    let label: String
}

/// Derives everything the dashboard shows from the raw list of receipts.
/// Pure and deterministic so it's easy to unit-test.
struct SpendingSummary {
    let currentMonthTotal: Decimal
    let previousMonthTotal: Decimal
    let currentMonthByCategory: [CategoryTotal]
    let insights: [Insight]

    /// `granularity` defaults to `.month`, which reproduces the exact
    /// behavior this type always had — quarter/year are additive. Insights
    /// are a month-over-month concept, so they're empty outside `.month`
    /// (same call the web dashboard makes).
    init(
        receipts: [Receipt],
        calendar: Calendar = .current,
        now: Date = .now,
        granularity: Granularity = .month
    ) {
        let currentInterval = granularity.interval(containing: now, calendar: calendar)
        let previousAnchor = granularity.shift(now, by: -1, calendar: calendar)
        let previousInterval = granularity.interval(containing: previousAnchor, calendar: calendar)

        let current = receipts.filter { Self.contains(currentInterval, $0.date) }
        let previous = receipts.filter { Self.contains(previousInterval, $0.date) }

        currentMonthTotal = current.reduce(Decimal(0)) { $0 + $1.total }
        previousMonthTotal = previous.reduce(Decimal(0)) { $0 + $1.total }

        currentMonthByCategory = Self.totals(current)
            .map { CategoryTotal(category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }

        insights =
            granularity == .month
            ? Self.makeInsights(
                current: current,
                previous: previous,
                receipts: receipts,
                calendar: calendar,
                now: now
            ) : []
    }

    /// Total spend per period (month, quarter, or year) for the last
    /// `periods` periods, oldest first, zero-filled.
    static func periodTrend(
        receipts: [Receipt],
        calendar: Calendar = .current,
        now: Date = .now,
        granularity: Granularity,
        periods: Int
    ) -> [MonthlyPoint] {
        guard let thisPeriodStart = granularity.interval(containing: now, calendar: calendar)?.start else {
            return []
        }
        var starts: [Date] = []
        var cursor = thisPeriodStart
        for _ in 0..<max(1, periods) {
            starts.append(cursor)
            cursor = granularity.shift(cursor, by: -1, calendar: calendar)
        }
        starts.reverse()
        return starts.compactMap { start -> MonthlyPoint? in
            guard let interval = granularity.interval(containing: start, calendar: calendar) else { return nil }
            let total = receipts
                .filter { interval.contains($0.date) }
                .reduce(Decimal(0)) { $0 + $1.total }
            return MonthlyPoint(
                monthStart: interval.start,
                total: total,
                label: granularity.chartLabel(for: start, calendar: calendar)
            )
        }
    }

    /// Total spend per month for the last `months` months, oldest first,
    /// zero-filled. Independent of the currently-viewed month.
    static func monthlyTrend(
        receipts: [Receipt],
        calendar: Calendar = .current,
        now: Date = .now,
        months: Int = 6
    ) -> [MonthlyPoint] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.dateFormat = "MMM"

        let thisMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return (0..<max(1, months)).reversed().compactMap { offset -> MonthlyPoint? in
            guard let start = calendar.date(byAdding: .month, value: -offset, to: thisMonthStart),
                let interval = calendar.dateInterval(of: .month, for: start)
            else { return nil }
            let total = receipts
                .filter { interval.contains($0.date) }
                .reduce(Decimal(0)) { $0 + $1.total }
            return MonthlyPoint(monthStart: interval.start, total: total, label: formatter.string(from: start))
        }
    }

    /// Every month that has at least one receipt, newest first, with a
    /// "September 2026" style label. For the full month-by-month comparison list.
    static func allMonths(receipts: [Receipt], calendar: Calendar = .current) -> [MonthlyPoint] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.dateFormat = "MMMM yyyy"

        var buckets: [Date: Decimal] = [:]
        for receipt in receipts {
            guard let start = calendar.dateInterval(of: .month, for: receipt.date)?.start else { continue }
            buckets[start, default: 0] += receipt.total
        }
        return buckets
            .sorted { $0.key > $1.key }
            .map { MonthlyPoint(monthStart: $0.key, total: $0.value, label: formatter.string(from: $0.key)) }
    }

    // MARK: - Helpers

    private static func contains(_ interval: DateInterval?, _ date: Date) -> Bool {
        guard let interval else { return false }
        return interval.contains(date)
    }

    private static func totals(_ list: [Receipt]) -> [ExpenseCategory: Decimal] {
        var map: [ExpenseCategory: Decimal] = [:]
        for receipt in list {
            map[receipt.category, default: 0] += receipt.total
        }
        return map
    }

    private static func makeInsights(
        current: [Receipt],
        previous: [Receipt],
        receipts: [Receipt],
        calendar: Calendar,
        now: Date
    ) -> [Insight] {
        var insights: [Insight] = []

        let currentTotals = totals(current)
        let previousTotals = totals(previous)

        for (category, currentAmount) in currentTotals.sorted(by: { $0.value > $1.value }) {
            guard let previousAmount = previousTotals[category], previousAmount > 0 else { continue }
            let change = (currentAmount - previousAmount) / previousAmount
            let percent = NSDecimalNumber(decimal: change * 100).doubleValue
            guard abs(percent) >= 15 else { continue }

            let direction = percent > 0 ? "more" : "less"
            insights.append(
                Insight(
                    kind: percent > 0 ? .up : .down,
                    message: "You spent \(Int(abs(percent).rounded()))% \(direction) on \(category.displayName.lowercased()) than the month before."
                )
            )
            if insights.count >= 3 { break }
        }

        if let rising = risingCategory(receipts: receipts, calendar: calendar, now: now) {
            insights.append(
                Insight(
                    kind: .streak,
                    message: "Your \(rising.displayName.lowercased()) spending has increased three months in a row."
                )
            )
        }

        return insights
    }

    /// A category whose spending rose in each of the last three months.
    private static func risingCategory(receipts: [Receipt], calendar: Calendar, now: Date) -> ExpenseCategory? {
        func monthTotal(_ category: ExpenseCategory, monthsAgo: Int) -> Decimal {
            guard let base = calendar.date(byAdding: .month, value: -monthsAgo, to: now),
                  let interval = calendar.dateInterval(of: .month, for: base) else { return 0 }
            return receipts
                .filter { $0.category == category && interval.contains($0.date) }
                .reduce(Decimal(0)) { $0 + $1.total }
        }

        for category in ExpenseCategory.allCases {
            let thisMonth = monthTotal(category, monthsAgo: 0)
            let lastMonth = monthTotal(category, monthsAgo: 1)
            let twoMonthsAgo = monthTotal(category, monthsAgo: 2)
            if twoMonthsAgo > 0, lastMonth > twoMonthsAgo, thisMonth > lastMonth {
                return category
            }
        }
        return nil
    }
}
