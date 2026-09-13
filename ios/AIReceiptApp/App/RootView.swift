import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }

            ScanFlowView()
                .tabItem { Label("Scan", systemImage: "camera.viewfinder") }

            ReceiptListView()
                .tabItem { Label("Receipts", systemImage: "list.bullet.rectangle") }

            BudgetsView()
                .tabItem { Label("Budgets", systemImage: "target") }

            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .tint(Theme.Palette.accent)
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
