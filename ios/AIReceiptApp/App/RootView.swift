import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = TabRouter()
    @State private var activityBadge = ActivityBadge()
    @State private var live = LiveEvents()
    @State private var keyboard = KeyboardWatcher()
    /// First launch only (skipped for seeded/demo runs, e.g. screenshots).
    @State private var showOnboarding =
        !OnboardingView.hasSeen && !ProcessInfo.processInfo.arguments.contains("-seedSampleReceipts")

    /// Something was shared into Tally while it was closed: read it on Scan.
    private func pickUpShared() {
        guard router.sharedFile == nil, let file = SharedInbox.next() else { return }
        router.sharedFile = file
        router.scanning = true
    }

    /// One tab's screen: shown when selected, kept alive (and out of the way)
    /// otherwise. Re-tapping the open tab rebuilds it (back to its main screen).
    @ViewBuilder
    private func tabPage<Content: View>(_ tab: AppTab, @ViewBuilder _ content: () -> Content) -> some View {
        let shown = router.selection == tab
        content()
            .id(router.resets[tab, default: 0])
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
            .zIndex(shown ? 1 : 0)
    }

    var body: some View {
        // Tally's own tab bar (`TallyTabBar`) instead of the system TabView:
        // five equal slots, so the gold Scan camera sits dead centre. All four
        // tabs stay alive, so each keeps its place when you switch away and back.
        ZStack {
            tabPage(.dashboard) { DashboardView() }
            tabPage(.receipts) { ReceiptListView() }
            tabPage(.groups) { GroupsView() }
            tabPage(.account) { AccountView() }
        }
        // Every scrolling screen in the app (and every screen pushed inside
        // one) leaves room for the bar below its last row.
        .contentMargins(.bottom, TallyTabBar.height + Theme.Space.lg, for: .scrollContent)
        .overlay(alignment: .bottom) {
            if !keyboard.isVisible {
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
            }
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
        .sheet(item: $router.opened) { target in
            ActivityTargetSheet(target: target)
                .environment(router)
                .environment(activityBadge)
                .environment(live)
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
            PushNotifications.onOpen = { link, target in
                if let target {
                    router.opened = target
                } else {
                    router.selection = link.hasPrefix("receipts") ? .receipts : .groups
                }
            }
            await PushNotifications.refresh()
        }
        .onChange(of: router.selection) { _, tab in
            // Shared is where pushes matter: ask the first time it's opened.
            if tab == .groups, auth.isSignedIn { Task { await PushNotifications.enable() } }
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


/// Hides the tab bar while the keyboard is up (it would otherwise ride on top
/// of the keyboard).
@MainActor
@Observable
final class KeyboardWatcher {
    var isVisible = false

    init() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isVisible = true }
        }
        center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isVisible = false }
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
