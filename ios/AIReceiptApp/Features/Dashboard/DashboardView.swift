import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]

    /// 0 = current month, -1 = last month, …
    @State private var monthOffset = 0

    private let calendar = Calendar.current

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    /// A date inside the month currently being viewed.
    private var anchor: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: .now) ?? .now
    }

    private var summary: SpendingSummary {
        SpendingSummary(receipts: receipts, calendar: calendar, now: anchor)
    }

    private var monthReceipts: [Receipt] {
        guard let interval = calendar.dateInterval(of: .month, for: anchor) else { return [] }
        return receipts.filter { interval.contains($0.date) }
    }

    private var anchorMonthStart: Date {
        calendar.dateInterval(of: .month, for: anchor)?.start ?? anchor
    }

    private var previousMonthLabel: String {
        let prev = calendar.date(byAdding: .month, value: -1, to: anchor) ?? anchor
        return prev.formatted(.dateTime.month(.abbreviated))
    }

    private var trendPoints: [MonthlyPoint] {
        SpendingSummary.monthlyTrend(receipts: receipts, calendar: calendar, months: 6)
    }

    /// Move the dashboard to the month containing `date`.
    private func jump(toMonthContaining date: Date) {
        let currentStart = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let targetStart = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let months = calendar.dateComponents([.month], from: currentStart, to: targetStart).month ?? 0
        withAnimation(Theme.Motion.base) { monthOffset = min(0, months) }
    }

    private var monthLabel: String {
        monthOffset == 0 ? "This month" : anchor.formatted(.dateTime.month(.wide).year())
    }

    private var canGoForward: Bool { monthOffset < 0 }

    private var canGoBack: Bool {
        guard let earliest = receipts.map(\.date).min() else { return false }
        let earliestMonth = calendar.dateInterval(of: .month, for: earliest)?.start ?? earliest
        let viewedMonth = calendar.dateInterval(of: .month, for: anchor)?.start ?? anchor
        return viewedMonth > earliestMonth
    }

    var body: some View {
        NavigationStack {
            Group {
                if receipts.isEmpty {
                    ContentUnavailableView {
                        Label("No receipts yet", systemImage: "doc.text.image")
                    } description: {
                        Text("Scan your first receipt to start tracking spending.")
                    }
                } else {
                    ScrollView {
                        VStack(spacing: Theme.Space.xl) {
                            monthSwitcher
                            MonthlyTotalCard(
                                label: monthLabel,
                                amount: summary.currentMonthTotal,
                                currencyCode: currencyCode,
                                previous: (summary.previousMonthTotal, previousMonthLabel)
                            )
                            NavigationLink {
                                MonthlyHistoryView(
                                    months: SpendingSummary.allMonths(
                                        receipts: receipts, calendar: calendar
                                    ),
                                    currencyCode: currencyCode,
                                    onSelect: jump(toMonthContaining:)
                                )
                            } label: {
                                SpendingTrendCard(
                                    points: trendPoints,
                                    highlighted: anchorMonthStart,
                                    currencyCode: currencyCode
                                )
                            }
                            .buttonStyle(.plain)

                            CategoryBreakdownCard(
                                breakdown: summary.currentMonthByCategory,
                                currencyCode: currencyCode
                            )
                            InsightsCard(insights: summary.insights)
                            RecentReceiptsCard(
                                title: monthOffset == 0 ? "Recent" : "Receipts",
                                receipts: Array(monthReceipts.prefix(8)),
                                currencyCode: currencyCode
                            )
                        }
                        .padding(Theme.Space.lg)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.bg.ignoresSafeArea())
            .navigationTitle("Dashboard")
        }
    }

    private var monthSwitcher: some View {
        HStack {
            Button {
                withAnimation(Theme.Motion.base) { monthOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!canGoBack)

            Spacer()
            Text(anchor.formatted(.dateTime.month(.wide).year()))
                .font(.appHeadline)
                .foregroundStyle(Theme.Palette.text)
                .contentTransition(.numericText())
            Spacer()

            Button {
                withAnimation(Theme.Motion.base) { monthOffset += 1 }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!canGoForward)
        }
        .font(.appCallout.weight(.semibold))
        .foregroundStyle(Theme.Palette.accent)
        .padding(.horizontal, Theme.Space.xs)
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: Receipt.self, inMemory: true)
}
