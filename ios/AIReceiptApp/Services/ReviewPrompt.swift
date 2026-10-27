import Foundation

/// When to ask for an App Store rating: right after a receipt is saved — a
/// moment the app just worked — on the 3rd, 10th and 25th save, and at most
/// once per app version. iOS still decides whether the sheet appears (it
/// shows it at most three times a year).
enum ReviewPrompt {
    static let milestones: Set<Int> = [3, 10, 25]

    static let savedCountKey = "reviewPrompt.savedCount"
    static let lastVersionKey = "reviewPrompt.lastVersion"

    static func shouldAsk(savedCount: Int, lastAskedVersion: String, currentVersion: String) -> Bool {
        milestones.contains(savedCount) && lastAskedVersion != currentVersion
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
