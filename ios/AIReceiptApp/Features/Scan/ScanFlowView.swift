import SwiftUI
import PhotosUI

/// Capture flow: pick an image (camera or library) → run the extractor →
/// confirm and save.
struct ScanFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var auth

    @State private var pickedItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var stage: Stage = .idle
    @State private var draft = ReceiptDraft()
    @State private var previewImage: UIImage?
    @State private var errorMessage: String?
    @State private var savedTick = 0
    @State private var showQuotaWall = false
    /// Server receipt id when signed in — `/v1/extract` already persisted it, so
    /// "Save" only needs to push edits and "Discard" needs to delete it.
    @State private var pendingServerID: String?

    private enum Stage: Equatable {
        case idle, working, confirming
    }

    /// Anonymous + backend-configured + the device has spent its free scans.
    private var quotaSpent: Bool {
        !auth.isSignedIn && AppConfig.extractionAPIBaseURL != nil && (auth.scansRemaining ?? 1) <= 0
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Palette.bg.ignoresSafeArea())
                .navigationTitle("Scan")
                .safeAreaInset(edge: .top) { scanAllowance }
                .alert("Couldn't scan receipt", isPresented: errorBinding) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage ?? "")
                }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(onImage: handle)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showQuotaWall) {
            QuotaWallView()
                .presentationDetents([.medium])
        }
        .sensoryFeedback(.success, trigger: savedTick)
        .onChange(of: pickedItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    handle(image)
                }
                pickedItem = nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .idle:
            captureOptions
                .transition(.opacity)
        case .working:
            readingState
                .transition(.opacity)
        case .confirming:
            ConfirmReceiptView(draft: $draft, onSave: save, onDiscard: discard)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var captureOptions: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.xxl, style: .continuous)
                    .fill(Theme.Palette.accent.opacity(0.10))
                    .frame(width: 108, height: 108)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Theme.Palette.accent)
            }
            VStack(spacing: Theme.Space.xs) {
                Text("Scan a receipt")
                    .font(.appHeadline)
                    .foregroundStyle(Theme.Palette.text)
                Text("Snap a photo and the amount, date, and category are filled in for you.")
                    .font(.appCallout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(.horizontal, Theme.Space.lg)

            Spacer()

            VStack(spacing: Theme.Space.sm) {
                if quotaSpent {
                    Button {
                        showQuotaWall = true
                    } label: {
                        Label("Sign in to keep scanning", systemImage: "lock.fill")
                    }
                    .buttonStyle(.primary)
                } else {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take photo", systemImage: "camera.fill")
                    }
                    .buttonStyle(.primary)

                    PhotosPicker(selection: $pickedItem, matching: .images) {
                        Label("Choose from library", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.secondaryFill)
                }

                Button("Enter manually", systemImage: "square.and.pencil", action: startManualEntry)
                    .font(.appCallout)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.top, Theme.Space.xs)
            }
        }
        .padding(Theme.Space.lg)
    }

    private func startManualEntry() {
        draft = ReceiptDraft()
        pendingServerID = nil
        previewImage = nil
        withAnimation(Theme.Motion.spring) { stage = .confirming }
    }

    /// Thin banner: how many free scans are left (anonymous only).
    @ViewBuilder
    private var scanAllowance: some View {
        if !auth.isSignedIn, let remaining = auth.scansRemaining {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: remaining <= 0 ? "lock.fill" : "sparkles")
                Text(
                    remaining <= 0
                        ? "No free scans left"
                        : "^[\(remaining) free scan](inflect: true) left"
                )
                .font(.appCaption.weight(.medium))
            }
            .foregroundStyle(remaining <= 3 ? Theme.Palette.accent : Theme.Palette.textSecondary)
            .padding(.vertical, Theme.Space.xs)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
    }

    private var readingState: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer()
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                            .strokeBorder(Theme.Palette.border)
                    }
            }
            HStack(spacing: Theme.Space.sm) {
                ProgressView()
                Text("Reading receipt…")
                    .font(.appCallout)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SkeletonBlock(height: 14, width: 160)
                SkeletonBlock(height: 14, width: 220)
                SkeletonBlock(height: 14, width: 120)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.xl)
            Spacer()
        }
        .padding(Theme.Space.lg)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func handle(_ image: UIImage) {
        previewImage = image
        withAnimation(Theme.Motion.base) { stage = .working }
        Task {
            do {
                let extractor = await ReceiptExtractionService.makeExtractor(auth: auth)
                let result = try await extractor.extractReceipt(from: image)
                auth.noteScansRemaining(result.scansRemaining)
                draft = result.draft
                pendingServerID = result.serverID
                withAnimation(Theme.Motion.spring) { stage = .confirming }
            } catch ReceiptExtractionError.quotaExhausted {
                auth.noteScansRemaining(0)
                withAnimation(Theme.Motion.base) { stage = .idle }
                showQuotaWall = true
            } catch {
                errorMessage = error.localizedDescription
                withAnimation(Theme.Motion.base) { stage = .idle }
            }
        }
    }

    private func save() {
        let receipt = draft.makeReceipt()
        receipt.remoteID = pendingServerID
        modelContext.insert(receipt)
        savedTick += 1

        let auth = auth
        let context = modelContext
        if pendingServerID != nil {
            // The server row holds the raw extraction — push the confirmed edits.
            Task { await AccountSync.pushUpdate(receipt, auth: auth) }
        } else if auth.isSignedIn {
            // Manual entry — nothing on the server yet.
            Task { await AccountSync.pushCreate(receipt, auth: auth, context: context) }
        }
        pendingServerID = nil
        reset()
    }

    /// User bailed on the confirm screen. If the backend already created a row
    /// for this scan (signed in), remove it so nothing orphaned is left behind.
    private func discard() {
        if let id = pendingServerID {
            let auth = auth
            Task {
                let client = await ReceiptExtractionService.makeAuthorizedClient(auth: auth)
                try? await client?.deleteReceipt(id: id)
            }
        }
        pendingServerID = nil
        reset()
    }

    private func reset() {
        draft = ReceiptDraft()
        pickedItem = nil
        previewImage = nil
        withAnimation(Theme.Motion.base) { stage = .idle }
    }
}

#Preview {
    ScanFlowView()
        .modelContainer(for: Receipt.self, inMemory: true)
        .environment(AuthManager())
}
