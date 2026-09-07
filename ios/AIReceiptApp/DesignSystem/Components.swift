import SwiftUI

/// A bordered surface card — the primary container on the dashboard.
struct AppCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(Theme.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Theme.Palette.surface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(Theme.Palette.border)
            }
    }
}

/// Small uppercase eyebrow label above a value or a card's content.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.appMicro)
            .tracking(0.5)
            .foregroundStyle(Theme.Palette.textTertiary)
    }
}

/// The rounded, tinted category icon used in every receipt row.
struct CategoryGlyph: View {
    let category: ExpenseCategory
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: category.systemImage)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(category.tint)
            .frame(width: size, height: size)
            .background(
                category.tint.opacity(0.14),
                in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
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
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                Theme.Palette.accent,
                in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Theme.Motion.base, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appCallout.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Theme.Palette.text)
            .background(
                Theme.Palette.surface2,
                in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            )
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
