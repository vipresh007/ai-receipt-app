import SwiftUI

/// Split a receipt with people (or a group), or add an expense to a group.
/// Shares preview live with `SplitMath`; the saved split comes back in
/// `onDone` with the server's numbers. See docs/SPLITS.md.
struct SplitEditorView: View {
    typealias API = ReceiptExtractionAPIClient

    /// The receipt being split (already on the account), or nil for a new
    /// group expense typed in by hand.
    let receipt: Receipt?
    let fixedGroup: API.GroupDetailDTO?
    let existing: API.SplitDTO?
    let onDone: (API.SplitDTO) -> Void

    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var groups: [API.GroupSummaryDTO] = []
    /// "" = split with people, no group.
    @State private var groupID: String
    @State private var group: API.GroupDetailDTO?

    // A hand-entered expense (no receipt).
    @State private var description: String
    @State private var amount: Decimal?
    @State private var date: Date

    // One-off: you, plus typed names.
    @State private var includeMe: Bool
    @State private var names: [NamedPerson]
    // Group: who's in (nil = everyone), and who paid.
    @State private var included: Set<String>?
    @State private var payerID: String

    @State private var mode: SplitMath.Mode
    @State private var assigned: [String: Set<Int>]
    @State private var amounts: [String: Decimal]
    @State private var saving = false
    @State private var errorMessage: String?

    init(
        receipt: Receipt? = nil,
        group: API.GroupDetailDTO? = nil,
        existing: API.SplitDTO? = nil,
        onDone: @escaping (API.SplitDTO) -> Void
    ) {
        self.receipt = receipt
        self.fixedGroup = group
        self.existing = existing
        self.onDone = onDone

        let others: [NamedPerson] =
            existing.map { split in
                split.groupId == nil
                    ? split.participants.filter { !$0.isMe }.map { NamedPerson(name: $0.displayName) } : []
            } ?? []
        var assigned: [String: Set<Int>] = [:]
        var amounts: [String: Decimal] = [:]
        var payer = ""
        var nextOther = 0
        for p in existing?.participants ?? [] {
            let key: String
            if let member = p.memberId {
                key = member
            } else if p.isMe {
                key = NamedPerson.meKey
            } else {
                guard nextOther < others.count else { continue }
                key = others[nextOther].id
                nextOther += 1
            }
            assigned[key] = Set(p.itemIndexes)
            if let amount = p.amount.flatMap({ Decimal(string: $0) }) { amounts[key] = amount }
            if p.isPayer, let member = p.memberId { payer = member }
        }

        _groupID = State(initialValue: group?.id ?? existing?.groupId ?? "")
        _group = State(initialValue: group)
        _description = State(initialValue: existing?.description ?? "")
        _amount = State(initialValue: receipt == nil ? existing?.totalValue : nil)
        _date = State(initialValue: existing?.day ?? .now)
        _includeMe = State(initialValue: existing.map { $0.participants.contains(where: \.isMe) } ?? true)
        _names = State(initialValue: others.isEmpty ? [NamedPerson(name: "")] : others)
        _included = State(
            initialValue: existing?.groupId != nil ? Set(existing!.participants.compactMap(\.memberId)) : nil
        )
        _payerID = State(initialValue: payer)
        _mode = State(initialValue: existing?.mode ?? .even)
        _assigned = State(initialValue: assigned)
        _amounts = State(initialValue: amounts)
    }

    // MARK: - Derived

    private struct Person: Identifiable {
        let key: String
        let label: String
        let isMe: Bool
        let memberID: String?
        var id: String { key }
    }

    private var people: [Person] {
        if !groupID.isEmpty {
            guard let group else { return [] }
            return group.members
                .filter { included?.contains($0.id) ?? true }
                .map { Person(key: $0.id, label: $0.isMe ? "You" : $0.displayName, isMe: $0.isMe, memberID: $0.id) }
        }
        var list = includeMe ? [Person(key: NamedPerson.meKey, label: "You", isMe: true, memberID: nil)] : []
        for (i, person) in names.enumerated() {
            let name = person.name.trimmingCharacters(in: .whitespaces)
            list.append(Person(key: person.id, label: name.isEmpty ? "Person \(i + 1)" : name, isMe: false, memberID: nil))
        }
        return list
    }

    private var items: [(name: String, price: Decimal)] {
        if let receipt { return receipt.items.map { ($0.name, $0.price) } }
        return (existing?.items ?? []).map { ($0.name, Decimal(string: $0.price) ?? 0) }
    }

    private var total: Decimal { receipt?.total ?? amount ?? 0 }

    private var currencyCode: String {
        group?.currency ?? existing?.currency ?? Locale.current.currency?.identifier ?? "USD"
    }

    private var effectivePayer: String {
        payerID.isEmpty ? (group?.members.first(where: \.isMe)?.id ?? "") : payerID
    }

    private var preview: Result<[Decimal], SplitMath.Failure> {
        SplitMath.shares(
            total: total,
            mode: mode,
            inputs: people.map { .init(itemIndexes: assigned[$0.key] ?? [], amount: amounts[$0.key]) },
            itemPrices: items.map(\.price)
        )
    }

    private var previewProblem: String? {
        switch preview {
        case .success: nil
        case .failure(.noPeople): "Add at least one person."
        case .failure(.missingAmount): "Enter an amount for everyone."
        case .failure(.amountsDontAddUp(let total, let entered)):
            "Amounts add up to \(money(entered)), not \(money(total))."
        }
    }

    private var canSave: Bool {
        guard !saving, case .success = preview, people.count > 1 || !groupID.isEmpty else { return false }
        if receipt == nil {
            return !description.trimmingCharacters(in: .whitespaces).isEmpty && (amount ?? 0) > 0
        }
        return true
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                expenseSection
                withSection
                modeSection
                if mode == .items { itemsSection }
                sharesSection
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.appCaption)
                            .foregroundStyle(Theme.Palette.danger)
                    }
                    .listRowBackground(Theme.Palette.surface)
                }
            }
            .ledgerBackground()
            .navigationTitle(existing == nil ? (receipt == nil ? "Add expense" : "Split receipt") : "Edit split")
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
                            .disabled(!canSave)
                    }
                }
            }
            .task { await loadGroups() }
            .task(id: groupID) { await loadGroup() }
        }
    }

    @ViewBuilder
    private var expenseSection: some View {
        if let receipt {
            LedgerSection("Receipt") {
                LabeledContent(receipt.merchant.isEmpty ? "Receipt" : receipt.merchant) {
                    Text(receipt.total, format: .currency(code: currencyCode))
                        .font(.appMoney)
                }
            }
        } else {
            LedgerSection("Expense") {
                TextField("What was it?", text: $description)
                LabeledContent("Amount") {
                    TextField("0.00", value: $amount, format: .currency(code: currencyCode))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
        }
    }

    @ViewBuilder
    private var withSection: some View {
        LedgerSection("Split with") {
            if fixedGroup == nil {
                Picker("Split with", selection: $groupID) {
                    Text("People").tag("")
                    ForEach(groups) { Text($0.name).tag($0.id) }
                }
                .onChange(of: groupID) { _, _ in
                    included = nil
                    payerID = ""
                }
            }

            if groupID.isEmpty {
                Toggle("Include me", isOn: $includeMe)
                ForEach($names) { $person in
                    TextField("Name", text: $person.name)
                        .textContentType(.name)
                }
                .onDelete { names.remove(atOffsets: $0) }
                Button {
                    names.append(NamedPerson(name: ""))
                } label: {
                    Label("Add someone", systemImage: "plus")
                }
            } else if let group {
                ForEach(group.members) { member in
                    Toggle(member.isMe ? "\(member.displayName) (you)" : member.displayName, isOn: memberIncluded(member.id))
                }
                Picker("Paid by", selection: Binding(get: { effectivePayer }, set: { payerID = $0 })) {
                    ForEach(people) { Text($0.label).tag($0.memberID ?? "") }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
    }

    private var modeSection: some View {
        LedgerSection("How") {
            Picker("Split", selection: $mode) {
                ForEach(SplitMath.Mode.allCases.filter { $0 != .items || !items.isEmpty }) {
                    Text($0.label).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
        }
    }

    private var itemsSection: some View {
        Section {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack {
                        Text(item.name.isEmpty ? "Item" : item.name)
                            .font(.appCallout)
                            .lineLimit(1)
                        Spacer()
                        Text(item.price, format: .currency(code: currencyCode))
                            .font(.appMoney)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    FlowLayout(spacing: 6) {
                        ForEach(people) { person in
                            let on = assigned[person.key]?.contains(index) ?? false
                            Button {
                                toggle(person.key, item: index)
                            } label: {
                                Text(person.label)
                                    .font(.appCaption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .foregroundStyle(on ? Theme.Palette.accent : Theme.Palette.textSecondary)
                                    .background(
                                        on ? Theme.Palette.accent.opacity(0.14) : Theme.Palette.surface2,
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.borderless)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowBackground(Theme.Palette.surface)
        } header: {
            sectionHeader("Who had what")
        } footer: {
            Text("Tap who had each item. Items nobody picks are shared by everyone; tax and tip follow what each person had.")
                .font(.appCaption)
        }
    }

    private var sharesSection: some View {
        Section {
            let shares = (try? preview.get()) ?? []
            ForEach(Array(people.enumerated()), id: \.element.key) { index, person in
                HStack {
                    Text(person.label).font(.appCallout)
                    Spacer()
                    if mode == .custom {
                        TextField(
                            "0.00",
                            value: Binding(get: { amounts[person.key] }, set: { amounts[person.key] = $0 }),
                            format: .currency(code: currencyCode)
                        )
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .font(.appMoney)
                        .frame(maxWidth: 120)
                    } else if index < shares.count {
                        Text(shares[index], format: .currency(code: currencyCode))
                            .font(.appMoney)
                    }
                }
            }
            .listRowBackground(Theme.Palette.surface)
        } header: {
            sectionHeader("Shares")
        } footer: {
            if let previewProblem, !people.isEmpty {
                Text(previewProblem)
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.danger)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.appMicro)
            .tracking(1.4)
            .foregroundStyle(Theme.Palette.textTertiary)
    }

    // MARK: - Actions

    private func memberIncluded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { included?.contains(id) ?? true },
            set: { on in
                var next = included ?? Set(group?.members.map(\.id) ?? [])
                if on { next.insert(id) } else { next.remove(id) }
                included = next
            }
        )
    }

    private func toggle(_ key: String, item index: Int) {
        var set = assigned[key] ?? []
        if set.contains(index) { set.remove(index) } else { set.insert(index) }
        assigned[key] = set
    }

    private func money(_ value: Decimal) -> String {
        value.formatted(.currency(code: currencyCode))
    }

    private func loadGroups() async {
        guard fixedGroup == nil, let client = try? await Splits.client(auth) else { return }
        groups = (try? await client.groups()) ?? []
    }

    private func loadGroup() async {
        guard !groupID.isEmpty else {
            group = nil
            return
        }
        if group?.id == groupID { return }
        group = nil
        do {
            group = try await Splits.client(auth).group(id: groupID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        errorMessage = nil
        let inGroup = !groupID.isEmpty
        let participants = people.map { p in
            API.ParticipantWrite(
                isMe: p.isMe,
                memberId: p.memberID,
                name: p.memberID == nil && !p.isMe ? p.label : nil,
                isPayer: inGroup ? p.memberID == effectivePayer : p.isMe,
                itemIndexes: mode == .items ? (assigned[p.key] ?? []).sorted() : [],
                amount: mode == .custom ? (amounts[p.key] ?? 0).wireString : nil
            )
        }
        var body = API.SplitWrite(
            receiptId: receipt?.remoteID,
            groupId: inGroup ? groupID : nil,
            mode: mode,
            participants: participants
        )
        if receipt == nil {
            body.description = description.trimmingCharacters(in: .whitespaces)
            body.total = (amount ?? 0).wireString
            body.currency = currencyCode
            body.date = API.isoDayString(date)
        }

        saving = true
        defer { saving = false }
        do {
            let client = try await Splits.client(auth)
            let split: API.SplitDTO
            if let existing {
                split = try await client.updateSplit(id: existing.id, body)
            } else {
                split = try await client.createSplit(body)
            }
            onDone(split)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A typed name in a one-off split, with a stable key while names are edited.
struct NamedPerson: Identifiable, Hashable {
    static let meKey = "me"
    let id = UUID().uuidString
    var name: String
}

/// Lays children out left to right, wrapping onto new rows (person chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
