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

/// Mirrors `design/tokens.json` — keep values in sync with that file.
/// (Web consumes the same tokens via `design/tokens.css`.)
enum Theme {
    enum Palette {
        static let bg = Color(light: "#FAFAF9", dark: "#0F0F10")
        static let surface = Color(light: "#FFFFFF", dark: "#17171A")
        static let surface2 = Color(light: "#F4F4F2", dark: "#202024")
        static let surfaceSunken = Color(light: "#F0EFEC", dark: "#0B0B0C")
        static let border = Color(light: "#E7E5E1", dark: "#2B2B30")
        static let borderStrong = Color(light: "#D6D3CD", dark: "#3B3B42")
        static let text = Color(light: "#1A1A19", dark: "#F5F5F4")
        static let textSecondary = Color(light: "#6B6B66", dark: "#A2A2A0")
        static let textTertiary = Color(light: "#9A9A93", dark: "#6E6E6D")

        /// "Ledger" direction — a deep teal, not blue. `accentForeground` is the
        /// text/icon color for anything filled with `accent` (white in light
        /// mode, but dark mode's accent is bright enough that it needs dark
        /// text — same convention as `accent-fg` in tokens.json).
        static let accent = Color(light: "#0E6E58", dark: "#35C79A")
        static let accentForeground = Color(light: "#FFFFFF", dark: "#0F0F10")

        /// The hero card's spotlight color only — eyebrow label, delta chip,
        /// sparkline. Never used for a button, link, or anything else.
        static let gold = Color(light: "#D9AE5C", dark: "#EAC471")

        /// The hero card's own gradient — always this dark ink-to-teal
        /// diagonal regardless of light/dark mode (a fixed card sitting on
        /// the page, not a themed surface). `heroText`/`heroChipBackground`
        /// are its on-gradient text/chip colors.
        static let heroGradientStart = Color(light: "#0F1E19", dark: "#090E0C")
        static let heroGradientMid = Color(light: "#123A32", dark: "#0F2B25")
        static let heroGradientEnd = Color(light: "#0E6E58", dark: "#167A62")
        static let heroText = Color(hex: "#F2EEE1")
        static let heroChipBackground = Color.white.opacity(0.12)

        static let success = Color(light: "#1F9D57", dark: "#37C77E")
        static let warning = Color(light: "#C1841A", dark: "#E4A63E")
        static let danger = Color(light: "#D5473B", dark: "#F26A5C")

        /// Default card shadow (Ledger direction) — replaces the old border.
        static let cardShadow = Color(light: "#141812", dark: "#000000")
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

extension Font {
    // Plain system (SF Pro), not `.rounded` — matches the web's plain Inter
    // for the big figures (the Ledger direction dropped the rounded/display
    // treatment in favor of the same workhorse sans everywhere).
    static let appDisplay = Font.system(size: 34, weight: .heavy)
    static let appTitle = Font.system(size: 28, weight: .bold)
    static let appHeadline = Font.system(size: 20, weight: .semibold)
    static let appBody = Font.system(size: 16)
    static let appCallout = Font.system(size: 15)
    static let appSubhead = Font.system(size: 13, weight: .medium)
    static let appCaption = Font.system(size: 12)
    static let appMicro = Font.system(size: 11, weight: .semibold)
}
