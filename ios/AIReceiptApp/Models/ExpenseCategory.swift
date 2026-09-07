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

    var tint: Color {
        switch self {
        case .groceries: .green
        case .restaurants: .orange
        case .transport: .blue
        case .shopping: .pink
        case .entertainment: .purple
        case .health: .red
        case .utilities: .yellow
        case .travel: .teal
        case .other: .gray
        }
    }
}
