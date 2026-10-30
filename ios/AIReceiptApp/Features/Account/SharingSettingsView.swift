import SwiftUI

/// Notification emails, how people pay you back, and CSV export.
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
    @FocusState private var editingInterac: Bool

    private var interacChanged: Bool {
        interac.trimmingCharacters(in: .whitespaces) != (me?.interac ?? "")
    }

    var body: some View {
        Form {
            if let me {
                Section {
                    Toggle(
                        "Email me about shared expenses",
                        isOn: Binding(
                            get: { me.emailNotifications },
                            set: { on in Task { await save(.init(emailNotifications: on)) } }
                        )
                    )
                } header: {
                    header("Notifications")
                } footer: {
                    Text("New expenses with you, payments and reminders. Everything also shows under Activity.")
                        .font(.appCaption)
                }
                .listRowBackground(Theme.Palette.surface)

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
        guard let loaded = try? await Splits.client(auth).me() else { return }
        me = loaded
        interac = loaded.interac
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
