import SwiftUI
import SwiftData

@main
struct AIReceiptAppApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: Receipt.self)
    }
}
