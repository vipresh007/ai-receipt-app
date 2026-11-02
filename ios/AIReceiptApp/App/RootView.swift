import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = TabRouter()
    @State private var activityBadge = ActivityBadge()
    @State private var live = LiveEvents()
    /// First launch only (skipped for seeded/demo runs, e.g. screenshots).
    @State private var showOnboarding =
        !OnboardingView.hasSeen && !ProcessInfo.processInfo.arguments.contains("-seedSampleReceipts")

    /// Something was shared into Tally while it was closed: read it on Scan.
    private func pickUpShared() {
        guard router.sharedFile == nil, let file = SharedInbox.next() else { return }
        router.sharedFile = file
        router.scanning = true
    }

    var body: some View {
        // Tally's own tab bar (`TallyTabBar`) instead of the system one: five
        // equal slots, so the gold Scan camera sits dead centre and a selected
        // tab's highlight never reaches its neighbours.
        TabView(selection: $router.selection) {
            DashboardView().id(router.resets[.dashboard, default: 0]).tag(AppTab.dashboard).tallyTabRoot()
            ReceiptListView().id(router.resets[.receipts, default: 0]).tag(AppTab.receipts).tallyTabRoot()
            GroupsView().id(router.resets[.groups, default: 0]).tag(AppTab.groups).tallyTabRoot()
            AccountView().id(router.resets[.account, default: 0]).tag(AppTab.account).tallyTabRoot()
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: Theme.Space.sm) {
                if let toast = router.undo {
                    UndoBar(toast: toast) {
                        toast.onUndo()
                        withAnimation(Theme.Motion.base) { router.undo = nil }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                TallyTabBar(unread: activityBadge.unread) { router.scanning = true }
            }
            .ignoresSafeArea(.keyboard)
        }
        .tint(Theme.Palette.accent)
        .fullScreenCover(isPresented: Binding(
            get: { showOnboarding || router.showIntro },
            set: { if !$0 { showOnboarding = false; router.showIntro = false } }
        )) {
            OnboardingView { router.scanning = true }
        }
        .sheet(isPresented: $router.scanning) {
            ScanFlowView(onSaved: { _ in router.scanning = false }, isMainScan: true)
                .environment(router)
        }
        .environment(router)
        .environment(activityBadge)
        .environment(live)
        .task {
            #if DEBUG
            SampleData.seedIfRequested(modelContext)
            SampleData.seedBusyJuneIfRequested(modelContext)
            #endif
            await AccountSync.pull(auth: auth, context: modelContext)
            await activityBadge.refresh(auth)
            if auth.isSignedIn { live.start(auth) }
            await ReturnReminders.sync(modelContext)
            WidgetSync.update(modelContext)
            pickUpShared()
            PushNotifications.auth = auth
            PushNotifications.onOpen = { link in
                router.selection = link.hasPrefix("receipts") ? .receipts : .groups
            }
            await PushNotifications.refresh()
        }
        .onOpenURL { url in
            // From the widget: com.vipreshpatel.tally://scan | //dashboard.
            switch url.host() {
            case "scan": router.scanning = true
            case "dashboard": router.selection = .dashboard
            default: break
            }
        }
        .onChange(of: live.tick) { _, _ in
            // Someone changed something you share: the badge, and your share
            // of any receipt they edited (your spending), follow.
            Task {
                await activityBadge.refresh(auth)
                await AccountSync.pull(auth: auth, context: modelContext)
            }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { live.start(auth) } else { live.stop() }
            if signedIn { Task { await PushNotifications.upload() } }
        }
        .onChange(of: scenePhase) { _, phase in
            // Streams only while the app is in front (battery).
            if phase == .active, auth.isSignedIn { live.start(auth) }
            if phase == .background {
                live.stop()
                WidgetSync.update(modelContext)
            }
            guard phase == .active else { return }
            pickUpShared()
            Task {
                await AccountSync.pull(auth: auth, context: modelContext)
                await activityBadge.refresh(auth)
                await ReturnReminders.sync(modelContext)
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: Receipt.self, inMemory: true)
        .environment(AuthManager())
        .environment(ActivityBadge())
        .environment(LiveEvents())
}


private extension View {
    /// A tab's screen: no system tab bar, and room at the bottom for ours.
    func tallyTabRoot() -> some View {
        self
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: TallyTabBar.height + Theme.Space.sm)
            }
    }
}

/// The bottom bar: Dashboard, Receipts, Scan (gold camera, opens the Scan
/// sheet), Shared, Account. Every slot is the same width.
struct TallyTabBar: View {
    static let height: CGFloat = 64

    @Environment(TabRouter.self) private var router
    let unread: Int
    let onScan: () -> Void
    /// Set on tap so the highlight moves at once, before the new screen's
    /// first (heavier) render; cleared when the switch lands.
    @State private var tapped: AppTab?

    var body: some View {
        HStack(spacing: 0) {
            slot(.dashboard, "Dashboard", "chart.pie.fill")
            slot(.receipts, "Receipts", "list.bullet.rectangle")
            scanSlot
            slot(.groups, "Shared", "person.2.fill", badge: unread)
            slot(.account, "Account", "person.crop.circle")
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(height: Self.height)
        .background(Theme.Palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.Palette.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
        .padding(.horizontal, Theme.Space.md)
        .padding(.bottom, Theme.Space.xs)
    }

    private func slot(_ tab: AppTab, _ title: String, _ symbol: String, badge: Int = 0) -> some View {
        let selected = (tapped ?? router.selection) == tab
        return Button {
            guard !selected else {
                // Already here: back to this tab's main screen.
                router.reset(tab)
                return
            }
            UISelectionFeedbackGenerator().selectionChanged()
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { tapped = tab }
            // Let the bar draw first; the screen swaps on the next turn.
            DispatchQueue.main.async {
                router.selection = tab
                tapped = nil
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .medium))
                    .frame(height: 30)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text(badge > 9 ? "9+" : "\(badge)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Theme.Palette.danger, in: Capsule())
                                .offset(x: 10, y: -4)
                        }
                    }
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Theme.Palette.gold : Theme.Palette.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height - 10)
            .background(selected ? Theme.Palette.surface2 : .clear, in: Capsule())
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? "\(title), \(badge) new" : title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var scanSlot: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onScan()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.bg)
                    .frame(width: 30, height: 30)
                    .background(Theme.Palette.gold, in: Circle())
                Text("Scan")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.height - 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scan a receipt")
    }
}


/// "Deleted Loblaws · Undo", just above the tab bar.
struct UndoBar: View {
    let toast: UndoToast
    let undo: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: "trash")
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(toast.message)
                .font(.appCallout)
                .foregroundStyle(Theme.Palette.text)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.sm)
            Button("Undo", action: undo)
                .font(.appCallout.weight(.semibold))
                .foregroundStyle(Theme.Palette.gold)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.md)
        .background(Theme.Palette.surface2, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.Palette.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .padding(.horizontal, Theme.Space.lg)
    }
}
