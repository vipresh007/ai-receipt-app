import SwiftUI

enum AppTab: Hashable {
    case dashboard, scan, receipts, groups, account
}

/// Lets a view outside the TabView's own hierarchy (e.g. a "Manage" link on
/// the Dashboard's Budgets card) switch tabs, since TabView's selection lives
/// in RootView and Dashboard has no other way to reach it.
@Observable
final class TabRouter {
    var selection: AppTab = .dashboard
    /// The Scan sheet, opened by the gold camera in the middle of the tab bar.
    var scanning = false
    /// Show the welcome screens again (Account → "Show the intro again").
    var showIntro = false
    /// A short-lived "Deleted X · Undo" bar shown above the tab bar.
    var undo: UndoToast?
    /// A photo or PDF shared in from another app, for the Scan tab to read.
    var sharedFile: URL?
}

struct UndoToast: Identifiable {
    let id = UUID()
    let message: String
    let onUndo: () -> Void
}
