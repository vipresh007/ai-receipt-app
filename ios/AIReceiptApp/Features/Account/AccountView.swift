import SwiftUI

/// The "Account" tab. Local-first: anonymous by default, with an optional
/// Google sign-in that unlocks the web app + cross-device sync.
struct AccountView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.xl) {
                    switch auth.state {
                    case .signedIn(let name, let email):
                        signedIn(name: name, email: email)
                    case .anonymous:
                        anonymous
                    }
                }
                .padding(Theme.Space.lg)
            }
            .frame(maxWidth: .infinity)
            .background(Theme.Palette.bg.ignoresSafeArea())
            .navigationTitle("Account")
        }
    }

    // MARK: - Signed in

    @ViewBuilder
    private func signedIn(name: String?, email: String?) -> some View {
        AppCard {
            HStack(spacing: Theme.Space.md) {
                ZStack {
                    Circle().fill(Theme.Palette.accent.opacity(0.14)).frame(width: 52, height: 52)
                    Text(initials(name: name, email: email))
                        .font(.appCallout.weight(.semibold))
                        .foregroundStyle(Theme.Palette.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name ?? "Signed in")
                        .font(.appCallout.weight(.medium))
                        .foregroundStyle(Theme.Palette.text)
                    if let email {
                        Text(email)
                            .font(.appCaption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                Spacer()
            }
        }

        AppCard {
            Label {
                Text("Your receipts sync to the web app and any other device you sign in on.")
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            } icon: {
                Image(systemName: "checkmark.icloud").foregroundStyle(Theme.Palette.accent)
            }
        }

        Button(role: .destructive) {
            Task { await auth.signOut() }
        } label: {
            Text("Sign out")
        }
        .buttonStyle(.secondaryFill)
        .disabled(auth.isBusy)
    }

    // MARK: - Anonymous

    @ViewBuilder
    private var anonymous: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SectionLabel("You're using AI Receipt without an account")
                Text("Everything works on this device. Sign in when you want the web app, backup, and sync across devices.")
                    .font(.appCallout)
                    .foregroundStyle(Theme.Palette.text)

                if let remaining = auth.scansRemaining {
                    Divider()
                    Label(
                        remaining <= 0
                            ? "No free scans left on this device"
                            : "^[\(remaining) free scan](inflect: true) left on this device",
                        systemImage: "sparkles"
                    )
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }

        benefit("globe", "Use it on the web", "Open your receipts at the AI Receipt web app.")
        benefit("arrow.triangle.2.circlepath", "Sync everywhere", "Scan on your phone, review on your laptop.")
        benefit("checkmark.icloud", "Backup", "Your receipts are safe if you lose your phone.")

        if auth.isConfigured {
            SignInButton()
        } else {
            Text("Sign-in isn't available in this build.")
                .font(.appCaption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private func benefit(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        AppCard {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appCallout.weight(.medium))
                        .foregroundStyle(Theme.Palette.text)
                    Text(subtitle)
                        .font(.appCaption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            } icon: {
                Image(systemName: icon).foregroundStyle(Theme.Palette.accent)
            }
        }
    }

    private func initials(name: String?, email: String?) -> String {
        if let name, !name.isEmpty {
            let parts = name.split(separator: " ")
            let letters = parts.prefix(2).compactMap { $0.first }
            if !letters.isEmpty { return String(letters).uppercased() }
        }
        return String(email?.first ?? "?").uppercased()
    }
}

#Preview {
    AccountView()
        .environment(AuthManager())
        .modelContainer(for: Receipt.self, inMemory: true)
}
