import SwiftUI

/// Everything you can do about one person in a group: settle up, remind,
/// pay them back, invite them by email, or take them off the group.
struct MemberSheet: View {
    typealias API = ReceiptExtractionAPIClient

    let group: API.GroupDetailDTO
    let member: API.GroupMemberDTO
    /// Between you and them: positive = they owe you.
    let owed: Decimal
    let onChange: (API.GroupDetailDTO) -> Void

    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var busy = false
    @State private var note: String?
    @State private var confirmingRemove = false
    // Recording a payment, right here (no second screen).
    @State private var recording = false
    @State private var theyPaid = true
    @State private var amount: Decimal?

    private var me: API.GroupMemberDTO? { group.members.first(where: \.isMe) }

    private func money(_ value: Decimal) -> String { value.formatted(.currency(code: group.currency)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(member.hasAccount ? "On Tally" : member.invitedAt != nil ? "Invited" : "Hasn't joined yet")
                            .font(.appMicro)
                            .tracking(1.2)
                            .foregroundStyle(Theme.Palette.textTertiary)
                        Text(owed > 0 ? "Owes you \(money(owed))" : owed < 0 ? "You owe \(money(-owed))" : "Settled up with you")
                            .font(.display(26, relativeTo: .title2))
                            .foregroundStyle(owed > 0 ? Theme.Palette.success : owed < 0 ? Theme.Palette.danger : Theme.Palette.text)
                    }
                    .padding(.vertical, Theme.Space.xs)
                    if let note, !note.isEmpty, !recording {
                        Text(note).font(.appCaption).foregroundStyle(Theme.Palette.success)
                    }
                }
                .listRowBackground(Color.clear)

                if let me {
                    Section {
                        Button {
                            withAnimation(Theme.Motion.base) { recording.toggle() }
                        } label: {
                            HStack {
                                Label("Record a payment", systemImage: "checkmark.circle")
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.appCaption.weight(.semibold))
                                    .rotationEffect(.degrees(recording ? 180 : 0))
                                    .foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                        if recording {
                            Picker("Who paid", selection: $theyPaid) {
                                Text("\(member.displayName) paid you").tag(true)
                                Text("You paid \(member.displayName)").tag(false)
                            }
                            .pickerStyle(.segmented)
                            LabeledContent("Amount") {
                                TextField("0.00", value: $amount, format: .currency(code: group.currency))
                                    .multilineTextAlignment(.trailing)
                                    .keyboardType(.decimalPad)
                                    .font(.appMoney)
                            }
                            Button {
                                Task { await record(me) }
                            } label: {
                                Text("Record \(money(amount ?? 0))")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.Palette.accent)
                            .disabled(busy || (amount ?? 0) <= 0)
                            Text("Tally only keeps track. Send the money however you normally do.")
                                .font(.appCaption)
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                        if owed > 0, member.hasAccount {
                            Button {
                                Task { await remind() }
                            } label: {
                                Label("Remind \(member.displayName)", systemImage: "bell")
                            }
                            .disabled(busy)
                        }
                        if owed < 0, let payTo = member.payTo {
                            PayToView(payTo: payTo, amount: -owed, currency: group.currency, name: member.displayName)
                        }
                    }
                    .listRowBackground(Theme.Palette.surface)
                }

                if !member.hasAccount {
                    Section {
                        TextField("Their email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.send)
                            .onSubmit { Task { await invite() } }
                        Button {
                            Task { await invite() }
                        } label: {
                            Label(member.invitedAt != nil ? "Send the invite again" : "Email the invite", systemImage: "envelope")
                        }
                        .disabled(busy || email.trimmingCharacters(in: .whitespaces).isEmpty)
                    } header: {
                        Text("INVITE").font(.appMicro).tracking(1.4).foregroundStyle(Theme.Palette.textTertiary)
                    } footer: {
                        Text(
                            note
                                ?? (member.invitedAt.flatMap { API.isoDay(String($0.prefix(10))) }.map {
                                    "Last emailed \($0.formatted(.dateTime.month().day())). Their name is already picked when they open it."
                                } ?? "Tally emails them the group's invite with their name already picked.")
                        )
                        .font(.appCaption)
                    }
                    .listRowBackground(Theme.Palette.surface)
                }

                if !member.hasAccount, owed == 0, abs(member.balanceValue) < 0.005 {
                    Section {
                        Button("Remove from \(group.name)", role: .destructive) { confirmingRemove = true }
                    }
                    .listRowBackground(Theme.Palette.surface)
                }
            }
            .ledgerBackground()
            .navigationTitle(member.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Remove \(member.displayName)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { Task { await remove() } }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            email = member.email ?? ""
            // Preset to the payment that would settle up.
            theyPaid = owed >= 0
            amount = owed == 0 ? nil : abs(owed)
        }
    }

    private func run(_ action: (API) async throws -> API.GroupDetailDTO, done: String) async {
        busy = true
        defer { busy = false }
        do {
            onChange(try await action(try await Splits.client(auth)))
            note = done
        } catch {
            note = error.localizedDescription
        }
    }

    private func record(_ me: API.GroupMemberDTO) async {
        let value = amount ?? 0
        guard value > 0 else { return }
        let (from, to) = theyPaid ? (member.id, me.id) : (me.id, member.id)
        await run(
            { try await $0.addSettlement(groupID: group.id, from: from, to: to, amount: value) },
            done: theyPaid ? "Recorded: \(member.displayName) paid you \(money(value))." : "Recorded: you paid \(member.displayName) \(money(value))."
        )
        withAnimation(Theme.Motion.base) { recording = false }
    }

    private func invite() async {
        let address = email.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return }
        await run({ try await $0.inviteMember(groupID: group.id, memberID: member.id, email: address) },
                  done: "Invite emailed to \(address).")
    }

    private func remind() async {
        await run({ try await $0.remindMember(groupID: group.id, memberID: member.id) },
                  done: "Reminder sent.")
    }

    private func remove() async {
        await run({ try await $0.removeMember(groupID: group.id, memberID: member.id) }, done: "")
        dismiss()
    }
}
