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

            // Not a screen: its gold camera icon opens the Scan sheet. Drawn
            // as the tab's own icon so the tab bar lines it up like the rest.
            Color.clear
                .tabItem {
                    Label {
                        Text("Scan")
                    } icon: {
                        Image(uiImage: ScanTabIcon.image)
                    }
                }
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


/// The middle tab's icon: a gold circle with the camera, kept in its own
/// colours (not tinted like the other tab icons).
enum ScanTabIcon {
    static let image: UIImage = {
        let size = CGSize(width: 34, height: 34)
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(Theme.Palette.gold).setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            if let camera = UIImage(systemName: "camera.fill", withConfiguration: config)?
                .withTintColor(UIColor(Theme.Palette.bg), renderingMode: .alwaysOriginal) {
                let origin = CGPoint(x: (size.width - camera.size.width) / 2, y: (size.height - camera.size.height) / 2)
                camera.draw(at: origin)
            }
        }
        return rendered.withRenderingMode(.alwaysOriginal)
    }()
}
