import SwiftData
import SwiftUI

@main
struct AIReceiptAppApp: App {
    @State private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .task { auth.bootstrap() }
        }
        .modelContainer(for: Receipt.self)
    }
}
