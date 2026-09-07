import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }

            ScanFlowView()
                .tabItem { Label("Scan", systemImage: "camera.viewfinder") }

            ReceiptListView()
                .tabItem { Label("Receipts", systemImage: "list.bullet.rectangle") }
        }
        .tint(Theme.Palette.accent)
    }
}

#Preview {
    RootView()
        .modelContainer(for: Receipt.self, inMemory: true)
}
