import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = TabRouter()
    @State private var activityBadge = ActivityBadge()
    @State private var live = LiveEvents()

    /// Something was shared into Tally while it was closed: read it on Scan.
    private func pickUpShared() {
        guard router.sharedFile == nil, let file = SharedInbox.next() else { return }
        router.sharedFile = file
        router.selection = .scan
    }

    var body: some View {
        TabView(selection: $router.selection) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }
                .tag(AppTab.dashboard)

            ScanFlowView()
                .tabItem { Label("Scan", systemImage: "camera.viewfinder") }
                .tag(AppTab.scan)

            ReceiptListView()
                .tabItem { Label("Receipts", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.receipts)

            GroupsView()
                .tabItem { Label("Shared", systemImage: "person.2.fill") }
                .badge(activityBadge.unread)
                .tag(AppTab.groups)

            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(AppTab.account)
        }
        .tint(Theme.Palette.accent)
        .environment(router)
        .environment(activityBadge)
        .environment(live)
        .task {
            #if DEBUG
            SampleData.seedIfRequested(modelContext)
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
            case "scan": router.selection = .scan
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
