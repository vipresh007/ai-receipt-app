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

    // One-off: you, saved people picked, and new names (saved as people).
    @State private var includeMe: Bool
    @State private var savedPeople: [API.PersonDTO] = []
    @State private var picked: [PickedPerson]
    @State private var names: [NamedPerson]
    @State private var oneOffPayer: String
    // Group: who's in (nil = everyone), and who paid.
    @State private var included: Set<String>?
    @State private var payerID: String

    @State private var mode: SplitMath.Mode
    @State private var assigned: [String: Set<Int>]
    @State private var amounts: [String: Decimal]
    @State private var weights: [String: Decimal]
    // Who paid: one person (the pickers above), or several with amounts.
    @State private var severalPayers: Bool
    @State private var paidAmounts: [String: Decimal]
    /// Someone else's expense: the payer among its existing participants.
    @State private var adjustPayer: String
    @State private var repeatEvery: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(
        receipt: Receipt? = nil,
        group: API.GroupDetailDTO? = nil,
        existing: API.SplitDTO? = nil,
        withPeople: [PickedPerson] = [],
        onDone: @escaping (API.SplitDTO) -> Void
    ) {
        self.receipt = receipt
        self.fixedGroup = group
        self.existing = existing
        self.onDone = onDone

        let oneOff = existing?.groupId == nil ? existing?.participants ?? [] : []
        let others: [NamedPerson] = oneOff.filter { !$0.isMe && $0.personId == nil }
            .map { NamedPerson(name: $0.displayName) }
        let pickedAtStart: [PickedPerson] =
            existing == nil
            ? withPeople
            : oneOff.compactMap { p in p.personId.map { PickedPerson(id: $0, name: p.displayName) } }
        var assigned: [String: Set<Int>] = [:]
        var amounts: [String: Decimal] = [:]
        var weights: [String: Decimal] = [:]
        var paidAmounts: [String: Decimal] = [:]
        let adjust = existing.map { !$0.isOwner } ?? false
        var payer = ""
        var oneOffPayer = NamedPerson.meKey
        var nextOther = 0
        for p in existing?.participants ?? [] {
            let key: String
            if adjust {
                key = "part:\(p.id)"
            } else if let member = p.memberId {
                key = member
            } else if p.isMe {
                key = NamedPerson.meKey
            } else if let person = p.personId {
                key = PickedPerson.key(person)
            } else {
                guard nextOther < others.count else { continue }
                key = others[nextOther].id
                nextOther += 1
            }
            assigned[key] = Set(p.itemIndexes)
            if let amount = p.amount.flatMap({ Decimal(string: $0) }) { amounts[key] = amount }
            if let weight = p.weight.flatMap({ Decimal(string: $0) }) { weights[key] = weight }
            if let paid = p.paid.flatMap({ Decimal(string: $0) }) { paidAmounts[key] = paid }
            if p.isPayer, let member = p.memberId { payer = member }
            if p.isPayer, p.memberId == nil { oneOffPayer = key }
        }

        _groupID = State(initialValue: group?.id ?? existing?.groupId ?? "")
        _group = State(initialValue: group)
        _description = State(initialValue: existing?.description ?? "")
        _amount = State(initialValue: receipt == nil ? existing?.totalValue : nil)
        _date = State(initialValue: existing?.day ?? .now)
        _includeMe = State(initialValue: existing.map { $0.participants.contains(where: \.isMe) } ?? true)
        _picked = State(initialValue: pickedAtStart)
        _names = State(
            initialValue: others
        )
        _oneOffPayer = State(initialValue: oneOffPayer)
        _included = State(
            initialValue: existing?.groupId != nil ? Set(existing!.participants.compactMap(\.memberId)) : nil
        )
        _payerID = State(initialValue: payer)
        _mode = State(initialValue: existing?.mode ?? .even)
        _assigned = State(initialValue: assigned)
        _amounts = State(initialValue: amounts)
        _weights = State(initialValue: weights)
        _paidAmounts = State(initialValue: paidAmounts)
        _severalPayers = State(initialValue: (existing?.payers.count ?? 0) > 1)
        _adjustPayer = State(initialValue: existing?.payer?.id ?? "")
        _repeatEvery = State(initialValue: existing?.repeat ?? "")
    }

    /// Someone else's expense: change the amounts, not who's on it.
    private var adjustOnly: Bool { existing.map { !$0.isOwner } ?? false }

    // MARK: - Derived

    private struct Person: Identifiable {
        let key: String
        let label: String
        let isMe: Bool
        let memberID: String?
        var personID: String? = nil
        var participantID: String? = nil
        var id: String { key }
    }

    private var people: [Person] {
        if adjustOnly, let existing {
            return existing.participants.map {
                Person(
                    key: "part:\($0.id)", label: $0.isMe ? "You" : $0.displayName, isMe: $0.isMe,
                    memberID: nil, participantID: $0.id
                )
            }
        }
        if !groupID.isEmpty {
            guard let group else { return [] }
            return group.members
                .filter { included?.contains($0.id) ?? true }
                .map { Person(key: $0.id, label: $0.isMe ? "You" : $0.displayName, isMe: $0.isMe, memberID: $0.id) }
        }
        var list = includeMe ? [Person(key: NamedPerson.meKey, label: "You", isMe: true, memberID: nil)] : []
        for person in picked {
            list.append(Person(key: person.key, label: person.name, isMe: false, memberID: nil, personID: person.id))
        }
        for person in names {
            let name = person.name.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { list.append(Person(key: person.id, label: name, isMe: false, memberID: nil)) }
        }
        return list
    }

    /// Who paid a one-off split: you by default, else the first person.
    private var oneOffPayerKey: String {
        people.contains(where: { $0.key == oneOffPayer }) ? oneOffPayer : (people.first?.key ?? "")
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
            inputs: people.map {
                .init(itemIndexes: assigned[$0.key] ?? [], amount: amounts[$0.key], weight: weights[$0.key])
            },
            itemPrices: items.map(\.price)
        )
    }

    private var previewProblem: String? {
        switch preview {
        case .success: nil
        case .failure(.noPeople): "Add at least one person."
        case .failure(.missingAmount): "Enter an amount for everyone."
        case .failure(.noShares): "Give at least one person a share."
        case .failure(.percentNot100(let sum)): "The percentages add up to \(sum)%, not 100%."
        case .failure(.amountsDontAddUp(let total, let entered)):
            "Amounts add up to \(money(entered)), not \(money(total))."
        }
    }

    /// The single payer's key across the three ways of picking one.
    private var payerKey: String {
        if adjustOnly { return "part:\(adjustPayer)" }
        if !groupID.isEmpty { return people.first(where: { $0.memberID == effectivePayer })?.key ?? "" }
        return oneOffPayerKey
    }

    private var paidSum: Decimal { people.reduce(0) { $0 + (paidAmounts[$1.key] ?? 0) } }

    private var canSave: Bool {
        guard !saving, case .success = preview, people.count > 1 || !groupID.isEmpty || adjustOnly else {
            return false
        }
        if severalPayers, paidSum != total { return false }
        if adjustOnly, existing?.receiptId != nil { return true }
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
                if adjustOnly {
                    Section {
                        Text("You can change the amounts, who paid and how it's divided. Who's on it is up to whoever added it. Everyone on it sees what you changed.")
                            .font(.appCaption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    .listRowBackground(Theme.Palette.surface)
                } else {
                    withSection
                }
                if people.count > 1 { paidBySection }
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
        if adjustOnly, let existing, existing.receiptId != nil {
            LedgerSection("Receipt") {
                LabeledContent(existing.description.isEmpty ? "Receipt" : existing.description) {
                    Text(existing.totalValue, format: .currency(code: currencyCode)).font(.appMoney)
                }
            }
        } else if let receipt {
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
                if !adjustOnly {
                    Picker("Repeats", selection: $repeatEvery) {
                        Text("Never").tag("")
                        Text("Every week").tag("weekly")
                        Text("Every month").tag("monthly")
                    }
                }
            }
        }
    }

    private var paidBySection: some View {
        LedgerSection("Paid by") {
            Picker(
                "Paid by",
                selection: Binding(
                    get: { severalPayers ? Self.several : payerKey },
                    set: { choosePayer($0) }
                )
            ) {
                ForEach(people) { Text($0.label).tag($0.key) }
                Text("Several people…").tag(Self.several)
            }
            if severalPayers {
                ForEach(people) { person in
                    LabeledContent("\(person.label) paid") {
                        TextField(
                            "0.00",
                            value: Binding(get: { paidAmounts[person.key] }, set: { paidAmounts[person.key] = $0 }),
                            format: .currency(code: currencyCode)
                        )
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .font(.appMoney)
                    }
                }
                Text("Paid \(money(paidSum)) of \(money(total))")
                    .font(.appCaption)
                    .foregroundStyle(paidSum == total ? Theme.Palette.textTertiary : Theme.Palette.warning)
            }
        }
    }

    private static let several = "__several"

    private func choosePayer(_ key: String) {
        if key == Self.several {
            severalPayers = true
            return
        }
        severalPayers = false
        let person = people.first(where: { $0.key == key })
        if adjustOnly {
            adjustPayer = person?.participantID ?? ""
        } else if !groupID.isEmpty {
            payerID = person?.memberID ?? ""
        } else {
            oneOffPayer = key
        }
    }

    @ViewBuilder
    private var withSection: some View {
        LedgerSection("Split with") {
            // Only a choice once there's a group to choose (or this split is in one).
            if fixedGroup == nil, !groups.isEmpty || !groupID.isEmpty {
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
                // Who's on it: picked people and new names, with a search
                // screen to add more (any number of people).
                ForEach(picked, id: \.id) { person in
                    Text(person.name)
                }
                .onDelete { picked.remove(atOffsets: $0) }
                ForEach(names.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }) { person in
                    HStack {
                        Text(person.name)
                        Text("new").font(.appCaption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                .onDelete { offsets in
                    let shown = names.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                    let gone = Set(offsets.map { shown[$0].id })
                    names.removeAll { gone.contains($0.id) }
                }
                NavigationLink {
                    PeoplePickerView(saved: savedPeople, picked: $picked, names: $names)
                } label: {
                    Label(picked.isEmpty && names.isEmpty ? "Add people" : "Add or remove people", systemImage: "person.badge.plus")
                }
            } else if let group {
                ForEach(group.members) { member in
                    Toggle(member.isMe ? "\(member.displayName) (you)" : member.displayName, isOn: memberIncluded(member.id))
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
                    if people.count > 6 {
                        NavigationLink {
                            WhoHadItView(
                                item: item.name.isEmpty ? "Item" : item.name,
                                people: people.map { (key: $0.key, label: $0.label) },
                                chosen: whoHad(index)
                            )
                        } label: {
                            Text(whoHadSummary(index))
                                .font(.appCaption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    } else {
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
                    if mode == .shares || mode == .percent {
                        TextField(
                            mode == .shares ? "1" : "0",
                            value: Binding(get: { weights[person.key] }, set: { weights[person.key] = $0 }),
                            format: .number
                        )
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .font(.appMoney)
                        .frame(width: 56)
                        .accessibilityLabel("\(person.label) \(mode == .shares ? "shares" : "percent")")
                        Text(index < shares.count ? "= \(shares[index].formatted(.currency(code: currencyCode)))" : "=")
                            .font(.appCaption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(minWidth: 84, alignment: .trailing)
                    } else if mode == .custom {
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
            sectionHeader(
                mode == .shares ? "Shares (parts each)" : mode == .percent ? "Percent each (to 100)"
                    : mode == .custom ? "Amounts" : "Each pays"
            )
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

    /// Who had item `index`, as a set of people keys (for the checklist).
    private func whoHad(_ index: Int) -> Binding<Set<String>> {
        Binding(
            get: { Set(people.filter { assigned[$0.key]?.contains(index) ?? false }.map(\.key)) },
            set: { chosen in
                for person in people {
                    var set = assigned[person.key] ?? []
                    if chosen.contains(person.key) { set.insert(index) } else { set.remove(index) }
                    assigned[person.key] = set
                }
            }
        )
    }

    private func whoHadSummary(_ index: Int) -> String {
        let names = people.filter { assigned[$0.key]?.contains(index) ?? false }.map(\.label)
        if names.isEmpty { return "Who had it: everyone" }
        let shown = names.prefix(2).joined(separator: ", ")
        return "Who had it: " + (names.count > 2 ? "\(shown) +\(names.count - 2)" : shown)
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
        guard let client = try? await Splits.client(auth) else { return }
        if fixedGroup == nil { groups = (try? await client.groups()) ?? [] }
        savedPeople = (try? await client.people()) ?? []
    }

    private func togglePicked(_ person: API.PersonDTO) {
        if let index = picked.firstIndex(where: { $0.id == person.id }) {
            picked.remove(at: index)
        } else {
            picked.append(PickedPerson(id: person.id, name: person.name))
        }
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
        let weighted = mode == .shares || mode == .percent
        let paid: (Person) -> String? = { severalPayers ? (paidAmounts[$0.key] ?? 0).wireString : nil }

        saving = true
        defer { saving = false }
        do {
            let client = try await Splits.client(auth)
            let split: API.SplitDTO
            if adjustOnly, let existing {
                let manual = existing.receiptId == nil
                split = try await client.adjustSplit(
                    id: existing.id,
                    API.SplitAdjustWrite(
                        description: manual ? description.trimmingCharacters(in: .whitespaces) : nil,
                        total: manual ? (amount ?? 0).wireString : nil,
                        date: manual ? API.isoDayString(date) : nil,
                        mode: mode,
                        participants: people.map { p in
                            API.ParticipantAdjustWrite(
                                id: p.participantID ?? "",
                                isPayer: !severalPayers && p.participantID == adjustPayer,
                                paid: paid(p),
                                itemIndexes: mode == .items ? (assigned[p.key] ?? []).sorted() : [],
                                amount: mode == .custom ? (amounts[p.key] ?? 0).wireString : nil,
                                weight: weighted ? weights[p.key]?.wireString : nil
                            )
                        }
                    )
                )
            } else {
                let participants = people.map { p in
                    API.ParticipantWrite(
                        isMe: p.isMe,
                        memberId: p.memberID,
                        personId: p.personID,
                        name: p.memberID == nil && p.personID == nil && !p.isMe ? p.label : nil,
                        isPayer: !severalPayers && p.key == payerKey,
                        itemIndexes: mode == .items ? (assigned[p.key] ?? []).sorted() : [],
                        amount: mode == .custom ? (amounts[p.key] ?? 0).wireString : nil,
                        weight: weighted ? weights[p.key]?.wireString : nil,
                        paid: paid(p)
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
                    body.repeat = repeatEvery
                }
                if let existing {
                    split = try await client.updateSplit(id: existing.id, body)
                } else {
                    split = try await client.createSplit(body)
                }
            }
            onDone(split)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A saved person on a one-off split.
struct PickedPerson: Hashable {
    let id: String
    let name: String

    static func key(_ id: String) -> String { "person:\(id)" }
    var key: String { Self.key(id) }
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
