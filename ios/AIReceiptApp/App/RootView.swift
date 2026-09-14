import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = TabRouter()

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

            BudgetsView()
                .tabItem { Label("Budgets", systemImage: "target") }
                .tag(AppTab.budgets)

            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(AppTab.account)
        }
        .tint(Theme.Palette.accent)
        .environment(router)
        .task { await AccountSync.pull(auth: auth, context: modelContext) }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await AccountSync.pull(auth: auth, context: modelContext) }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: Receipt.self, inMemory: true)
        .environment(AuthManager())
}
