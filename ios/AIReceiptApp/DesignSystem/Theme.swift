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
        static let accent = Color(light: "#3373F1", dark: "#528CFF")
        static let success = Color(light: "#1F9D57", dark: "#37C77E")
        static let warning = Color(light: "#C1841A", dark: "#E4A63E")
        static let danger = Color(light: "#D5473B", dark: "#F26A5C")
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
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
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
    static let appDisplay = Font.system(size: 34, weight: .bold, design: .rounded)
    static let appTitle = Font.system(size: 28, weight: .bold)
    static let appHeadline = Font.system(size: 20, weight: .semibold)
    static let appBody = Font.system(size: 16)
    static let appCallout = Font.system(size: 15)
    static let appSubhead = Font.system(size: 13, weight: .medium)
    static let appCaption = Font.system(size: 12)
    static let appMicro = Font.system(size: 11, weight: .semibold)
}
