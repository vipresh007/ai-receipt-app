import SwiftUI

/// An expense's history (added, every change and who made it) and comments.
/// Everyone who can see the expense sees all of it.
struct SplitTimelineView: View {
    typealias API = ReceiptExtractionAPIClient

    let split: API.SplitDTO

    @Environment(AuthManager.self) private var auth
    @State private var entries: [API.TimelineEntryDTO] = []
    @State private var loaded = false
    @State private var draft = ""
    @State private var sending = false
    @State private var errorMessage: String?
    @State private var note: String?
    // Reporting: pick a reason, then whether to block them too.
    @State private var reporting: API.TimelineEntryDTO?
    @State private var reason: String?

    var body: some View {
        List {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity)
            }
            ForEach(entries) { entry in
                if entry.isComment {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(entry.authorName).font(.appCaption.weight(.semibold))
                            Spacer()
                            Text(entry.date, format: .relative(presentation: .named))
                                .font(.appCaption)
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                        Text(entry.text).font(.appCallout)
                    }
                    .padding(.vertical, 2)
                    .swipeActions {
                        if entry.canDelete {
                            Button("Delete", role: .destructive) { Task { await delete(entry) } }
                        }
                        if entry.canReport == true {
                            Button("Report") { reporting = entry }
                                .tint(Theme.Palette.danger)
                        }
                    }
                    .contextMenu {
                        if entry.canReport == true {
                            Button("Report \(entry.authorName)'s comment…", systemImage: "flag") { reporting = entry }
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: Theme.Space.sm) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.appCaption)
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            (Text(entry.authorName).fontWeight(.semibold) + Text(" \(entry.text)"))
                                .font(.appCaption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                            Text(entry.date, format: .relative(presentation: .named))
                                .font(.appCaption)
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                }
            }
            .listRowBackground(Theme.Palette.surface)
            if let note {
                Text(note)
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .listRowBackground(Theme.Palette.surface)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.danger)
                    .listRowBackground(Theme.Palette.surface)
            }
        }
        .ledgerBackground()
        .navigationTitle(split.description.isEmpty ? "History" : split.description)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: Theme.Space.sm) {
                TextField("Add a comment", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, 10)
                    .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.Palette.border))
                Button {
                    Task { await post() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                .accessibilityLabel("Post comment")
            }
            .padding(Theme.Space.md)
            .background(Theme.Palette.bg)
        }
        .confirmationDialog(
            "What's wrong with this comment?",
            isPresented: Binding(get: { reporting != nil && reason == nil }, set: { if !$0, reason == nil { reporting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Spam") { reason = "spam" }
            Button("Harassment or hate") { reason = "abuse" }
            Button("Inappropriate") { reason = "inappropriate" }
            Button("Something else") { reason = "other" }
            Button("Cancel", role: .cancel) { reporting = nil }
        }
        .alert(
            "Block \(reporting?.authorName ?? "them") too?",
            isPresented: Binding(get: { reporting != nil && reason != nil }, set: { if !$0 { reporting = nil; reason = nil } })
        ) {
            Button("Report and block", role: .destructive) { Task { await report(block: true) } }
            Button("Just report") { Task { await report(block: false) } }
            Button("Cancel", role: .cancel) { reporting = nil; reason = nil }
        } message: {
            Text("You won't see their comments or hear from them. Shared expenses stay as they are.")
        }
        .task { await load() }
        .liveRefresh { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            entries = try await Splits.client(auth).timeline(splitID: split.id)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        loaded = true
    }

    private func post() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            entries = try await Splits.client(auth).addComment(splitID: split.id, body: body)
            draft = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func report(block: Bool) async {
        guard let entry = reporting, let reason else { return }
        reporting = nil
        self.reason = nil
        do {
            entries = try await Splits.client(auth).reportComment(splitID: split.id, id: entry.id, reason: reason, block: block)
            note = block ? "Reported, and \(entry.authorName) is blocked." : "Reported. Thanks for telling us."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ entry: API.TimelineEntryDTO) async {
        if let next = try? await Splits.client(auth).deleteComment(splitID: split.id, id: entry.id) {
            entries = next
        }
    }
}
