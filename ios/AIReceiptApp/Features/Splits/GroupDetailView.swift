import SwiftUI
import SwiftData

/// One group: who owes whom (with the payments that would square everyone),
/// its expenses, payments made, and the people in it.
struct GroupDetailView: View {
    typealias API = ReceiptExtractionAPIClient

    let groupID: String
    /// Balances or the group itself changed (the list's badges follow).
    var onChange: () -> Void = {}

    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var group: API.GroupDetailDTO?
    @State private var errorMessage: String?
    @State private var addingExpense = false
    @State private var editingSplit: API.SplitDTO?
    @State private var payment: PaymentDraft?
    @State private var newMember = ""
    @State private var confirmingDelete = false
    @State private var notice: String?

    var body: some View {
        Group {
            if let group {
                content(group)
            } else if errorMessage != nil {
                ContentUnavailableView(
                    "Couldn't open this group",
                    systemImage: "person.3",
                    description: Text(errorMessage ?? "")
                )
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.Palette.bg.ignoresSafeArea())
        .navigationTitle(group?.name ?? "Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let group {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if let url = URL(string: group.inviteUrl) {
                            ShareLink(item: url, message: Text("Join \(group.name) on Tally to see what we've spent and who owes whom.")) {
                                Label("Send invite link", systemImage: "person.badge.plus")
                            }
                        }
                        if group.isOwner {
                            Button("Delete group", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .task { await load() }
        .liveRefresh { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $addingExpense) {
            if let group {
                SplitEditorView(group: group) { _ in Task { await changed() } }
            }
        }
        .sheet(item: $editingSplit) { split in
            if let group {
                SplitEditorView(group: group, existing: split) { _ in Task { await changed() } }
            }
        }
        .sheet(item: $payment) { draft in
            if let group {
                RecordPaymentSheet(group: group, draft: draft) { next in
                    self.group = next
                    onChange()
                }
            }
        }
        .confirmationDialog("Delete \(group?.name ?? "this group")?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete group", role: .destructive) { Task { await deleteGroup() } }
        } message: {
            Text("Its expenses and payments go too, for everyone. Receipts split in it count in full again.")
        }
    }

    // MARK: - Content

    private func content(_ group: API.GroupDetailDTO) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionLabel("\(group.members.count) \(group.members.count == 1 ? "person" : "people") · \(group.currency)")
                    Text(BalanceBadge.text(group.myBalanceValue, currency: group.currency))
                        .font(.display(30, relativeTo: .title))
                        .foregroundStyle(
                            group.myBalanceValue > 0 ? Theme.Palette.success
                                : group.myBalanceValue < 0 ? Theme.Palette.danger : Theme.Palette.text
                        )
                }
                .padding(.vertical, Theme.Space.xs)
            }
            .listRowBackground(Color.clear)

            balancesSection(group)
            timelineSection(group)
            peopleSection(group)

            if let errorMessage {
                Text(errorMessage)
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.danger)
                    .listRowBackground(Theme.Palette.surface)
            }
        }
        .ledgerBackground()
    }

    /// Between you and one member, as the group settles up: positive = they owe you.
    private func withMe(_ member: API.GroupMemberDTO, in group: API.GroupDetailDTO) -> Decimal {
        guard let me = group.members.first(where: \.isMe) else { return 0 }
        return group.payments.reduce(Decimal(0)) { sum, p in
            if p.fromMemberId == member.id && p.toMemberId == me.id { return sum + p.amountValue }
            if p.fromMemberId == me.id && p.toMemberId == member.id { return sum - p.amountValue }
            return sum
        }
    }

    private func balancesSection(_ group: API.GroupDetailDTO) -> some View {
        let me = group.members.first(where: \.isMe)
        let others = group.payments.filter { $0.fromMemberId != me?.id && $0.toMemberId != me?.id }
        return LedgerSection("Balances") {
            ForEach(group.members.filter { !$0.isMe }) { m in
                let owed = withMe(m, in: group)
                let elsewhere = m.balanceValue - owed
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack(spacing: Theme.Space.md) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.displayName).font(.appCallout.weight(.medium))
                            Text(memberStatus(owed: owed, elsewhere: elsewhere, currency: group.currency))
                                .font(.appCaption)
                                .foregroundStyle(
                                    owed > 0 ? Theme.Palette.success : owed < 0 ? Theme.Palette.danger : Theme.Palette.textTertiary
                                )
                        }
                        Spacer()
                        if owed != 0, let me {
                            Button("Record payment") {
                                payment = owed > 0
                                    ? PaymentDraft(from: m.id, to: me.id, amount: owed)
                                    : PaymentDraft(from: me.id, to: m.id, amount: -owed)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(Theme.Palette.accent)
                        }
                    }
                    if owed > 0, m.hasAccount {
                        Button("Remind \(m.displayName)") {
                            Task {
                                await mutate { try await $0.remindMember(groupID: groupID, memberID: m.id) }
                                if errorMessage == nil { notice = "Reminder sent to \(m.displayName)." }
                            }
                        }
                        .font(.appCaption)
                        .buttonStyle(.borderless)
                    }
                    if owed < 0, let payTo = m.payTo {
                        PayToView(payTo: payTo, amount: -owed, currency: group.currency, name: m.displayName)
                    }
                }
            }
            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Between others").font(.appCaption.weight(.medium)).foregroundStyle(Theme.Palette.textSecondary)
                    ForEach(others, id: \.self) { p in
                        HStack {
                            Text("\(group.memberName(p.fromMemberId)) owes \(group.memberName(p.toMemberId))")
                            Spacer()
                            Text(p.amountValue, format: .currency(code: group.currency)).monospacedDigit()
                        }
                        .font(.appCaption)
                    }
                }
            }
            if let notice {
                Text(notice)
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.success)
            }
            Toggle(
                isOn: Binding(
                    get: { group.simplifyDebts },
                    set: { on in Task { await mutate { try await $0.setSimplifyDebts(groupID: groupID, on) } } }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Simplify debts").font(.appCallout)
                    Text(
                        group.simplifyDebts
                            ? "Fewest payments: if you owe Sam and Sam owes Kim, you pay Kim directly."
                            : "Everyone pays back whoever they owe, expense by expense."
                    )
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            if group.members.count > 1, let me {
                Button("Other payment") {
                    payment = PaymentDraft(from: group.members.first { !$0.isMe }?.id ?? me.id, to: me.id, amount: nil)
                }
            }
        }
    }

    private func memberStatus(owed: Decimal, elsewhere: Decimal, currency: String) -> String {
        func money(_ value: Decimal) -> String { value.formatted(.currency(code: currency)) }
        if owed > 0 { return "owes you \(money(owed))" }
        if owed < 0 { return "you owe \(money(-owed))" }
        if abs(elsewhere) < 0.005 { return "settled up" }
        return elsewhere < 0 ? "owes others \(money(-elsewhere))" : "is owed \(money(elsewhere)) by others"
    }

    /// Expenses and payments together, newest first: a payment is part of
    /// the story ("Mit paid you $100"), not a separate list.
    private func timelineSection(_ group: API.GroupDetailDTO) -> some View {
        enum Entry: Identifiable {
            case expense(API.SplitDTO)
            case payment(API.SettlementDTO)
            var id: String {
                switch self {
                case .expense(let s): "s-\(s.id)"
                case .payment(let p): "p-\(p.id)"
                }
            }
            var date: String {
                switch self {
                case .expense(let s): s.date
                case .payment(let p): p.date
                }
            }
        }
        let entries = (group.splits.map(Entry.expense) + group.settlements.map(Entry.payment))
            .sorted { $0.date > $1.date }
        return Section {
            Button {
                addingExpense = true
            } label: {
                Label("Add expense", systemImage: "plus")
            }
            if entries.isEmpty {
                Text("Add one here, or split a receipt with this group from the receipt itself.")
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            ForEach(entries) { entry in
                switch entry {
                case .payment(let s):
                    HStack(spacing: Theme.Space.md) {
                        Image(systemName: "banknote")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.success)
                            .frame(width: 28, height: 28)
                            .background(Theme.Palette.success.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(group.memberName(s.fromMemberId)) paid \(group.memberName(s.toMemberId))")
                                .font(.appCallout)
                            if let day = API.isoDay(s.date) {
                                Text(day, format: .dateTime.month(.abbreviated).day())
                                    .font(.appCaption)
                                    .foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                        Spacer()
                        Text(s.amountValue, format: .currency(code: group.currency))
                            .font(.appMoney)
                            .foregroundStyle(Theme.Palette.success)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            Task { await mutate { try await $0.deleteSettlement(groupID: groupID, id: s.id) } }
                        }
                    }
                case .expense(let split):
                    DisclosureGroup {
                        SplitParticipantRows(split: split, onChange: { _ in Task { await load() } })
                        if split.receiptId != nil && split.isOwner {
                            Text("Split from your receipt. Edit it from the receipt.")
                                .font(.appCaption)
                                .foregroundStyle(Theme.Palette.textTertiary)
                        } else if split.canEdit {
                            Button("Edit expense") { editingSplit = split }
                        }
                        if split.isOwner {
                            Button("Remove expense", role: .destructive) { Task { await removeSplit(split) } }
                        }
                    } label: {
                        SharedExpenseRow(split: split)
                    }
                }
            }
        } header: {
            Text("EXPENSES & PAYMENTS")
                .font(.appMicro)
                .tracking(1.4)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .listRowBackground(Theme.Palette.surface)
    }

    private func peopleSection(_ group: API.GroupDetailDTO) -> some View {
        Section {
            ForEach(group.members) { m in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.isMe ? "\(m.displayName) (you)" : m.displayName).font(.appCallout)
                        if !m.hasAccount {
                            Text("Hasn't joined yet")
                                .font(.appCaption)
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    Spacer()
                    if m.hasAccount {
                        Text("On Tally").font(.appCaption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                .swipeActions {
                    if !m.hasAccount {
                        Button("Remove", role: .destructive) {
                            Task { await mutate { try await $0.removeMember(groupID: groupID, memberID: m.id) } }
                        }
                    }
                }
            }
            HStack {
                TextField("Add a name", text: $newMember)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .onSubmit { Task { await addMember() } }
                Button("Add") { Task { await addMember() } }
                    .disabled(newMember.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let url = URL(string: group.inviteUrl) {
                ShareLink(item: url, message: Text("Join \(group.name) on Tally to see what we've spent and who owes whom.")) {
                    Label("Send invite link", systemImage: "person.badge.plus")
                }
            }
        } header: {
            Text("PEOPLE")
                .font(.appMicro)
                .tracking(1.4)
                .foregroundStyle(Theme.Palette.textTertiary)
        } footer: {
            Text("Each person opens the invite, signs in, and picks their name, so they see the group too.")
                .font(.appCaption)
        }
        .listRowBackground(Theme.Palette.surface)
    }

    // MARK: - Actions

    private func load() async {
        do {
            group = try await Splits.client(auth).group(id: groupID)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// After an expense is added, edited or removed: balances move, and a
    /// receipt split here changes what counts toward your spending.
    private func changed() async {
        await load()
        onChange()
        await AccountSync.pull(auth: auth, context: modelContext)
    }

    private func mutate(_ action: (API) async throws -> API.GroupDetailDTO) async {
        do {
            group = try await action(try await Splits.client(auth))
            errorMessage = nil
            onChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addMember() async {
        let name = newMember.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        await mutate { try await $0.addMember(groupID: groupID, name: name) }
        if errorMessage == nil { newMember = "" }
    }

    private func removeSplit(_ split: API.SplitDTO) async {
        do {
            try await Splits.client(auth).deleteSplit(id: split.id)
            await changed()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteGroup() async {
        do {
            try await Splits.client(auth).deleteGroup(id: groupID)
            onChange()
            await AccountSync.pull(auth: auth, context: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PaymentDraft: Identifiable {
    let id = UUID()
    var from: String
    var to: String
    var amount: Decimal?
}

/// "Kim paid Alex $45": records money that changed hands outside Tally.
private struct RecordPaymentSheet: View {
    let group: ReceiptExtractionAPIClient.GroupDetailDTO
    @State var draft: PaymentDraft
    let onSaved: (ReceiptExtractionAPIClient.GroupDetailDTO) -> Void

    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                LedgerSection {
                    Picker("Who paid", selection: $draft.from) {
                        ForEach(group.members) { Text($0.isMe ? "You" : $0.displayName).tag($0.id) }
                    }
                    Picker("To", selection: $draft.to) {
                        ForEach(group.members) { Text($0.isMe ? "You" : $0.displayName).tag($0.id) }
                    }
                    LabeledContent("Amount") {
                        TextField("0.00", value: $draft.amount, format: .currency(code: group.currency))
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
                            .disabled(draft.from == draft.to || (draft.amount ?? 0) <= 0)
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
            let next = try await Splits.client(auth).addSettlement(
                groupID: group.id, from: draft.from, to: draft.to, amount: draft.amount ?? 0
            )
            onSaved(next)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
