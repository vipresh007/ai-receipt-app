import Foundation
import SwiftData
import WidgetKit

/// Keeps the home screen widget's numbers current (`Shared/AppGroup.swift`).
enum WidgetSync {
    @MainActor
    static func update(_ context: ModelContext) {
        let receipts = (try? context.fetch(FetchDescriptor<Receipt>())) ?? []
        let summary = SpendingSummary(receipts: receipts)
        let next = ComingUpCard.items(in: receipts).first { $0.isReturn }
        let snapshot = WidgetSnapshot(
            monthTotal: summary.currentMonthTotal,
            previousMonthTotal: summary.previousMonthTotal,
            monthLabel: Date.now.formatted(.dateTime.month(.wide)),
            currency: Locale.current.currency?.identifier ?? "USD",
            top: summary.currentMonthByCategory.prefix(3).map {
                .init(name: $0.category.displayName, amount: $0.amount, slug: $0.category.rawValue)
            },
            nextReturn: next.map { "\($0.receipt.merchant) · \($0.date.formatted(.dateTime.weekday(.abbreviated)))" },
            updated: .now
        )
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Photos and PDFs shared into Tally from other apps (the share extension
/// drops them in the App Group inbox); read one at a time on the Scan tab.
enum SharedInbox {
    static func next() -> URL? {
        guard let inbox = AppGroup.inbox,
              let files = try? FileManager.default.contentsOfDirectory(
                at: inbox, includingPropertiesForKeys: [.creationDateKey]
              )
        else { return nil }
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
    }
}
