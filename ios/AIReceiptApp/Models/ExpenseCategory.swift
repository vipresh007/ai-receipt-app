import SwiftUI

/// The categories a receipt can be filed under. Raw values are stable and safe
/// to persist; display strings and styling live here so the rest of the app
/// never hard-codes them.
enum ExpenseCategory: String, CaseIterable, Codable, Identifiable {
    case groceries
    case restaurants
    case transport
    case shopping
    case entertainment
    case health
    case utilities
    case travel
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groceries: "Groceries"
        case .restaurants: "Restaurants"
        case .transport: "Transport"
        case .shopping: "Shopping"
        case .entertainment: "Entertainment"
        case .health: "Health"
        case .utilities: "Utilities"
        case .travel: "Travel"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .groceries: "cart.fill"
        case .restaurants: "fork.knife"
        case .transport: "car.fill"
        case .shopping: "bag.fill"
        case .entertainment: "film.fill"
        case .health: "cross.case.fill"
        case .utilities: "bolt.fill"
        case .travel: "airplane"
        case .other: "square.grid.2x2.fill"
        }
    }

    /// Category colors from `design/tokens.json` — tuned to coexist in a chart
    /// and stay distinct for color-vision deficiency.
    var tint: Color {
        switch self {
        case .groceries: Color(light: "#2FA36B", dark: "#46C088")
        case .restaurants: Color(light: "#E1873C", dark: "#F2A25C")
        case .transport: Color(light: "#3B82C4", dark: "#5AA0E0")
        case .shopping: Color(light: "#D2649B", dark: "#EC85B8")
        case .entertainment: Color(light: "#8B5CD6", dark: "#A98AE6")
        case .health: Color(light: "#D5544A", dark: "#F0776C")
        case .utilities: Color(light: "#C0982A", dark: "#E3C04A")
        case .travel: Color(light: "#2FA6A0", dark: "#48C4BE")
        case .other: Color(light: "#8A8A83", dark: "#9A9A94")
        }
    }
}
