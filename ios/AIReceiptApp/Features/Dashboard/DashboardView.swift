import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]

    /// A date inside the period currently being viewed.
    @State private var anchor: Date = .now
    @State private var granularity: Granularity = .month

    private let calendar = Calendar.current

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var summary: SpendingSummary {
        SpendingSummary(receipts: receipts, calendar: calendar, now: anchor, granularity: granularity)
    }

    private var periodReceipts: [Receipt] {
        guard let interval = granularity.interval(containing: anchor, calendar: calendar) else { return [] }
        return receipts.filter { interval.contains($0.date) }
    }

    private var periodStart: Date {
        granularity.interval(containing: anchor, calendar: calendar)?.start ?? anchor
    }

    private var previousPeriodLabel: String {
        let previousAnchor = granularity.shift(anchor, by: -1, calendar: calendar)
        switch granularity {
        case .month: return previousAnchor.formatted(.dateTime.month(.abbreviated))
        case .quarter: return granularity.periodLabel(for: previousAnchor, calendar: calendar)
        case .year: return String(calendar.component(.year, from: previousAnchor))
        }
    }

    private var trendPeriods: Int {
        switch granularity {
        case .month: return 6
        case .quarter: return 6
        case .year: return 5
        }
    }

    private var trendPoints: [MonthlyPoint] {
        SpendingSummary.periodTrend(
            receipts: receipts, calendar: calendar, now: anchor, granularity: granularity, periods: trendPeriods
        )
    }

    /// Move the dashboard to whatever period contains `date`, switching
    /// granularity too if given (e.g. tapping a month row in "All months"
    /// always means month granularity).
    private func jump(to date: Date, granularity newGranularity: Granularity? = nil) {
        withAnimation(Theme.Motion.base) {
            if let newGranularity { granularity = newGranularity }
            anchor = date
        }
    }

    private var isCurrentPeriod: Bool {
        granularity.key(for: anchor, calendar: calendar) == granularity.key(for: .now, calendar: calendar)
    }

    private var periodLabel: String {
        isCurrentPeriod ? "This \(granularity.rawValue)" : granularity.periodLabel(for: anchor, calendar: calendar)
    }

    private var canGoForward: Bool { !isCurrentPeriod }

    private var canGoBack: Bool {
        guard let earliest = receipts.map(\.date).min(),
            let earliestStart = granularity.interval(containing: earliest, calendar: calendar)?.start
        else { return false }
        return periodStart > earliestStart
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
                            granularityPicker
                            periodSwitcher
                            MonthlyTotalCard(
                                label: periodLabel,
                                amount: summary.currentMonthTotal,
                                currencyCode: currencyCode,
                                previous: (summary.previousMonthTotal, previousPeriodLabel)
                            )
                            NavigationLink {
                                MonthlyHistoryView(
                                    months: SpendingSummary.allMonths(
                                        receipts: receipts, calendar: calendar
                                    ),
                                    currencyCode: currencyCode,
                                    onSelect: { jump(to: $0, granularity: .month) },
                                    chartPoints: SpendingSummary.periodTrend(
                                        receipts: receipts, calendar: calendar, now: .now,
                                        granularity: .month, periods: 12
                                    )
                                )
                            } label: {
                                SpendingTrendCard(
                                    points: trendPoints,
                                    highlighted: periodStart,
                                    currencyCode: currencyCode,
                                    periodNoun: granularity == .month ? "months" : "\(granularity.rawValue)s"
                                )
                            }
                            .buttonStyle(.plain)

                            CategoryBreakdownCard(
                                breakdown: summary.currentMonthByCategory,
                                currencyCode: currencyCode
                            )
                            if granularity == .month {
                                InsightsCard(insights: summary.insights)
                            }
                            RecentReceiptsCard(
                                title: isCurrentPeriod ? "Recent" : "Receipts",
                                receipts: Array(periodReceipts.prefix(8)),
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

    private var granularityPicker: some View {
        Picker("Granularity", selection: $granularity) {
            ForEach(Granularity.allCases) { g in
                Text(g.label).tag(g)
            }
        }
        .pickerStyle(.segmented)
    }

    private var periodSwitcher: some View {
        HStack {
            Button {
                withAnimation(Theme.Motion.base) { anchor = granularity.shift(anchor, by: -1, calendar: calendar) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!canGoBack)

            Spacer()
            Text(granularity.periodLabel(for: anchor, calendar: calendar))
                .font(.appHeadline)
                .foregroundStyle(Theme.Palette.text)
                .contentTransition(.numericText())
            Spacer()

            Button {
                withAnimation(Theme.Motion.base) { anchor = granularity.shift(anchor, by: 1, calendar: calendar) }
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
