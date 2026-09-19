import AuthenticationServices
import SwiftUI

/// Sign in with Apple — Apple's own button view, so it always matches their
/// Human Interface Guidelines (a custom-styled button here risks App Review
/// rejection). Required alongside `SignInButton`'s Google option per App
/// Review guideline 4.8: any app offering a third-party login must also offer
/// Sign in with Apple. Reused by the Account tab and the quota wall, same as
/// `SignInButton`.
struct AppleSignInButton: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    /// Called after a successful sign-in + import (e.g. to dismiss a sheet).
    var onSignedIn: () -> Void = {}

    @State private var errorMessage: String?

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            Task { await handle(result) }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 44)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
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

    private func handle(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Apple didn't return a usable credential."
                return
            }
            do {
                try await auth.signInWithApple(credential: credential)
                _ = try? await AccountSync.importLocalReceiptsIfNeeded(auth: auth, context: modelContext)
                await AccountSync.pull(auth: auth, context: modelContext)
                onSignedIn()
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            let nsError = error as NSError
            let userCancelled =
                nsError.domain == ASAuthorizationError.errorDomain
                && nsError.code == ASAuthorizationError.canceled.rawValue
            if !userCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }
}
