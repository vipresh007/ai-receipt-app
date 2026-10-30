import SwiftUI

/// Who owes what on a split, one row per person, for use inside a `Form` or
/// `List` section. The split's owner gets each person's link to send (their
/// share, no account needed) and, on one-off splits, a paid tick.
struct SplitParticipantRows: View {
    typealias API = ReceiptExtractionAPIClient

    let split: API.SplitDTO
    let onChange: (API.SplitDTO) -> Void

    @Environment(AuthManager.self) private var auth
    @State private var busy: String?

    var body: some View {
        rows
        if !split.repeat.isEmpty {
            Label(
                split.repeat == "weekly" ? "Repeats every week" : "Repeats every month",
                systemImage: "repeat"
            )
            .font(.appCaption)
            .foregroundStyle(Theme.Palette.textTertiary)
        }
        NavigationLink {
            SplitTimelineView(split: split)
        } label: {
            Label("History & comments", systemImage: "text.bubble")
                .font(.appCallout)
        }
    }

    @ViewBuilder
    private var rows: some View {
        ForEach(split.participants) { person in
            let owes = !person.isPayer && person.shareValue > 0
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.isMe ? "You" : person.displayName)
                        .font(.appCallout)
                        .foregroundStyle(Theme.Palette.text)
                    Text(status(person))
                        .font(.appCaption)
                        .foregroundStyle(person.settled ? Theme.Palette.success : Theme.Palette.textTertiary)
                }
                Spacer()
                Text(person.shareValue, format: .currency(code: split.currency))
                    .font(.appMoney)
                    .strikethrough(person.settled)
                    .foregroundStyle(person.settled ? Theme.Palette.textTertiary : Theme.Palette.text)
                if owes, split.canEdit {
                    Button {
                        Task { await toggleSettled(person) }
                    } label: {
                        Image(systemName: person.settled ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(person.settled ? Theme.Palette.success : Theme.Palette.textTertiary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(busy == person.id)
                    .accessibilityLabel(
                        person.settled ? "Paid back. Mark \(person.displayName) as not paid" : "Mark \(person.displayName) as paid"
                    )
                }
                if !person.isMe, split.isOwner, !person.settled, let url = URL(string: person.shareUrl) {
                    ShareLink(item: url, message: Text(shareMessage(person))) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Send \(person.displayName) their share")
                }
            }
        }
    }

    /// "paid $300.00" for whoever paid; "owes Vipresh" / "paid back" for the rest.
    private func status(_ person: API.ParticipantDTO) -> String {
        if person.isPayer {
            let paid = Decimal(string: person.paid ?? "") ?? split.totalValue
            return "paid \(paid.formatted(.currency(code: split.currency)))"
        }
        if person.settled { return "paid back" }
        let payers = split.payers
        if payers.count == 1 { return "owes \(payers[0].isMe ? "you" : payers[0].displayName)" }
        return "owes the payers"
    }

    private func shareMessage(_ person: API.ParticipantDTO) -> String {
        let what = split.description.isEmpty ? "our split" : split.description
        return "Your share of \(what): \(person.shareValue.formatted(.currency(code: split.currency)))"
    }

    private func toggleSettled(_ person: API.ParticipantDTO) async {
        busy = person.id
        defer { busy = nil }
        guard let client = try? await Splits.client(auth),
            let next = try? await client.setSettled(splitID: split.id, participantID: person.id, settled: !person.settled)
        else { return }
        onChange(next)
    }
}

/// The "Split" section of a receipt: start a split, or see and manage it.
struct ReceiptSplitSection: View {
    typealias API = ReceiptExtractionAPIClient

    @Bindable var receipt: Receipt
    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext

    @State private var split: API.SplitDTO?
    @State private var editing = false
    @State private var preparing = false
    @State private var confirmingRemove = false
    @State private var errorMessage: String?

    var body: some View {
        LedgerSection("Split") {
            if !auth.isSignedIn {
                Text("Sign in to split this with others and send each person what they owe.")
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            } else if receipt.remoteID == nil {
                Text("This receipt hasn't synced to your account yet.")
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            } else if let split {
                SplitParticipantRows(split: split, onChange: { self.split = $0 })
                if split.isOwner {
                    Button("Edit split") { Task { await openEditor() } }
                    Button("Remove split", role: .destructive) { confirmingRemove = true }
                }
            } else if receipt.splitID != nil {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Button {
                    Task { await openEditor() }
                } label: {
                    HStack {
                        Label("Split this receipt", systemImage: "person.2")
                        Spacer()
                        if preparing { ProgressView() }
                    }
                }
                .disabled(preparing)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.danger)
            }
        }
        .task(id: receipt.splitID) { await load() }
        .liveRefresh { await reload() }
        .sheet(isPresented: $editing) {
            SplitEditorView(receipt: receipt, existing: split) { saved in
                split = saved
                receipt.myShare = saved.myShareValue
                receipt.splitID = saved.id
                try? modelContext.save()
            }
        }
        .confirmationDialog("Remove this split?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove split", role: .destructive) { Task { await remove() } }
        } message: {
            Text("The receipt will count in full toward your spending again, and the links you sent stop working.")
        }
    }

    private func load() async {
        guard let id = receipt.splitID else {
            split = nil
            return
        }
        guard split?.id != id else { return }
        do {
            split = try await Splits.client(auth).split(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Someone else on it may have changed the amounts: fetch it again, and
    /// keep this receipt's share (your spending) in step.
    private func reload() async {
        guard let id = receipt.splitID, let fresh = try? await Splits.client(auth).split(id: id) else {
            return
        }
        split = fresh
        if receipt.myShare != fresh.myShareValue {
            receipt.myShare = fresh.myShareValue
            try? modelContext.save()
        }
    }

    /// The split is computed from the server's copy of the receipt, so send
    /// any edits made on this screen first.
    private func openEditor() async {
        preparing = true
        defer { preparing = false }
        await AccountSync.pushUpdate(receipt, auth: auth)
        editing = true
    }

    private func remove() async {
        guard let split else { return }
        do {
            try await Splits.client(auth).deleteSplit(id: split.id)
            self.split = nil
            receipt.myShare = nil
            receipt.splitID = nil
            try? modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
