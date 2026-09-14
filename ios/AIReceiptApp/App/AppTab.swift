import SwiftUI

enum AppTab: Hashable {
    case dashboard, scan, receipts, budgets, account
}

/// Lets a view outside the TabView's own hierarchy (e.g. a "Manage" link on
/// the Dashboard's Budgets card) switch tabs, since TabView's selection lives
/// in RootView and Dashboard has no other way to reach it.
@Observable
final class TabRouter {
    var selection: AppTab = .dashboard
}
