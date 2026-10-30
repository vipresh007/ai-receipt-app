import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = TabRouter()
    @State private var activityBadge = ActivityBadge()
    @State private var live = LiveEvents()

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
        }
        .onChange(of: scenePhase) { _, phase in
            // Streams only while the app is in front (battery).
            if phase == .active, auth.isSignedIn { live.start(auth) }
            if phase == .background { live.stop() }
            guard phase == .active else { return }
            Task {
                await AccountSync.pull(auth: auth, context: modelContext)
                await activityBadge.refresh(auth)
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
