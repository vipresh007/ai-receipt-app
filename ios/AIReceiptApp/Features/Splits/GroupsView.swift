import SwiftUI

/// The Groups tab: people you share expenses with (a trip, housemates), each
/// with a running balance. Signed-in only — groups are shared with others.
struct GroupsView: View {
    typealias API = ReceiptExtractionAPIClient

    @Environment(AuthManager.self) private var auth

    @State private var groups: [API.GroupSummaryDTO] = []
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var creating = false
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !auth.isSignedIn {
                    signInPrompt
                } else if !loaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if groups.isEmpty {
                    ContentUnavailableView {
                        Label("No groups yet", systemImage: "person.3")
                    } description: {
                        Text("Make one for a trip, housemates, or anyone you share costs with. Tally keeps the tab.")
                    } actions: {
                        Button("New group") { creating = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.Palette.accent)
                    }
                } else {
                    List {
                        ForEach(groups) { group in
                            NavigationLink(value: group.id) {
                                GroupRow(group: group)
                            }
                        }
                        .listRowBackground(Theme.Palette.surface)
                    }
                    .ledgerBackground()
                    .refreshable { await load() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.bg.ignoresSafeArea())
            .navigationTitle("Groups")
            .navigationDestination(for: String.self) { id in
                GroupDetailView(groupID: id, onChange: { Task { await load() } })
            }
            .toolbar {
                if auth.isSignedIn {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            creating = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("New group")
                    }
                }
            }
        }
        .task(id: auth.isSignedIn) { await load() }
        .onAppear { Task { await load() } }
        .sheet(isPresented: $creating) {
            NewGroupSheet { group in
                Task {
                    await load()
                    path = [group.id]
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
            groups = try await Splits.client(auth).groups()
        } catch is CancellationError {
            return
        } catch {
            if !loaded { errorMessage = error.localizedDescription }
        }
        loaded = true
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
