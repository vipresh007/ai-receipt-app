import SwiftUI
import SwiftData

/// One person you split with outside groups: where you stand, settling up,
/// what you've shared, and inviting them (link or email).
struct PersonDetailView: View {
    typealias API = ReceiptExtractionAPIClient

    let personID: String
    /// The balance or the person changed (the list's badges follow).
    var onChange: () -> Void = {}

    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var person: API.PersonDetailDTO?
    @State private var errorMessage: String?
    @State private var addingExpense = false
    @State private var editingSplit: API.SplitDTO?
    @State private var recordingPayment = false
    @State private var email = ""
    @State private var inviteNote: String?
    @State private var sendingInvite = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingRemove = false

    var body: some View {
        Group {
            if let person {
                content(person)
            } else if errorMessage != nil {
                ContentUnavailableView("Couldn't open this person", systemImage: "person", description: Text(errorMessage ?? ""))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.Palette.bg.ignoresSafeArea())
        .navigationTitle(person?.name ?? "Person")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let person {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Rename", systemImage: "pencil") {
                            newName = person.name
                            renaming = true
                        }
                        Button("Remove \(person.name)", systemImage: "trash", role: .destructive) { confirmingRemove = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $addingExpense) {
            if let person {
                SplitEditorView(withPeople: [PickedPerson(id: person.id, name: person.name)]) { _ in
                    Task { await changed() }
                }
            }
        }
        .sheet(item: $editingSplit) { split in
            SplitEditorView(existing: split) { _ in Task { await changed() } }
        }
        .sheet(isPresented: $recordingPayment) {
            if let person {
                PersonPaymentSheet(person: person) { next in
                    self.person = next
                    onChange()
                }
            }
        }
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") { Task { await rename() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Remove \(person?.name ?? "them")?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await remove() } }
        } message: {
            Text("Expenses keep their name; payments with them are deleted.")
        }
    }

    // MARK: - Content

    private func content(_ person: API.PersonDetailDTO) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionLabel(person.hasAccount ? "On Tally" : person.email ?? "Just a name")
                    Text(balanceText(person))
                        .font(.display(30, relativeTo: .title))
                        .foregroundStyle(
                            person.balanceValue > 0 ? Theme.Palette.success
                                : person.balanceValue < 0 ? Theme.Palette.danger : Theme.Palette.text
                        )
                    Button("Record a payment") { recordingPayment = true }
                        .buttonStyle(.bordered)
                        .tint(Theme.Palette.accent)
                        .padding(.top, Theme.Space.xs)
                }
                .padding(.vertical, Theme.Space.xs)
            }
            .listRowBackground(Color.clear)

            expensesSection(person)
            if !person.payments.isEmpty { paymentsSection(person) }
            inviteSection(person)

            if let errorMessage {
                Text(errorMessage)
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.danger)
                    .listRowBackground(Theme.Palette.surface)
            }
        }
        .ledgerBackground()
    }

    private func balanceText(_ person: API.PersonDetailDTO) -> String {
        let amount = abs(person.balanceValue).formatted(.currency(code: person.currency))
        if person.balanceValue > 0 { return "\(person.name) owes you \(amount)" }
        if person.balanceValue < 0 { return "You owe \(person.name) \(amount)" }
        return "All square"
    }

    private func expensesSection(_ person: API.PersonDetailDTO) -> some View {
        Section {
            Button {
                addingExpense = true
            } label: {
                Label("Add expense", systemImage: "plus")
            }
            if person.splits.isEmpty {
                Text("Nothing shared yet. Add an expense, or split a receipt with \(person.name) from the receipt.")
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            ForEach(person.splits) { split in
                DisclosureGroup {
                    SplitParticipantRows(split: split, onChange: { _ in Task { await load() } })
                    if split.isOwner {
                        if split.receiptId == nil {
                            Button("Edit expense") { editingSplit = split }
                        } else {
                            Text("Split from a receipt. Edit it from the receipt.")
                                .font(.appCaption)
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                        Button("Remove expense", role: .destructive) { Task { await removeSplit(split) } }
                    }
                } label: {
                    SharedExpenseRow(split: split)
                }
            }
        } header: {
            Text("EXPENSES")
                .font(.appMicro)
                .tracking(1.4)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .listRowBackground(Theme.Palette.surface)
    }

    private func paymentsSection(_ person: API.PersonDetailDTO) -> some View {
        LedgerSection("Payments") {
            ForEach(person.payments) { payment in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(payment.youPaid ? "You paid \(person.name)" : "\(person.name) paid you")
                            .font(.appCallout)
                        if let day = API.isoDay(payment.date) {
                            Text(day, format: .dateTime.month().day())
                                .font(.appCaption)
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    Spacer()
                    Text(payment.amountValue, format: .currency(code: person.currency)).font(.appMoney)
                }
                .swipeActions {
                    if payment.canDelete {
                        Button("Delete", role: .destructive) {
                            Task { await mutate { try await $0.deletePersonPayment(personID: personID, id: payment.id) } }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func inviteSection(_ person: API.PersonDetailDTO) -> some View {
        if person.hasAccount {
            LedgerSection("On Tally") {
                Text("\(person.name) accepted your invite and sees what you share, from their side.")
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        } else {
            Section {
                if let url = URL(string: person.inviteUrl) {
                    ShareLink(item: url, message: Text("I'm keeping track of what we share on Tally. See it here:")) {
                        Label("Send invite link", systemImage: "square.and.arrow.up")
                    }
                }
                HStack {
                    TextField("Their email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if sendingInvite {
                        ProgressView()
                    } else {
                        Button("Email invite") { Task { await sendInvite() } }
                            .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if let inviteNote {
                    Text(inviteNote)
                        .font(.appCaption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else if let sent = person.invitedAt.flatMap({ API.isoDay(String($0.prefix(10))) }) {
                    Text("Invite emailed \(sent.formatted(.dateTime.month().day())).")
                        .font(.appCaption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            } header: {
                Text("INVITE \(person.name.uppercased())")
                    .font(.appMicro)
                    .tracking(1.4)
                    .foregroundStyle(Theme.Palette.textTertiary)
            } footer: {
                Text("Once they sign in from the invite, they see every expense you share and the balance, from their side.")
                    .font(.appCaption)
            }
            .listRowBackground(Theme.Palette.surface)
        }
    }

    // MARK: - Actions

    private func load() async {
        do {
            let loaded = try await Splits.client(auth).person(id: personID)
            if person == nil || email.isEmpty { email = loaded.email ?? "" }
            person = loaded
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// An expense was added, edited or removed: the balance moves, and a
    /// receipt split here changes what counts toward your spending.
    private func changed() async {
        await load()
        onChange()
        await AccountSync.pull(auth: auth, context: modelContext)
    }

    private func mutate(_ action: (API) async throws -> API.PersonDetailDTO) async {
        do {
            person = try await action(try await Splits.client(auth))
            errorMessage = nil
            onChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendInvite() async {
        guard let person else { return }
        sendingInvite = true
        defer { sendingInvite = false }
        inviteNote = nil
        do {
            let client = try await Splits.client(auth)
            var current = person
            let address = email.trimmingCharacters(in: .whitespaces)
            if address.lowercased() != (person.email ?? "") {
                current = try await client.updatePerson(id: person.id, email: address)
                self.person = current
            }
            guard current.canEmail else {
                inviteNote = "Email invites aren't available yet. Send the invite link instead."
                return
            }
            self.person = try await client.invitePerson(id: person.id)
            inviteNote = "Invite sent to \(current.email ?? address)."
            onChange()
        } catch {
            inviteNote = error.localizedDescription
        }
    }

    private func rename() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        await mutate { try await $0.updatePerson(id: personID, name: name) }
    }

    private func removeSplit(_ split: API.SplitDTO) async {
        do {
            try await Splits.client(auth).deleteSplit(id: split.id)
            await changed()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove() async {
        do {
            try await Splits.client(auth).deletePerson(id: personID)
            onChange()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// An expense row: what, when, who paid, and your share.
struct SharedExpenseRow: View {
    let split: ReceiptExtractionAPIClient.SplitDTO

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if split.receiptId != nil {
                        Image(systemName: "doc.text")
                            .font(.appCaption)
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Text(split.description.isEmpty ? "Expense" : split.description)
                        .font(.appCallout.weight(.medium))
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if let mine = split.myShareValue {
                    Text(mine, format: .currency(code: split.currency)).font(.appMoney)
                    Text("your share")
                        .font(.appCaption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                } else {
                    Text("not in it")
                        .font(.appCaption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
    }

    private var subtitle: String {
        let day = split.day.formatted(.dateTime.month(.abbreviated).day())
        let total = split.totalValue.formatted(.currency(code: split.currency))
        guard let payer = split.payer else { return "\(day) · \(total)" }
        return "\(day) · \(payer.isMe ? "You" : payer.displayName) paid \(total)"
    }
}

/// "Sam paid me $40" / "I paid Sam $40".
private struct PersonPaymentSheet: View {
    let person: ReceiptExtractionAPIClient.PersonDetailDTO
    let onSaved: (ReceiptExtractionAPIClient.PersonDetailDTO) -> Void

    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var youPaid: Bool
    @State private var amount: Decimal?
    @State private var saving = false
    @State private var errorMessage: String?

    init(person: ReceiptExtractionAPIClient.PersonDetailDTO, onSaved: @escaping (ReceiptExtractionAPIClient.PersonDetailDTO) -> Void) {
        self.person = person
        self.onSaved = onSaved
        // Default to the payment that would square things up.
        _youPaid = State(initialValue: person.balanceValue < 0)
        _amount = State(initialValue: person.balanceValue == 0 ? nil : abs(person.balanceValue))
    }

    var body: some View {
        NavigationStack {
            Form {
                LedgerSection {
                    Picker("Who paid", selection: $youPaid) {
                        Text("\(person.name) paid me").tag(false)
                        Text("I paid \(person.name)").tag(true)
                    }
                    LabeledContent("Amount") {
                        TextField("0.00", value: $amount, format: .currency(code: person.currency))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                }
                Section {
                    Text("Tally only keeps track. Send the money however you normally do.")
                        .font(.appCaption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.appCaption)
                            .foregroundStyle(Theme.Palette.danger)
                    }
                }
                .listRowBackground(Color.clear)
            }
            .ledgerBackground()
            .navigationTitle("Record payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled((amount ?? 0) <= 0)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let next = try await Splits.client(auth).addPersonPayment(
                personID: person.id, youPaid: youPaid, amount: amount ?? 0
            )
            onSaved(next)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
