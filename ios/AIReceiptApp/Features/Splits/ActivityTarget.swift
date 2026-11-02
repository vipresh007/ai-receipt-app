import SwiftData
import SwiftUI

/// What an Activity row or a tapped notification is about: the receipt,
/// shared expense, group or person to open. Push payloads carry the same ids
/// under `target` (`backend/app/services/activity.py`).
struct ActivityTarget: Hashable, Identifiable {
    var receipt: String?
    var split: String?
    var group: String?
    var person: String?
    /// A comment: open the conversation rather than the receipt.
    var comments = false

    var id: String { [receipt, split, group, person].map { $0 ?? "-" }.joined(separator: "|") }
    var isEmpty: Bool { receipt == nil && split == nil && group == nil && person == nil }

    init(receipt: String? = nil, split: String? = nil, group: String? = nil, person: String? = nil, comments: Bool = false) {
        self.receipt = receipt
        self.split = split
        self.group = group
        self.person = person
        self.comments = comments
    }

    init(_ item: ReceiptExtractionAPIClient.ActivityItemDTO) {
        self.init(
            receipt: item.receiptId, split: item.splitId, group: item.groupId, person: item.personId,
            comments: item.kind == "comment"
        )
    }

    /// From a notification's `userInfo["target"]`.
    init?(push info: [AnyHashable: Any]) {
        guard let ids = info["target"] as? [String: Any] else { return nil }
        self.init(
            receipt: ids["receipt"] as? String,
            split: ids["split"] as? String,
            group: ids["group"] as? String,
            person: ids["person"] as? String,
            comments: (ids["kind"] as? String) == "comment"
        )
        if isEmpty { return nil }
    }
}

/// Opens an `ActivityTarget`: your copy of the receipt when you have one,
/// otherwise the shared expense's history, the person or the group.
struct ActivityDestination: View {
    typealias API = ReceiptExtractionAPIClient

    let target: ActivityTarget

    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @State private var resolved: Resolved?

    private enum Resolved {
        case receipt(Receipt)
        case split(API.SplitDTO)
        case comments(API.SplitDTO)
        case group(String)
        case person(String)
        case missing
    }

    var body: some View {
        Group {
            switch resolved {
            case nil:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .receipt(let receipt):
                ReceiptDetailView(receipt: receipt)
            case .split(let split):
                SharedExpenseView(split: split)
            case .comments(let split):
                SplitTimelineView(split: split)
            case .group(let id):
                GroupDetailView(groupID: id)
            case .person(let id):
                PersonDetailView(personID: id)
            case .missing:
                ContentUnavailableView(
                    "No longer here",
                    systemImage: "tray",
                    description: Text("It was deleted, or you're no longer on it.")
                )
            }
        }
        .background(Theme.Palette.bg.ignoresSafeArea())
        .task { if resolved == nil { await resolve() } }
    }

    private func resolve() async {
        if let id = target.receipt {
            if let receipt = local(remoteID: id) {
                return resolved = .receipt(receipt)
            }
            // Just arrived (an emailed receipt): fetch it, then look again.
            await AccountSync.pull(auth: auth, context: modelContext)
            if let receipt = local(remoteID: id) {
                return resolved = .receipt(receipt)
            }
        }
        if let id = target.split {
            if target.comments, let split = try? await Splits.client(auth).split(id: id) {
                return resolved = .comments(split)
            }
            if let receipt = local(splitID: id) {
                return resolved = .receipt(receipt)
            }
            if let split = try? await Splits.client(auth).split(id: id) {
                return resolved = .split(split)
            }
        }
        if let id = target.person { return resolved = .person(id) }
        if let id = target.group { return resolved = .group(id) }
        resolved = .missing
    }

    private func local(remoteID id: String) -> Receipt? {
        let wanted: String? = id
        return try? modelContext.fetch(FetchDescriptor<Receipt>(predicate: #Predicate { $0.remoteID == wanted })).first
    }

    private func local(splitID id: String) -> Receipt? {
        let wanted: String? = id
        return try? modelContext.fetch(FetchDescriptor<Receipt>(predicate: #Predicate { $0.splitID == wanted })).first
    }
}

/// Someone else's shared expense: what it came to, your share, who owes
/// what, and its history and comments.
struct SharedExpenseView: View {
    @State var split: ReceiptExtractionAPIClient.SplitDTO

    var body: some View {
        List {
            Section {
                LabeledContent("Total", value: money(split.totalValue))
                if let mine = split.myShareValue {
                    LabeledContent("Your share", value: money(mine))
                }
                LabeledContent("Date", value: split.day.formatted(.dateTime.month(.abbreviated).day().year()))
            }
            .listRowBackground(Theme.Palette.surface)
            Section("Who owes what") {
                SplitParticipantRows(split: split, onChange: { split = $0 })
            }
            .listRowBackground(Theme.Palette.surface)
        }
        .ledgerBackground()
        .background(Theme.Palette.bg.ignoresSafeArea())
        .navigationTitle(split.description)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func money(_ value: Decimal) -> String {
        value.formatted(.currency(code: split.currency))
    }
}

/// A tapped notification, shown over whatever tab you're on.
struct ActivityTargetSheet: View {
    let target: ActivityTarget
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ActivityDestination(target: target)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
