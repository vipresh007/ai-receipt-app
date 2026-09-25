import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(TabRouter.self) private var router
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]

    /// A date inside the period currently being viewed.
    @State private var anchor: Date = .now
    @State private var granularity: Granularity = .month
    @State private var budgets: [ReceiptExtractionAPIClient.BudgetDTO] = []

    private let calendar = Calendar.current

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

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

    private var periodMonthString: String {
        Self.monthFormatter.string(from: periodStart)
    }

    private func loadBudgets() async {
        guard granularity == .month, auth.isSignedIn else {
            budgets = []
            return
        }
        do {
            budgets = try await AccountSync.listBudgets(auth: auth, month: periodMonthString)
        } catch is CancellationError {
            // Superseded by a newer load (e.g. .task(id:) and .onAppear both
            // firing, or rapid tab switching) — not a real failure.
        } catch {
            print("DashboardView.loadBudgets failed: \(error)")
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

    private var heroLabel: String {
        let name = granularity.periodLabel(for: anchor, calendar: calendar)
        return isCurrentPeriod ? "This \(granularity.rawValue) · \(name)" : name
    }

    /// Average spend per day over the period — up to today if it's the
    /// current one (matches the web dashboard's "Per day" figure).
    private var perDay: Decimal {
        guard let interval = granularity.interval(containing: anchor, calendar: calendar) else { return 0 }
        let end = isCurrentPeriod ? Date.now : interval.end.addingTimeInterval(-1)
        let days = (calendar.dateComponents([.day], from: interval.start, to: end).day ?? 0) + 1
        return summary.currentMonthTotal / Decimal(max(days, 1))
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
                            greetingHeader
                            granularityPicker
                            periodSwitcher
                            PeriodHeroCard(
                                label: heroLabel,
                                amount: summary.currentMonthTotal,
                                currencyCode: currencyCode,
                                delta: summary.previousMonthTotal > 0
                                    ? summary.currentMonthTotal - summary.previousMonthTotal
                                    : nil,
                                against: "the \(granularity.rawValue) before",
                                figures: [
                                    (
                                        "Previous \(granularity.rawValue)",
                                        summary.previousMonthTotal.formatted(.currency(code: currencyCode))
                                    ),
                                    (
                                        isCurrentPeriod ? "Per day so far" : "Per day",
                                        perDay.formatted(.currency(code: currencyCode))
                                    ),
                                ],
                                points: trendPoints,
                                highlighted: periodStart
                            )

                            CategoryBreakdownCard(
                                breakdown: summary.currentMonthByCategory,
                                currencyCode: currencyCode
                            ) {
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
                                    CardLinkLabel(title: "All months")
                                }
                            }

                            if !summary.insights.isEmpty {
                                InsightsCard(insights: summary.insights)
                            }
                            if granularity == .month, !budgets.isEmpty {
                                BudgetsSummaryCard(budgets: budgets, onManage: { router.selection = .budgets })
                            }
                            RecentReceiptsCard(
                                title: isCurrentPeriod ? "Recent receipts" : "Receipts",
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
            .navigationBarTitleDisplayMode(.inline)
            // The greeting header is the page title; pushed screens (All
            // months, receipt detail) still show their own bar.
            .toolbar(receipts.isEmpty ? .visible : .hidden, for: .navigationBar)
            .task(id: "\(granularity.rawValue)-\(periodMonthString)-\(auth.isSignedIn)") {
                await loadBudgets()
            }
            .onAppear {
                // TabView keeps this view alive across tab switches, so
                // .task(id:) alone won't refire just from revisiting this tab
                // (its id hasn't changed) — e.g. after adding a budget on the
                // Budgets tab and switching straight back here.
                Task { await loadBudgets() }
            }
        }
    }

    /// First name from the signed-in account; `nil` while anonymous, in which
    /// case `greetingHeader` shows just the time-of-day greeting alone.
    private var firstName: String? {
        guard case .signedIn(let name, _) = auth.state, let name,
            let first = name.split(separator: " ").first, !first.isEmpty
        else { return nil }
        return String(first)
    }

    private var greeting: String {
        switch calendar.component(.hour, from: .now) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var greetingHeader: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionLabel(firstName == nil ? "Overview" : greeting)
                Text(firstName ?? greeting)
                    .font(.display(38, relativeTo: .largeTitle))
                    .tracking(-1)
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            if let firstName {
                Button {
                    router.selection = .account
                } label: {
                    Text(firstName.prefix(1).uppercased())
                        .font(.display(18, bold: true, relativeTo: .headline))
                        .foregroundStyle(Theme.Palette.gold)
                        .frame(width: 44, height: 44)
                        .background(HeroPanelBackground(cornerRadius: 22))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Account")
            }
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
            periodButton(systemImage: "chevron.left", label: "Previous period", enabled: canGoBack) {
                anchor = granularity.shift(anchor, by: -1, calendar: calendar)
            }
            Spacer()
            Text(granularity.periodLabel(for: anchor, calendar: calendar))
                .font(.appHeadline)
                .foregroundStyle(Theme.Palette.text)
                .contentTransition(.numericText())
            Spacer()
            periodButton(systemImage: "chevron.right", label: "Next period", enabled: canGoForward) {
                anchor = granularity.shift(anchor, by: 1, calendar: calendar)
            }
        }
    }

    private func periodButton(
        systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(Theme.Motion.base) { action() }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 40, height: 40)
                .background(Theme.Palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.Palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: Receipt.self, inMemory: true)
        .environment(AuthManager())
        .environment(TabRouter())
}
