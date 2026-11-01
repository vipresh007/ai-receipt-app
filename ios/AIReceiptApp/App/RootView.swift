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
        router.scanning = true
    }

    var body: some View {
        TabView(selection: Binding(
            get: { router.selection },
            // The middle slot isn't a screen: it opens the Scan sheet.
            set: { tab in
                if tab == .scan { router.scanning = true } else { router.selection = tab }
            }
        )) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }
                .tag(AppTab.dashboard)

            ReceiptListView()
                .tabItem { Label("Receipts", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.receipts)

            // Holds the middle place for the gold camera drawn over it.
            Color.clear
                .tabItem { Text(" ") }
                .tag(AppTab.scan)


            GroupsView()
                .tabItem { Label("Shared", systemImage: "person.2.fill") }
                .badge(activityBadge.unread)
                .tag(AppTab.groups)

            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(AppTab.account)
        }
        .tint(Theme.Palette.accent)
        .overlay(alignment: .bottom) {
            ScanTabButton { router.scanning = true }
                .padding(.bottom, -5)
        }
        .ignoresSafeArea(.keyboard)
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


/// The gold camera in the middle of the tab bar: sized to its own slot so it
/// never covers the neighbouring tabs' selection, and opens the Scan sheet.
struct ScanTabButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Palette.bg)
                .frame(width: 46, height: 46)
                .background(Theme.Palette.gold, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scan a receipt")
    }
}
