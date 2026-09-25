import SwiftUI

/// The primary container: a surface card with a hairline edge and a soft
/// shadow (matches the web `Card`).
struct AppCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Theme.Palette.surface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                    .strokeBorder(Theme.Palette.border, lineWidth: 1)
            )
            .shadow(
                color: Theme.Palette.cardShadow.opacity(colorScheme == .dark ? 0.45 : 0.07),
                radius: 14, x: 0, y: 8
            )
    }
}

/// A grouped-form section in the app's palette: surface rows on the page
/// ground, with a mono eyebrow for a header (like the dashboard card labels).
/// Use inside a `Form` styled with `.ledgerBackground()`.
struct LedgerSection<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        Section {
            content()
                .listRowBackground(Theme.Palette.surface)
        } header: {
            if let title {
                Text(title.uppercased())
                    .font(.appMicro)
                    .tracking(1.4)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }
}

extension View {
    /// Swaps a `Form`'s or `List`'s stock background (system grey, or pure
    /// black in dark mode) for the page ground, so these screens sit in the
    /// same palette as the rest of the app. Grouped rows still need
    /// `.listRowBackground(Theme.Palette.surface)` — `LedgerSection` does it.
    func ledgerBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.Palette.bg.ignoresSafeArea())
    }
}

/// The always-ink background of the hero panel, with a gold glow in the
/// top-trailing corner — the one loud moment per screen.
struct HeroPanelBackground: View {
    var cornerRadius: CGFloat = Theme.Radius.xxl

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(
                LinearGradient(
                    colors: [Theme.Palette.heroInkTop, Theme.Palette.heroInkBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RadialGradient(
                    colors: [Theme.Palette.gold.opacity(0.2), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 320
                )
                .clipShape(shape)
            )
            .overlay(shape.strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 12)
    }
}

/// Small uppercase eyebrow label above a value or a card's content — set in
/// the mono face, like a printed receipt heading.
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.Palette.textTertiary
    init(_ text: String, color: Color = Theme.Palette.textTertiary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.appMicro)
            .tracking(1.6)
            .foregroundStyle(color)
    }
}

/// The rounded, tinted category icon used in every receipt row, budget row,
/// and the category list. Radius scales with size so it reads as the same
/// "icon-chip" shape at any size.
struct CategoryGlyph: View {
    let category: ExpenseCategory
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: category.systemImage)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(category.tint)
            .frame(width: size, height: size)
            .background(
                category.tint.opacity(0.15),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
    }
}

/// Pulsing placeholder shown while data loads.
struct SkeletonBlock: View {
    var height: CGFloat = 16
    var width: CGFloat?
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
            .fill(Theme.Palette.surface2)
            .frame(width: width, height: height)
            .opacity(pulse ? 0.5 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .accessibilityHidden(true)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appCallout.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(Theme.Palette.accentForeground)
            .background(Theme.Palette.accent, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Theme.Motion.base, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appCallout.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(Theme.Palette.text)
            .background(Theme.Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Palette.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.Motion.base, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondaryFill: SecondaryButtonStyle { .init() }
}
