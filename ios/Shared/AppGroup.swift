import Foundation

/// The container the app shares with its widget and share extension.
enum AppGroup {
    static let id = "group.com.vipreshpatel.tally"

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    /// Receipts shared into Tally from other apps, waiting for the app to read them.
    static var inbox: URL? {
        guard let url = container?.appendingPathComponent("Inbox", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var snapshotURL: URL? { container?.appendingPathComponent("widget.json") }

    /// Budgets live on the server; the dashboard leaves this month's totals
    /// here for the widget (spent, limit).
    static var budgetTotals: (spent: Decimal, limit: Decimal)? {
        get {
            guard let d = UserDefaults(suiteName: id),
                  let spent = d.string(forKey: "budget.spent").flatMap({ Decimal(string: $0) }),
                  let limit = d.string(forKey: "budget.limit").flatMap({ Decimal(string: $0) }),
                  d.string(forKey: "budget.month") == Self.monthKey
            else { return nil }
            return (spent, limit)
        }
        set {
            let d = UserDefaults(suiteName: id)
            if let newValue, newValue.limit > 0 {
                d?.set("\(newValue.spent)", forKey: "budget.spent")
                d?.set("\(newValue.limit)", forKey: "budget.limit")
                d?.set(Self.monthKey, forKey: "budget.month")
            } else {
                d?.removeObject(forKey: "budget.limit")
            }
        }
    }

    private static var monthKey: String {
        let c = Calendar.current.dateComponents([.year, .month], from: .now)
        return "\(c.year ?? 0)-\(c.month ?? 0)"
    }
}

/// What the widget shows, written by the app whenever spending changes.
struct WidgetSnapshot: Codable {
    struct Category: Codable, Hashable {
        let name: String
        let amount: Decimal
        /// ExpenseCategory raw value, for its colour.
        let slug: String
    }

    var monthTotal: Decimal
    var previousMonthTotal: Decimal
    var monthLabel: String
    var currency: String
    var top: [Category]
    /// The next return deadline, e.g. "Best Buy · Fri".
    var nextReturn: String?
    var updated: Date
    /// This month across your budgets (nil = no budgets set).
    var budgetSpent: Decimal?
    var budgetLimit: Decimal?

    static let placeholder = WidgetSnapshot(
        monthTotal: 461.84, previousMonthTotal: 405.84, monthLabel: "November",
        currency: Locale.current.currency?.identifier ?? "USD",
        top: [
            .init(name: "Groceries", amount: 226.22, slug: "groceries"),
            .init(name: "Restaurants", amount: 108.72, slug: "restaurants"),
            .init(name: "Utilities", amount: 86.90, slug: "utilities"),
        ],
        nextReturn: nil, updated: .now, budgetSpent: 310, budgetLimit: 500
    )

    static func load() -> WidgetSnapshot? {
        guard let url = AppGroup.snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = AppGroup.snapshotURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
