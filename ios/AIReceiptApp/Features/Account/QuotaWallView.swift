import SwiftUI

/// Soft wall shown when an anonymous device has used all its free scans.
/// History stays browsable behind it; only new scans are gated.
struct QuotaWallView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.Palette.accent.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.Palette.accent)
            }

            VStack(spacing: Theme.Space.xs) {
                Text("You're out of free scans")
                    .font(.appHeadline)
                    .foregroundStyle(Theme.Palette.text)
                Text("Sign in to keep scanning — you'll also get the web app and your receipts synced across devices. Everything you've scanned so far comes with you.")
                    .font(.appCallout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(.horizontal, Theme.Space.lg)

            Spacer()

            if auth.isConfigured {
                SignInButton(title: "Sign in to keep scanning") { dismiss() }
            } else {
                Text("Sign-in isn't available in this build.")
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Button("Not now") { dismiss() }
                .buttonStyle(.plain)
                .font(.appCallout)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(Theme.Space.lg)
        .background(Theme.Palette.bg.ignoresSafeArea())
    }
}

#Preview {
    QuotaWallView()
        .environment(AuthManager())
        .modelContainer(for: Receipt.self, inMemory: true)
}
