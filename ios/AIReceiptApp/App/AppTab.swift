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
    /// A tapped notification's receipt, expense, group or person.
    var opened: ActivityTarget?
    /// The one-time "next time, just forward the email" tip.
    var emailTip = false
    /// A just-saved receipt that turned out to be one you already had.
    var duplicate: DuplicatePair?
    /// Bumped when a tab is tapped while already open: rebuilds that tab, so
    /// it's back on its main screen (like any iPhone tab bar).
    var resets: [AppTab: Int] = [:]

    func reset(_ tab: AppTab) { resets[tab, default: 0] += 1 }
}

struct UndoToast: Identifiable {
    let id = UUID()
    let message: String
    let onUndo: () -> Void
}


/// A receipt saved twice: `copy` was just added, `existing` was there first.
struct DuplicatePair {
    let copy: Receipt
    let existing: Receipt
}
