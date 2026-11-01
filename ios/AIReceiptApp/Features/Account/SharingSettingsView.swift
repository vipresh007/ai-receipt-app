import SwiftUI

/// How people pay you back, emailing receipts in, and CSV export.
struct SharingSettingsView: View {
    typealias API = ReceiptExtractionAPIClient

    enum ExportRange: String, CaseIterable, Identifiable {
        case thisMonth = "This month", lastMonth = "Last month", thisYear = "This year"
        case lastYear = "Last year", all = "All time", custom = "Custom dates"
        var id: String { rawValue }
    }

    @Environment(AuthManager.self) private var auth
    @State private var me: API.MeDTO?
    @State private var interac = ""
    @State private var note: String?
    @State private var saving = false
    @State private var range: ExportRange = .thisYear
    @State private var customFrom = Calendar.current.date(from: Calendar.current.dateComponents([.year], from: .now)) ?? .now
    @State private var customTo = Date.now
    @State private var exports: [String: URL] = [:]
    @State private var exporting: String?
    @State private var blocked: [API.BlockedDTO] = []
    @FocusState private var editingInterac: Bool

    private var interacChanged: Bool {
        interac.trimmingCharacters(in: .whitespaces) != (me?.interac ?? "")
    }

    var body: some View {
        Form {
            if let me {
                Section {
                    LabeledContent("Interac") {
                        HStack(spacing: Theme.Space.sm) {
                            TextField("email or phone", text: $interac)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                                .submitLabel(.done)
                                .focused($editingInterac)
                                .onSubmit { Task { await saveInterac() } }
                            // Only when there's something to save.
                            if interacChanged {
                                Button("Save") { Task { await saveInterac() } }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .tint(Theme.Palette.accent)
                                    .disabled(saving)
                            }
                        }
                    }
                } header: {
                    header("Get paid back")
                } footer: {
                    Text(note ?? "Your Interac e-Transfer email or phone, shown to people who owe you.")
                        .font(.appCaption)
                }
                .listRowBackground(Theme.Palette.surface)
                if let address = me.receiptsEmail {
                    Section {
                        ForwardRow(title: "Forward to", address: address)
                        if let personal = me.receiptsPersonalEmail {
                            ForwardRow(title: "From any other inbox", address: personal)
                        }
                    } header: {
                        header("Email receipts in")
                    } footer: {
                        Text("Forward an e-receipt from \(me.email) to \(address) and it's read and added for you, attachments (PDF or photo) or not. From another email address, use your personal one.")
                            .font(.appCaption)
                    }
                    .listRowBackground(Theme.Palette.surface)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }

            Section {
                Picker("Dates", selection: $range) {
                    ForEach(ExportRange.allCases) { Text($0.rawValue).tag($0) }
                }
                if range == .custom {
                    DatePicker("From", selection: $customFrom, in: ...customTo, displayedComponents: .date)
                    DatePicker("To", selection: $customTo, in: customFrom..., displayedComponents: .date)
                }
                exportRow("receipts", title: "Receipts")
                exportRow("shared", title: "Shared expenses")
            } header: {
                header("Export")
            } footer: {
                Text("CSV files that open in Numbers, Excel or Google Sheets.").font(.appCaption)
            }
            .listRowBackground(Theme.Palette.surface)
            .onChange(of: range) { _, _ in exports = [:] }
            .onChange(of: customFrom) { _, _ in exports = [:] }
            .onChange(of: customTo) { _, _ in exports = [:] }

            if !blocked.isEmpty {
                Section {
                    ForEach(blocked) { person in
                        HStack {
                            Text(person.name)
                            Spacer()
                            Button("Unblock") { Task { await unblock(person) } }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                } header: {
                    header("Blocked")
                } footer: {
                    Text("You don't see their comments or get their activity. Shared expenses stay as they are.")
                        .font(.appCaption)
                }
                .listRowBackground(Theme.Palette.surface)
            }
        }
        .ledgerBackground()
        .navigationTitle("Sharing & export")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear {
            if interacChanged { Task { await saveInterac() } }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased()).font(.appMicro).tracking(1.4).foregroundStyle(Theme.Palette.textTertiary)
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

    /// (from, to) as YYYY-MM-DD, or nil for all time.
    private var dates: (String, String)? {
        let calendar = Calendar.current
        let day = API.isoDayString
        func month(_ offset: Int) -> (String, String)? {
            guard let start = calendar.date(byAdding: .month, value: offset, to: calendar.dateInterval(of: .month, for: .now)!.start),
                  let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)
            else { return nil }
            return (day(start), day(end))
        }
        let year = calendar.component(.year, from: .now)
        switch range {
        case .thisMonth: return month(0)
        case .lastMonth: return month(-1)
        case .thisYear: return ("\(year)-01-01", "\(year)-12-31")
        case .lastYear: return ("\(year - 1)-01-01", "\(year - 1)-12-31")
        case .all: return nil
        case .custom: return (day(customFrom), day(customTo))
        }
    }

    private func load() async {
        guard let client = try? await Splits.client(auth), let loaded = try? await client.me() else { return }
        me = loaded
        interac = loaded.interac
        blocked = (try? await client.blocked()) ?? []
    }

    private func unblock(_ person: API.BlockedDTO) async {
        guard (try? await Splits.client(auth).unblock(userID: person.userId)) != nil else { return }
        blocked.removeAll { $0.id == person.id }
    }

    private func saveInterac() async {
        await save(.init(interac: interac.trimmingCharacters(in: .whitespaces)))
        if note == nil { note = "Saved." }
        editingInterac = false
    }

    private func save(_ body: API.MeSettingsWrite) async {
        saving = true
        defer { saving = false }
        note = nil
        do {
            let next = try await Splits.client(auth).updateMe(body)
            me = next
            interac = next.interac
        } catch {
            note = error.localizedDescription
        }
    }

    private func export(_ name: String) async {
        exporting = name
        defer { exporting = nil }
        do {
            let range = dates
            let data = try await Splits.client(auth).exportCSV(name, from: range?.0, to: range?.1)
            let label = range.map { "\($0.0)-to-\($0.1)" } ?? "all"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("tally-\(name)-\(label).csv")
            try data.write(to: url, options: .atomic)
            exports[name] = url
        } catch {
            note = error.localizedDescription
        }
    }
}


private struct ForwardRow: View {
    let title: String
    let address: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = address
            copied = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.appCaption).foregroundStyle(Theme.Palette.textTertiary)
                HStack {
                    Text(address).font(.appCallout).foregroundStyle(Theme.Palette.text).textSelection(.enabled)
                    Spacer()
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(Theme.Palette.accent)
                }
            }
        }
        .accessibilityLabel("Copy \(address)")
    }
}
