import Foundation

/// How a spending period is bucketed on the dashboard — mirrors the web
/// app's `lib/period.ts`, just expressed in `Calendar`/`Date` terms instead
/// of "YYYY-MM" strings.
enum Granularity: String, CaseIterable, Identifiable {
    case month, quarter, year

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// The interval (calendar month, quarter, or year) containing `date`.
    func interval(containing date: Date, calendar: Calendar) -> DateInterval? {
        switch self {
        case .month:
            return calendar.dateInterval(of: .month, for: date)
        case .year:
            return calendar.dateInterval(of: .year, for: date)
        case .quarter:
            guard let yearStart = calendar.dateInterval(of: .year, for: date)?.start else { return nil }
            let month = calendar.component(.month, from: date) // 1...12
            let quarterIndex = (month - 1) / 3 // 0...3
            guard let start = calendar.date(byAdding: .month, value: quarterIndex * 3, to: yearStart),
                let end = calendar.date(byAdding: .month, value: 3, to: start)
            else { return nil }
            return DateInterval(start: start, end: end)
        }
    }

    /// Move `date` one whole period forward (positive) or back (negative).
    func shift(_ date: Date, by amount: Int, calendar: Calendar) -> Date {
        let months = self == .quarter ? amount * 3 : amount
        let component: Calendar.Component = self == .year ? .year : .month
        let value = self == .year ? amount : months
        return calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    /// Human header label, e.g. "September 2026" / "Q3 2026" / "2026".
    func periodLabel(for date: Date, calendar: Calendar) -> String {
        switch self {
        case .month:
            return date.formatted(.dateTime.month(.wide).year())
        case .quarter:
            let month = calendar.component(.month, from: date)
            let year = calendar.component(.year, from: date)
            return "Q\((month - 1) / 3 + 1) \(year)"
        case .year:
            return String(calendar.component(.year, from: date))
        }
    }

    /// Short chart-axis label, e.g. "Sep" / "Q3 '26" / "2026".
    func chartLabel(for date: Date, calendar: Calendar) -> String {
        switch self {
        case .month:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = .current
            formatter.dateFormat = "MMM"
            return formatter.string(from: date)
        case .quarter:
            let month = calendar.component(.month, from: date)
            let year = calendar.component(.year, from: date) % 100
            return "Q\((month - 1) / 3 + 1) '\(String(format: "%02d", year))"
        case .year:
            return String(calendar.component(.year, from: date))
        }
    }

    /// A stable key for comparing periods regardless of the exact anchor
    /// date used to reach them (e.g. "is the viewed quarter the current one").
    func key(for date: Date, calendar: Calendar) -> DateComponents {
        switch self {
        case .month: return calendar.dateComponents([.year, .month], from: date)
        case .quarter:
            let month = calendar.component(.month, from: date)
            var c = calendar.dateComponents([.year], from: date)
            c.month = (month - 1) / 3
            return c
        case .year: return calendar.dateComponents([.year], from: date)
        }
    }
}
