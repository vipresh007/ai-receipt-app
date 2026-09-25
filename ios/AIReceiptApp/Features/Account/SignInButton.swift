import Auth0
import SwiftUI

/// Primary "Sign in" action. Runs the Auth0 Universal Login flow (Google or
/// email/password — whatever the tenant has enabled), then does the one-shot
/// local→account receipt import. Reused by the Account tab and the quota wall.
struct SignInButton: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext

    var title = "Sign in or create account"
    /// Called after a successful sign-in + import (e.g. to dismiss a sheet).
    var onSignedIn: () -> Void = {}

    @State private var errorMessage: String?

    var body: some View {
        Button {
            Task { await run() }
        } label: {
            HStack(spacing: Theme.Space.sm) {
                if auth.isBusy {
                    ProgressView().tint(Theme.Palette.accentForeground)
                } else {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                }
                Text(title)
            }
        }
        .buttonStyle(.primary)
        .disabled(auth.isBusy)
        .alert(
            "Sign-in failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func run() async {
        do {
            try await auth.signIn()
            _ = try? await AccountSync.importLocalReceiptsIfNeeded(auth: auth, context: modelContext)
            await AccountSync.pull(auth: auth, context: modelContext)
            onSignedIn()
        } catch let error as WebAuthError where error == .userCancelled {
            // User closed the web sheet — not an error.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
