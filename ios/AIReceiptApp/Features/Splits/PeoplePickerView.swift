import SwiftUI

/// Pick who's on a split from your saved people by searching, or add
/// someone new. Recent people first; scales to any number of people.
struct PeoplePickerView: View {
    typealias API = ReceiptExtractionAPIClient

    let saved: [API.PersonDTO]
    @Binding var picked: [PickedPerson]
    @Binding var names: [NamedPerson]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var matches: [API.PersonDTO] {
        guard !trimmed.isEmpty else { return saved.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
        return saved
            .filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            .sorted { a, b in
                let aStarts = a.name.lowercased().hasPrefix(trimmed.lowercased())
                let bStarts = b.name.lowercased().hasPrefix(trimmed.lowercased())
                return aStarts != bStarts ? aStarts : a.name < b.name
            }
    }

    private var recent: [API.PersonDTO] {
        Array(saved.filter { $0.lastShared != nil }.sorted { ($0.lastShared ?? "") > ($1.lastShared ?? "") }.prefix(5))
    }

    private var canAddNew: Bool {
        !trimmed.isEmpty
            && !saved.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
            && !names.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        List {
            if canAddNew {
                Section {
                    Button {
                        names.append(NamedPerson(name: trimmed))
                        query = ""
                    } label: {
                        Label("Add \u{201C}\(trimmed)\u{201D} as someone new", systemImage: "plus.circle.fill")
                    }
                }
                .listRowBackground(Theme.Palette.surface)
            }
            if trimmed.isEmpty, !recent.isEmpty {
                Section("Recent") { ForEach(recent) { row($0) } }
                    .listRowBackground(Theme.Palette.surface)
            }
            if !matches.isEmpty {
                Section(trimmed.isEmpty ? "Everyone" : "Matches") { ForEach(matches) { row($0) } }
                    .listRowBackground(Theme.Palette.surface)
            }
        }
        .ledgerBackground()
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name")
        .navigationTitle("Who's on it")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    private func row(_ person: API.PersonDTO) -> some View {
        let on = picked.contains { $0.id == person.id }
        return Button {
            if on {
                picked.removeAll { $0.id == person.id }
            } else {
                picked.append(PickedPerson(id: person.id, name: person.name))
            }
        } label: {
            HStack {
                Text(person.name).foregroundStyle(Theme.Palette.text)
                Spacer()
                if on { Image(systemName: "checkmark").foregroundStyle(Theme.Palette.accent) }
            }
        }
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// "Who had it" for one item in a big split: a checklist instead of a chip
/// per person.
struct WhoHadItView: View {
    let item: String
    let people: [(key: String, label: String)]
    @Binding var chosen: Set<String>

    var body: some View {
        List {
            Section {
                ForEach(people, id: \.key) { person in
                    Button {
                        if chosen.contains(person.key) { chosen.remove(person.key) } else { chosen.insert(person.key) }
                    } label: {
                        HStack {
                            Text(person.label).foregroundStyle(Theme.Palette.text)
                            Spacer()
                            if chosen.contains(person.key) {
                                Image(systemName: "checkmark").foregroundStyle(Theme.Palette.accent)
                            }
                        }
                    }
                }
            } footer: {
                Text("Nobody picked means everyone shares it.").font(.appCaption)
            }
            .listRowBackground(Theme.Palette.surface)
        }
        .ledgerBackground()
        .navigationTitle(item)
        .navigationBarTitleDisplayMode(.inline)
    }
}
