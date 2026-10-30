import SwiftUI

/// Notification emails, how people pay you back, and CSV export.
struct SharingSettingsView: View {
    typealias API = ReceiptExtractionAPIClient

    @Environment(AuthManager.self) private var auth
    @State private var me: API.MeDTO?
    @State private var interac = ""
    @State private var note: String?
    @State private var saving = false
    @State private var exports: [String: URL] = [:]
    @State private var exporting: String?

    var body: some View {
        Form {
            if let me {
                LedgerSection("Notifications") {
                    Toggle(
                        "Email me about shared expenses",
                        isOn: Binding(
                            get: { me.emailNotifications },
                            set: { on in Task { await save(.init(emailNotifications: on)) } }
                        )
                    )
                    Text("New expenses with you, payments and reminders. Everything also shows under Activity.")
                        .font(.appCaption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Section {
                    TextField("Interac e-Transfer email or phone", text: $interac)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    Button(saving ? "Saving…" : "Save") {
                        Task { await save(.init(interac: interac)) }
                    }
                    .disabled(saving)
                    if let note {
                        Text(note).font(.appCaption).foregroundStyle(Theme.Palette.textSecondary)
                    }
                } header: {
                    Text("GET PAID BACK").font(.appMicro).tracking(1.4).foregroundStyle(Theme.Palette.textTertiary)
                } footer: {
                    Text("Your Interac e-Transfer email or phone, shown to people who owe you.").font(.appCaption)
                }
                .listRowBackground(Theme.Palette.surface)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }

            Section {
                exportRow("receipts", title: "Receipts")
                exportRow("shared", title: "Shared expenses")
            } header: {
                Text("EXPORT").font(.appMicro).tracking(1.4).foregroundStyle(Theme.Palette.textTertiary)
            } footer: {
                Text("CSV files that open in Numbers, Excel or Google Sheets.").font(.appCaption)
            }
            .listRowBackground(Theme.Palette.surface)
        }
        .ledgerBackground()
        .navigationTitle("Sharing & export")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func exportRow(_ name: String, title: String) -> some View {
        if let url = exports[name] {
            ShareLink(item: url) {
                Label("Share \(title.lowercased()) CSV", systemImage: "square.and.arrow.up")
            }
        } else {
            Button {
                Task { await export(name) }
            } label: {
                HStack {
                    Label(title, systemImage: "tablecells")
                    Spacer()
                    if exporting == name { ProgressView() }
                }
            }
            .disabled(exporting != nil)
        }
    }

    private func load() async {
        guard let loaded = try? await Splits.client(auth).me() else { return }
        me = loaded
        interac = loaded.interac
    }

    private func save(_ body: API.MeSettingsWrite) async {
        saving = true
        defer { saving = false }
        do {
            let next = try await Splits.client(auth).updateMe(body)
            me = next
            interac = next.interac
            note = body.interac != nil ? "Saved." : nil
        } catch {
            note = error.localizedDescription
        }
    }

    private func export(_ name: String) async {
        exporting = name
        defer { exporting = nil }
        do {
            let data = try await Splits.client(auth).exportCSV(name)
            let day = ReceiptExtractionAPIClient.isoDayString(.now)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("tally-\(name)-\(day).csv")
            try data.write(to: url, options: .atomic)
            exports[name] = url
        } catch {
            note = error.localizedDescription
        }
    }
}
