import SwiftUI
import UIKit

// MARK: - Color helpers

extension Color {
    /// Hex string → Color. Accepts `#RRGGBB` or `#RRGGBBAA` (with or without `#`).
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let r, g, b, a: Double
        if cleaned.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// A light/dark pair that resolves automatically with the interface style.
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

// MARK: - Theme

/// Mirrors `design/tokens.json` v0.3 ("ledger" palette) — keep values in sync
/// with that file. (Web consumes the same tokens via `design/tokens.css`.)
enum Theme {
    enum Palette {
        /// Warm paper in light mode, ink in dark.
        static let bg = Color(light: "#F3EEE3", dark: "#0C1412")
        static let surface = Color(light: "#FBF8F2", dark: "#121D1A")
        static let surface2 = Color(light: "#EDE7DA", dark: "#182723")
        static let surfaceSunken = Color(light: "#E8E1D2", dark: "#08100E")
        static let border = Color(light: "#E2DACA", dark: "#21302B")
        static let borderStrong = Color(light: "#CFC5B1", dark: "#2F413B")
        static let text = Color(light: "#1E2321", dark: "#F1ECE1")
        static let textSecondary = Color(light: "#5B5F59", dark: "#A7ADA5")
        static let textTertiary = Color(light: "#8B8D85", dark: "#6E766F")

        /// Gold is the action color. Light mode uses a deep gold so it holds
        /// 4.5:1 as text on paper and under white; dark mode uses the bright
        /// gold with ink text on it (same as `accent-fg` in tokens.json).
        static let accent = Color(light: "#8A5E0F", dark: "#D9AE5C")
        static let accentForeground = Color(light: "#FFFFFF", dark: "#0C1412")

        /// The bright gold used on the always-ink hero panel.
        static let gold = Color(hex: "#D9AE5C")
        static let teal = Color(hex: "#35C79A")
        static let amber = Color(hex: "#F2A25C")

        /// The hero panel — always ink regardless of light/dark mode, with a
        /// gold glow in the top-trailing corner (see `HeroPanelBackground`).
        static let heroInkTop = Color(light: "#0C1412", dark: "#0A110F")
        static let heroInkBottom = Color(light: "#14231F", dark: "#172824")
        static let heroText = Color(hex: "#F1ECE1")
        static let heroTextSecondary = Color(hex: "#F1ECE1").opacity(0.55)
        static let heroRule = Color.white.opacity(0.1)
        static let heroChipBackground = Color.white.opacity(0.08)

        static let success = Color(light: "#1F8A57", dark: "#37C77E")
        static let warning = Color(light: "#B7791A", dark: "#E4A63E")
        static let danger = Color(light: "#C8453A", dark: "#F26A5C")

        static let cardShadow = Color(light: "#302612", dark: "#000000")
    }

    enum Space {
        static let hair: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 28
    }

    enum Motion {
        static let base: Animation = .easeInOut(duration: 0.2)
        static let slow: Animation = .easeOut(duration: 0.32)
        static let spring: Animation = .spring(response: 0.35, dampingFraction: 0.82)
    }
}

// MARK: - Typography

/// Bundled faces (Resources/Fonts, registered via `UIAppFonts`), by
/// PostScript name. Body text stays San Francisco.
enum AppFontName {
    static let displayHeavy = "BricolageGrotesque-48ptExtraBold"
    static let displayBold = "BricolageGrotesque-48ptBold"
    static let mono = "IBMPlexMono-Regular"
    static let monoMedium = "IBMPlexMono-Medium"
}

extension Font {
    /// Big figures and screen headings — Bricolage Grotesque, scaling with
    /// Dynamic Type relative to the given text style.
    static func display(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom(bold ? AppFontName.displayBold : AppFontName.displayHeavy, size: size, relativeTo: style)
    }

    /// Money, dates, and printed-looking labels — IBM Plex Mono.
    static func mono(_ size: CGFloat, medium: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(medium ? AppFontName.monoMedium : AppFontName.mono, size: size, relativeTo: style)
    }

    static let appDisplay = Font.display(34)
    static let appTitle = Font.display(28, relativeTo: .title)
    static let appHeadline = Font.display(20, bold: true, relativeTo: .title3)
    static let appBody = Font.system(size: 16)
    static let appCallout = Font.system(size: 15)
    static let appSubhead = Font.system(size: 13, weight: .medium)
    static let appCaption = Font.system(size: 12)
    /// Uppercase eyebrow labels (with tracking — see `SectionLabel`).
    static let appMicro = Font.mono(11, medium: true, relativeTo: .caption2)
    /// Money amounts in rows and lists.
    static let appMoney = Font.mono(15, relativeTo: .callout)
}
