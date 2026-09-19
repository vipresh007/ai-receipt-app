import Auth0
import AuthenticationServices
import Foundation
import Observation

/// Owns the app's identity: an always-present anonymous device ID, plus an
/// optional Google or Apple sign-in through Auth0 that unlocks web access +
/// sync.
///
/// Local-first: the app is fully usable while `state == .anonymous`. Signing in
/// is a one-way upgrade (see `docs/AUTH.md`).
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

        // No `.connection(...)` filter: Auth0 Universal Login shows every method
        // enabled for this application (Google + email/password today).
        let credentials =
            try await Auth0
            .webAuth(clientId: clientID, domain: domain)
            .audience(audience)
            .scope("openid profile email offline_access")
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

    /// Signs in with the credential from a completed native `ASAuthorizationController`
    /// request (see `AppleSignInButton`). Exchanges Apple's authorization code for
    /// Auth0 credentials via the Apple **Native** connection — the Client ID
    /// configured on that connection must be this app's bundle id, not a Services ID
    /// (that's the web-flow identifier; see `docs/AUTH.md`).
    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
        guard
            let domain = AppConfig.auth0Domain,
            let clientID = AppConfig.auth0ClientID,
            let audience = AppConfig.auth0Audience,
            let manager = credentialsManager,
            let codeData = credential.authorizationCode,
            let code = String(data: codeData, encoding: .utf8)
        else { throw AuthError.notConfigured }

        isBusy = true
        defer { isBusy = false }

        let credentials = try await Auth0
            .authentication(clientId: clientID, domain: domain)
            .login(
                appleAuthorizationCode: code,
                fullName: credential.fullName,
                profile: nil,
                audience: audience,
                scope: "openid profile email offline_access"
            )
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
        // Apple hands us the real name/email only on the very first
        // authorization ever — fall back to what the credential itself
        // carried if Auth0's /userinfo didn't have them (e.g. a private
        // relay email, or a re-authorization that Apple stayed silent on).
        if name == nil, let components = credential.fullName {
            let formatted = PersonNameComponentsFormatter().string(from: components)
            if !formatted.isEmpty { name = formatted }
        }
        email = email ?? credential.email

        defaults.set(name, forKey: Key.name)
        defaults.set(email, forKey: Key.email)
        state = .signedIn(name: name, email: email)
        scansRemaining = nil
    }

    func signOut() async {
        isBusy = true
        defer { isBusy = false }

        // No `Auth0.webAuth(...).logout()` here: that opens an
        // ASWebAuthenticationSession purely to clear Auth0's browser-side SSO
        // cookie, which only ever existed for the Google flow (a web view) —
        // Apple's native sign-in never touches a browser session at all. All
        // it accomplished was a confusing system "wants to use ... to sign
        // in" prompt during sign-*out*. Clearing local tokens below is what
        // actually signs this device out; a stale Google browser session at
        // worst skips the account picker on a future Google sign-in, not a
        // security issue.
        try? credentialsManager?.clear()
        defaults.removeObject(forKey: Key.name)
        defaults.removeObject(forKey: Key.email)
        state = .anonymous
    }

    /// Record the remaining anonymous scan count reported by the backend.
    func noteScansRemaining(_ value: Int?) {
        guard let value else { return }
        scansRemaining = value
    }

    enum AuthError: LocalizedError {
        case notConfigured
        var errorDescription: String? { "Sign-in isn't configured in this build." }
    }
}
