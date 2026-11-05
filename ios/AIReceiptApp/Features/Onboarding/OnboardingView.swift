import SwiftUI

/// Four screens the first time Tally opens: what it does, ending on the
/// camera. Skippable, never shown again (`hasSeen`).
struct OnboardingView: View {
    @AppStorage(OnboardingView.seenKey) static var hasSeen = false
    static let seenKey = "onboarding.seen"

    /// Called when they tap "Scan your first receipt".
    let onScan: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Page {
        let symbol: String
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(
            symbol: "camera.viewfinder",
            title: "Snap a receipt.\nTally reads every item.",
            body: "Store, date, total, tax and each line, filled in for you. No typing, no bank linking."
        ),
        Page(
            symbol: "envelope.fill",
            title: "Got it by email?\nJust forward it.",
            body: "Send e-receipts from Uber, Amazon or anywhere to \(ReceiptsInbox.general) and they're added for you."
        ),
        Page(
            symbol: "person.2.fill",
            title: "Split any bill,\nitem by item.",
            body: "Friends get a link with exactly what they owe. They don't need the app."
        ),
        Page(
            symbol: "tag.fill",
            title: "Know what things cost.\nReturn them in time.",
            body: "See prices creep up over time, and get a reminder before a return window closes."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { finish() }
                    .font(.appCallout)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.sm)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: Theme.Space.xl) {
                        Spacer(minLength: 0)
                        Image(systemName: item.symbol)
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(Theme.Palette.gold)
                            .frame(width: 160, height: 160)
                            .background(HeroPanelBackground(cornerRadius: 44))
                        VStack(spacing: Theme.Space.md) {
                            // Same height on every page (titles run 2–3 lines),
                            // so nothing jumps while paging.
                            Text(item.title)
                                .font(.display(32, relativeTo: .title))
                                .tracking(-0.8)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Theme.Palette.text)
                                .lineLimit(2, reservesSpace: true)
                                .minimumScaleFactor(0.85)
                            Text(item.body)
                                .font(.appCallout)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .padding(.horizontal, Theme.Space.lg)
                                .lineLimit(3, reservesSpace: true)
                        }
                        Spacer(minLength: 0)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, Theme.Space.lg)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Dots, then the one button that matters.
            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Theme.Palette.gold : Theme.Palette.border)
                        .frame(width: index == page ? 18 : 6, height: 6)
                        .animation(Theme.Motion.base, value: page)
                }
            }
            .padding(.bottom, Theme.Space.xl)

            // The same height on every page ("Maybe later" is reserved but
            // hidden until the last one), so paging never shifts the layout.
            VStack(spacing: Theme.Space.sm) {
                if page < pages.count - 1 {
                    Button {
                        withAnimation(Theme.Motion.base) { page += 1 }
                    } label: {
                        Text("Next")
                    }
                    .buttonStyle(.primary)
                } else {
                    Button {
                        finish()
                        onScan()
                    } label: {
                        Label("Scan your first receipt", systemImage: "camera.fill")
                    }
                    .buttonStyle(.primary)
                }
                Button("Maybe later") { finish() }
                    .font(.appCallout)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.top, Theme.Space.xs)
                    .opacity(page == pages.count - 1 ? 1 : 0)
                    .disabled(page != pages.count - 1)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.Palette.bg.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    private func finish() {
        Self.hasSeen = true
        dismiss()
    }
}
