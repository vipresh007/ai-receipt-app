import Auth0
import Foundation
import Observation

/// Owns the app's identity: an always-present anonymous device ID, plus an
/// optional Google sign-in through Auth0 that unlocks web access + sync.
///
/// Local-first: the app is fully usable while `state == .anonymous`. Signing in
/// is a one-way upgrade (see `docs/AUTH.md`). Only Google is wired up for now.
@MainActor
@Observable
final class AuthManager {
    enum State: Equatable {
        case anonymous
        case signedIn(name: String?, email: String?)
    }

    private(set) var state: State = .anonymous

    /// Free scans left for this device while anonymous; `nil` when signed in or
    /// not yet known. Updated from `/v1/extract` responses.
    private(set) var scansRemaining: Int?

    /// True while a sign-in / sign-out round-trip is in flight.
    private(set) var isBusy = false

    /// Stable per-install identifier, sent as `X-Device-Id` for anonymous scans.
    let deviceID: String

    /// False in builds without Auth0 config — the Account screen then hides the
    /// sign-in button and the app stays anonymous/local-only.
    var isConfigured: Bool { AppConfig.authConfigured }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    private let credentialsManager: CredentialsManager?
    private let defaults = UserDefaults.standard

    private enum Key {
        static let deviceID = "com.aireceipt.deviceID"
        static let name = "com.aireceipt.user.name"
        static let email = "com.aireceipt.user.email"
        static let didImport = "com.aireceipt.didImportOnSignIn"
    }

    init() {
        if let existing = KeychainStore.string(for: Key.deviceID) {
            deviceID = existing
        } else {
            let generated = UUID().uuidString
            KeychainStore.set(generated, for: Key.deviceID)
            deviceID = generated
        }

        if let domain = AppConfig.auth0Domain, let clientID = AppConfig.auth0ClientID {
            credentialsManager = CredentialsManager(
                authentication: Auth0.authentication(clientId: clientID, domain: domain)
            )
        } else {
            credentialsManager = nil
        }
    }

    /// Restore a previous session on launch (no network unless a refresh is due).
    func bootstrap() {
        guard let manager = credentialsManager, manager.hasValid() || manager.canRenew() else {
            state = .anonymous
            return
        }
        state = .signedIn(
            name: defaults.string(forKey: Key.name),
            email: defaults.string(forKey: Key.email)
        )
    }

    /// A valid API access token, refreshed if needed. `nil` when signed out.
    func accessToken() async -> String? {
        guard let manager = credentialsManager, manager.hasValid() || manager.canRenew() else {
            return nil
        }
        return try? await manager.credentials().accessToken
    }

    func signIn() async throws {
        guard
            let domain = AppConfig.auth0Domain,
            let clientID = AppConfig.auth0ClientID,
            let audience = AppConfig.auth0Audience,
            let manager = credentialsManager
        else { throw AuthError.notConfigured }

        isBusy = true
        defer { isBusy = false }

        let credentials =
            try await Auth0
            .webAuth(clientId: clientID, domain: domain)
            .audience(audience)
            .scope("openid profile email offline_access")
            .connection("google-oauth2")
            .start()

        try manager.store(credentials: credentials)

        var name: String?
        var email: String?
        if let info = try? await Auth0
            .authentication(clientId: clientID, domain: domain)
            .userInfo(withAccessToken: credentials.accessToken)
            .start()
        {
            name = info.name
            email = info.email
        }
        defaults.set(name, forKey: Key.name)
        defaults.set(email, forKey: Key.email)
        state = .signedIn(name: name, email: email)
        scansRemaining = nil
    }

    func signOut() async {
        isBusy = true
        defer { isBusy = false }

        if let domain = AppConfig.auth0Domain, let clientID = AppConfig.auth0ClientID {
            try? await Auth0.webAuth(clientId: clientID, domain: domain).logout()
        }
        try? credentialsManager?.clear()
        defaults.removeObject(forKey: Key.name)
        defaults.removeObject(forKey: Key.email)
        defaults.removeObject(forKey: Key.didImport)
        state = .anonymous
    }

    /// Record the remaining anonymous scan count reported by the backend.
    func noteScansRemaining(_ value: Int?) {
        guard let value else { return }
        scansRemaining = value
    }

    /// Guard so local receipts are pushed to the account only once per sign-in.
    var hasImportedOnSignIn: Bool {
        get { defaults.bool(forKey: Key.didImport) }
        set { defaults.set(newValue, forKey: Key.didImport) }
    }

    enum AuthError: LocalizedError {
        case notConfigured
        var errorDescription: String? { "Sign-in isn't configured in this build." }
    }
}
