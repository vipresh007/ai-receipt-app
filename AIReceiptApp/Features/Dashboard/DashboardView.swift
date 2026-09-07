import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var summary: SpendingSummary {
        SpendingSummary(receipts: receipts)
    }

    var body: some View {
        NavigationStack {
            Group {
                if receipts.isEmpty {
                    ContentUnavailableView(
                        "No receipts yet",
                        systemImage: "doc.text.image",
                        description: Text("Scan your first receipt to start tracking spending.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            MonthlyTotalCard(amount: summary.currentMonthTotal, currencyCode: currencyCode)
                            CategoryBreakdownCard(breakdown: summary.currentMonthByCategory, currencyCode: currencyCode)
                            InsightsCard(insights: summary.insights)
                            RecentReceiptsCard(receipts: Array(receipts.prefix(5)), currencyCode: currencyCode)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Dashboard")
        }
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: Receipt.self, inMemory: true)
}
