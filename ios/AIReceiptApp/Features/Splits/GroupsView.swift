import SwiftUI

/// The Shared tab: people you split with (no group needed) and groups (a
/// trip, housemates), each with a running balance. Signed-in only.
struct GroupsView: View {
    typealias API = ReceiptExtractionAPIClient

    enum Route: Hashable {
        case group(String)
        case person(String)
        case activity
    }

    @Environment(AuthManager.self) private var auth
    @Environment(ActivityBadge.self) private var badge

    @State private var groups: [API.GroupSummaryDTO] = []
    @State private var people: [API.PersonDTO] = []
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var creating = false
    @State private var addingPerson = false
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !auth.isSignedIn {
                    signInPrompt
                } else if !loaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if groups.isEmpty && people.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing shared yet", systemImage: "person.2")
                    } description: {
                        Text("Split a receipt with anyone by name, add a person here, or make a group for a trip or housemates. Tally keeps the tab.")
                    } actions: {
                        Button("Add person") { addingPerson = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.Palette.accent)
                        Button("New group") { creating = true }
                    }
                } else {
                    List {
                        Section {
                            if people.isEmpty {
                                Text("Split a receipt with someone by name and they show up here.")
                                    .font(.appCaption)
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                            ForEach(people) { person in
                                NavigationLink(value: Route.person(person.id)) {
                                    PersonRow(person: person)
                                }
                            }
                        } header: {
                            ListHeader("People")
                        }
                        .listRowBackground(Theme.Palette.surface)

                        Section {
                            if groups.isEmpty {
                                Button("New group") { creating = true }
                            }
                            ForEach(groups) { group in
                                NavigationLink(value: Route.group(group.id)) {
                                    GroupRow(group: group)
                                }
                            }
                        } header: {
                            ListHeader("Groups")
                        }
                        .listRowBackground(Theme.Palette.surface)
                    }
                    .ledgerBackground()
                    .refreshable { await load() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.bg.ignoresSafeArea())
            .navigationTitle("Shared")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .group(let id):
                    GroupDetailView(groupID: id, onChange: { Task { await load() } })
                case .person(let id):
                    PersonDetailView(personID: id, onChange: { Task { await load() } })
                case .activity:
                    ActivityView()
                }
            }
            .toolbar {
                if auth.isSignedIn {
                    ToolbarItem(placement: .navigationBarLeading) {
                        NavigationLink(value: Route.activity) {
                            Image(systemName: badge.unread > 0 ? "bell.badge" : "bell")
                                .symbolRenderingMode(.multicolor)
                        }
                        .accessibilityLabel(badge.unread > 0 ? "Activity, \(badge.unread) new" : "Activity")
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button("Add person", systemImage: "person.badge.plus") { addingPerson = true }
                            Button("New group", systemImage: "person.3") { creating = true }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add")
                    }
                }
            }
        }
        .task(id: auth.isSignedIn) { await load() }
        .onAppear {
            Task {
                await load()
                await badge.refresh(auth)
            }
        }
        .sheet(isPresented: $creating) {
            NewGroupSheet { group in
                Task {
                    await load()
                    path = [.group(group.id)]
                }
            }
        }
        .sheet(isPresented: $addingPerson) {
            NewPersonSheet { person in
                Task {
                    await load()
                    path = [.person(person.id)]
                }
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var signInPrompt: some View {
        ScrollView {
            AppCard {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    SectionLabel("Sign in to share expenses")
                    Text("Split receipts with friends and keep a running tab of who owes whom. The people you split with don't need Tally; they get a link.")
                        .font(.appCallout)
                        .foregroundStyle(Theme.Palette.text)
                    SignInButton(onSignedIn: { Task { await load() } })
                }
            }
            .padding(Theme.Space.lg)
        }
    }

    private func load() async {
        guard auth.isSignedIn else { return }
        do {
            let client = try await Splits.client(auth)
            async let loadedGroups = client.groups()
            async let loadedPeople = client.people()
            (groups, people) = try await (loadedGroups, loadedPeople)
        } catch is CancellationError {
            return
        } catch {
            if !loaded { errorMessage = error.localizedDescription }
        }
        loaded = true
    }
}

private struct ListHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.appMicro)
            .tracking(1.4)
            .foregroundStyle(Theme.Palette.textTertiary)
    }
}

private struct PersonRow: View {
    let person: ReceiptExtractionAPIClient.PersonDTO

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Text(person.name.prefix(1).uppercased())
                .font(.appCallout.weight(.semibold))
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 34, height: 34)
                .background(Theme.Palette.accent.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name)
                    .font(.appCallout.weight(.medium))
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
                Text(person.hasAccount ? "On Tally" : person.invitedAt != nil ? "Invited" : person.email ?? "Just a name")
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            PersonBalanceBadge(balance: person.balanceValue, currency: person.currency, name: person.name)
        }
        .padding(.vertical, 2)
    }
}

/// Between you and one person (positive = they owe you).
struct PersonBalanceBadge: View {
    let balance: Decimal
    let currency: String
    let name: String

    var body: some View {
        Text(Self.text(balance, currency: currency, name: name))
            .font(.appCaption.weight(.medium))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(balance == 0 ? 0.1 : 0.14), in: Capsule())
    }

    private var color: Color {
        balance > 0 ? Theme.Palette.success : balance < 0 ? Theme.Palette.danger : Theme.Palette.textTertiary
    }

    static func text(_ balance: Decimal, currency: String, name: String) -> String {
        if balance > 0 { return "Owes you \(balance.formatted(.currency(code: currency)))" }
        if balance < 0 { return "You owe \((-balance).formatted(.currency(code: currency)))" }
        return "All square"
    }
}

private struct GroupRow: View {
    let group: ReceiptExtractionAPIClient.GroupSummaryDTO

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.appHeadline)
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
                Text("^[\(group.memberCount) person](inflect: true)")
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer()
            BalanceBadge(balance: Decimal(string: group.myBalance) ?? 0, currency: group.currency)
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

/// "You're owed $45" / "You owe $12" / "Settled up".
struct BalanceBadge: View {
    let balance: Decimal
    let currency: String

    var body: some View {
        Text(Self.text(balance, currency: currency))
            .font(.appCaption.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(balance == 0 ? 0.1 : 0.14), in: Capsule())
    }

    private var color: Color {
        balance > 0 ? Theme.Palette.success : balance < 0 ? Theme.Palette.danger : Theme.Palette.textTertiary
    }

    static func text(_ balance: Decimal, currency: String) -> String {
        if balance > 0 { return "You're owed \(balance.formatted(.currency(code: currency)))" }
        if balance < 0 { return "You owe \((-balance).formatted(.currency(code: currency)))" }
        return "Settled up"
    }
}

/// Name the group and who's in it; each person can claim their name later
/// from the invite link.
private struct NewGroupSheet: View {
    let onCreated: (ReceiptExtractionAPIClient.GroupDetailDTO) -> Void

    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var members = [NamedPerson(name: "")]
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                LedgerSection("Name") {
                    TextField("Ski trip", text: $name)
                }
                Section {
                    ForEach($members) { $person in
                        TextField("Name", text: $person.name)
                            .textContentType(.name)
                    }
                    .onDelete { members.remove(atOffsets: $0) }
                    Button {
                        members.append(NamedPerson(name: ""))
                    } label: {
                        Label("Add someone", systemImage: "plus")
                    }
                } header: {
                    Text("WHO ELSE IS IN IT")
                        .font(.appMicro)
                        .tracking(1.4)
                        .foregroundStyle(Theme.Palette.textTertiary)
                } footer: {
                    Text("Just names for now. Send the invite link afterwards and each person picks theirs.")
                        .font(.appCaption)
                }
                .listRowBackground(Theme.Palette.surface)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.appCaption)
                        .foregroundStyle(Theme.Palette.danger)
                        .listRowBackground(Theme.Palette.surface)
                }
            }
            .ledgerBackground()
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Create") { Task { await create() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func create() async {
        saving = true
        defer { saving = false }
        do {
            let group = try await Splits.client(auth).createGroup(
                name: name.trimmingCharacters(in: .whitespaces),
                currency: Locale.current.currency?.identifier ?? "USD",
                members: members.map { $0.name.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            )
            onCreated(group)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Add someone to split with: a name now, an email whenever.
private struct NewPersonSheet: View {
    let onCreated: (ReceiptExtractionAPIClient.PersonDetailDTO) -> Void

    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var invite = true
    @State private var saving = false
    @State private var errorMessage: String?

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                LedgerSection("Name") {
                    TextField("Sam", text: $name)
                        .textContentType(.name)
                }
                Section {
                    TextField("Optional, add it later", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !trimmedEmail.isEmpty {
                        Toggle("Email them an invite", isOn: $invite)
                    }
                } header: {
                    Text("EMAIL")
                        .font(.appMicro)
                        .tracking(1.4)
                        .foregroundStyle(Theme.Palette.textTertiary)
                } footer: {
                    Text("Once they accept an invite, they see what you share from their side. You can also send them the invite link yourself.")
                        .font(.appCaption)
                }
                .listRowBackground(Theme.Palette.surface)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.appCaption)
                        .foregroundStyle(Theme.Palette.danger)
                        .listRowBackground(Theme.Palette.surface)
                }
            }
            .ledgerBackground()
            .navigationTitle("Add person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Add") { Task { await create() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func create() async {
        saving = true
        defer { saving = false }
        do {
            let client = try await Splits.client(auth)
            var person = try await client.createPerson(
                name: name.trimmingCharacters(in: .whitespaces),
                email: trimmedEmail.isEmpty ? nil : trimmedEmail
            )
            if invite, person.canEmail, let sent = try? await client.invitePerson(id: person.id) {
                person = sent  // best effort: their screen has the link either way
            }
            onCreated(person)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
