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
    @State private var pickingReceipt = false
    @State private var pendingReceipt: Receipt?
    @State private var receiptToSplit: Receipt?
    @State private var scanning = false
    @State private var scanStatus: String?
    @State private var editingSplit: API.SplitDTO?
    @State private var payment: PaymentDraft?
    @State private var newMember = ""
    @State private var confirmingDelete = false
    @State private var notice: String?
    @State private var addingMember = false
    @State private var newMemberEmail = ""
    @State private var invitingMember: API.GroupMemberDTO?
    @State private var inviteEmail = ""

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
        .sheet(isPresented: $pickingReceipt, onDismiss: {
            // One sheet at a time: open the editor once the picker is gone.
            receiptToSplit = pendingReceipt
            pendingReceipt = nil
        }) {
            ReceiptPickerSheet { pendingReceipt = $0 }
        }
        .scanToSplit(isPresented: $scanning, ready: $receiptToSplit, status: $scanStatus)
        .sheet(item: $receiptToSplit) { receipt in
            if let group {
                SplitEditorView(receipt: receipt, group: group) { saved in
                    receipt.myShare = saved.myShareValue
                    receipt.splitID = saved.id
                    try? modelContext.save()
                    Task { await changed() }
                }
            }
        }
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
        .alert("Add someone", isPresented: $addingMember) {
            TextField("Name", text: $newMember)
                .textContentType(.name)
            TextField("Email (optional)", text: $newMemberEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            Button("Add") { Task { await addMember() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("With an email, Tally sends them the invite with their name already picked.")
        }
        .alert(
            "Invite \(invitingMember?.displayName ?? "")",
            isPresented: Binding(get: { invitingMember != nil }, set: { if !$0 { invitingMember = nil } })
        ) {
            TextField("Email", text: $inviteEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            Button("Send") { Task { await sendInvite() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tally emails them the invite with their name already picked.")
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

            peopleSection(group)
            expensesSection(group)
            if !group.settlements.isEmpty { paymentsSection(group) }

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

    /// Everyone in the group, where each stands with you, and what to do
    /// about it; then adding people, the invite, and simplify debts.
    private func peopleSection(_ group: API.GroupDetailDTO) -> some View {
        let me = group.members.first(where: \.isMe)
        let others = group.payments.filter { $0.fromMemberId != me?.id && $0.toMemberId != me?.id }
        return Section {
            ForEach(group.members.filter { !$0.isMe }) { m in
                let owed = withMe(m, in: group)
                let elsewhere = m.balanceValue - owed
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack(spacing: Theme.Space.md) {
                        Text(m.displayName.prefix(1).uppercased())
                            .font(.appCallout.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .background(Theme.Palette.surface2, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(m.displayName).font(.appCallout.weight(.medium))
                                if !m.hasAccount {
                                    Text("not joined")
                                        .font(.system(size: 10.5))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Theme.Palette.surface2, in: Capsule())
                                        .foregroundStyle(Theme.Palette.textTertiary)
                                }
                            }
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
                        .padding(.leading, 46)
                    }
                    if owed < 0, let payTo = m.payTo {
                        PayToView(payTo: payTo, amount: -owed, currency: group.currency, name: m.displayName)
                            .padding(.leading, 46)
                    }
                    if !m.hasAccount {
                        HStack(spacing: 6) {
                            if let email = m.email {
                                Text(m.invitedAt != nil ? "Invite emailed to \(email)" : email)
                                    .lineLimit(1)
                                    .foregroundStyle(Theme.Palette.textTertiary)
                            }
                            Button(m.invitedAt != nil ? "Send again" : "Invite by email") {
                                inviteEmail = m.email ?? ""
                                invitingMember = m
                            }
                            .buttonStyle(.borderless)
                        }
                        .font(.appCaption)
                        .padding(.leading, 46)
                    }
                }
                .swipeActions {
                    if !m.hasAccount, owed == 0, abs(elsewhere) < 0.005 {
                        Button("Remove", role: .destructive) {
                            Task { await mutate { try await $0.removeMember(groupID: groupID, memberID: m.id) } }
                        }
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
                Text(notice).font(.appCaption).foregroundStyle(Theme.Palette.success)
            }
            Button {
                newMember = ""
                newMemberEmail = ""
                addingMember = true
            } label: {
                Label("Add someone", systemImage: "person.badge.plus")
            }
            if let url = URL(string: group.inviteUrl) {
                ShareLink(item: url, message: Text("Join \(group.name) on Tally to see what we've spent and who owes whom.")) {
                    Label("Send invite link", systemImage: "person.badge.plus")
                }
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
                Button("Record some other payment") {
                    payment = PaymentDraft(from: group.members.first { !$0.isMe }?.id ?? me.id, to: me.id, amount: nil)
                }
                .font(.appCaption)
            }
        } header: {
            Text("PEOPLE")
                .font(.appMicro)
                .tracking(1.4)
                .foregroundStyle(Theme.Palette.textTertiary)
        } footer: {
            Text("Invite people so they see the group too. They sign in and pick their name.")
                .font(.appCaption)
        }
        .listRowBackground(Theme.Palette.surface)
    }

    private func memberStatus(owed: Decimal, elsewhere: Decimal, currency: String) -> String {
        func money(_ value: Decimal) -> String { value.formatted(.currency(code: currency)) }
        if owed > 0 { return "owes you \(money(owed))" }
        if owed < 0 { return "you owe \(money(-owed))" }
        if abs(elsewhere) < 0.005 { return "settled up" }
        return elsewhere < 0 ? "owes others \(money(-elsewhere))" : "is owed \(money(elsewhere)) by others"
    }

    /// Expenses, newest first, under month headings.
    @ViewBuilder
    private func expensesSection(_ group: API.GroupDetailDTO) -> some View {
        let months = Dictionary(grouping: group.splits) { String($0.date.prefix(7)) }
            .sorted { $0.key > $1.key }
        Section {
            Menu {
                Button("Take a photo", systemImage: "camera") { scanning = true }
                Button("From a receipt", systemImage: "doc.text") { pickingReceipt = true }
                Button("Type it in", systemImage: "pencil") { addingExpense = true }
            } label: {
                Label("Add expense", systemImage: "plus")
            }
            if let scanStatus {
                HStack(spacing: Theme.Space.sm) {
                    if scanStatus.hasSuffix("…") { ProgressView() }
                    Text(scanStatus).font(.appCaption).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            if group.splits.isEmpty {
                Text("Add one here, or split a receipt with this group from the receipt itself.")
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        } header: {
            Text("EXPENSES").font(.appMicro).tracking(1.4).foregroundStyle(Theme.Palette.textTertiary)
        }
        .listRowBackground(Theme.Palette.surface)
        ForEach(months, id: \.key) { month, splits in
            Section {
                ForEach(splits.sorted { $0.date > $1.date }) { split in
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
            } header: {
                Text(monthTitle(month)).font(.appMicro).tracking(1.4).foregroundStyle(Theme.Palette.textTertiary)
            }
            .listRowBackground(Theme.Palette.surface)
        }
    }

    private func monthTitle(_ yearMonth: String) -> String {
        guard let day = API.isoDay(yearMonth + "-01") else { return yearMonth }
        return day.formatted(.dateTime.month(.wide).year()).uppercased()
    }

    private func paymentsSection(_ group: API.GroupDetailDTO) -> some View {
        LedgerSection("Payments") {
            ForEach(group.settlements) { s in
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
                    Text(s.amountValue, format: .currency(code: group.currency)).font(.appMoney)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        Task { await mutate { try await $0.deleteSettlement(groupID: groupID, id: s.id) } }
                    }
                }
            }
        }
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
        let email = newMemberEmail.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        await mutate { try await $0.addMember(groupID: groupID, name: name, email: email.isEmpty ? nil : email) }
        if errorMessage == nil {
            newMember = ""
            newMemberEmail = ""
            if !email.isEmpty { notice = "Added \(name) and emailed the invite." }
        }
    }

    private func sendInvite() async {
        guard let member = invitingMember else { return }
        let email = inviteEmail.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty else { return }
        await mutate { try await $0.inviteMember(groupID: groupID, memberID: member.id, email: email) }
        if errorMessage == nil { notice = "Invite emailed to \(email)." }
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
