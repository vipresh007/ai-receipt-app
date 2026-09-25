import SwiftUI
import PhotosUI

/// Capture flow: pick an image (camera or library) → read it → confirm and save.
///
/// The confirm screen opens on the phone's own quick read (`ReceiptQuickParser`
/// over on-device OCR) while the server's full extraction is still running;
/// when that lands it fills in what the user hasn't touched. Save and Discard
/// work at any point — a late result follows the receipt (see `PendingScan`).
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
    /// True while the confirm screen is a from-scratch entry (no scan).
    @State private var isManualEntry = false
    /// Set while the confirm screen shows the quick read and the server's is on its way.
    @State private var pending: PendingScan?
    /// Why the server's read never arrived (the quick read stays editable).
    @State private var refineNote: String?

    /// A scan showing its quick read while the server extraction runs. A class
    /// so the in-flight task sees what the user did meanwhile.
    @MainActor
    private final class PendingScan {
        enum Outcome {
            case open
            case saved(Receipt)
            case discarded
        }

        /// The quick read as first shown — fields still equal to it are the
        /// ones the user hasn't touched.
        let baseline: ReceiptDraft
        var outcome: Outcome = .open

        init(baseline: ReceiptDraft) {
            self.baseline = baseline
        }
    }

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
            ConfirmReceiptView(
                draft: $draft,
                title: isManualEntry ? "New expense" : "Confirm",
                isRefining: pending != nil,
                refineNote: refineNote,
                onSave: save,
                onDiscard: discard
            )
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
        pending = nil
        refineNote = nil
        previewImage = nil
        isManualEntry = true
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
            .background(Theme.Palette.bg)
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

    private func handle(_ photo: UIImage) {
        // Everything downstream (OCR, upload, the stored copy) uses the capped size.
        let image = photo.scaledDown(toLongEdge: LLMReceiptExtractor.maxUploadEdge)
        previewImage = image
        isManualEntry = false
        pendingServerID = nil
        refineNote = nil
        withAnimation(Theme.Motion.base) { stage = .working }
        Task {
            // On-device OCR first: it takes well under a second, its rows go to
            // the server as context, and if they give a total the confirm
            // screen opens now instead of after the server round trip.
            let rows = (try? await ReceiptTextRecognizer().recognizeText(in: image)) ?? []
            var quick = ReceiptQuickParser.draft(from: rows)
            quick.imageData = image.jpegData(compressionQuality: 0.7)

            var scan: PendingScan?
            if ReceiptQuickParser.isUseful(quick) {
                let shown = PendingScan(baseline: quick)
                scan = shown
                pending = shown
                draft = quick
                withAnimation(Theme.Motion.spring) { stage = .confirming }
            }

            do {
                let extractor = await ReceiptExtractionService.makeExtractor(auth: auth)
                let result = try await extractor.extractReceipt(from: image, ocrLines: rows)
                auth.noteScansRemaining(result.scansRemaining)
                finish(scan, with: result)
            } catch {
                fail(scan, with: error)
            }
        }
    }

    /// The server's read arrived.
    private func finish(_ scan: PendingScan?, with result: ReceiptExtractionResult) {
        guard let scan else {
            // Nothing was shown yet (the quick read found no total).
            draft = result.draft
            pendingServerID = result.serverID
            withAnimation(Theme.Motion.spring) { stage = .confirming }
            return
        }
        switch scan.outcome {
        case .open:
            withAnimation(Theme.Motion.base) {
                draft = draft.refined(with: result.draft, baseline: scan.baseline)
            }
            pendingServerID = result.serverID
            if pending === scan { pending = nil }
        case .saved(let receipt):
            // Saved on the quick read: fill in what the user left alone and link
            // the server's row (signed in), pushing the confirmed values to it.
            let current = ReceiptDraft(
                merchant: receipt.merchant, date: receipt.date, total: receipt.total,
                tax: receipt.tax, category: receipt.category, items: receipt.items
            )
            let merged = current.refined(with: result.draft, baseline: scan.baseline)
            receipt.merchant = merged.merchant
            receipt.date = merged.date
            receipt.total = merged.total
            receipt.tax = merged.tax
            receipt.category = merged.category
            receipt.items = merged.items
            receipt.remoteID = result.serverID
            try? modelContext.save()
            if result.serverID != nil {
                let auth = auth
                Task { await AccountSync.pushUpdate(receipt, auth: auth) }
            }
        case .discarded:
            // Signed-in extraction already created a row — remove it.
            if let id = result.serverID { deleteServerReceipt(id) }
        }
    }

    /// The server's read failed.
    private func fail(_ scan: PendingScan?, with error: Error) {
        var outOfScans = false
        if let extractionError = error as? ReceiptExtractionError,
            case .quotaExhausted = extractionError
        {
            outOfScans = true
            auth.noteScansRemaining(0)
        }
        guard let scan else {
            withAnimation(Theme.Motion.base) { stage = .idle }
            if outOfScans {
                showQuotaWall = true
            } else {
                errorMessage = error.localizedDescription
            }
            return
        }
        switch scan.outcome {
        case .open:
            refineNote = outOfScans
                ? "You've used your free scans, so the rest wasn't filled in. Check the fields and save, or sign in to keep scanning."
                : "Couldn't read the rest of the receipt. Check the fields and save."
            if pending === scan { pending = nil }
        case .saved(let receipt):
            // Kept from the quick read alone; signed in, it still needs a server row.
            if auth.isSignedIn, receipt.remoteID == nil {
                let auth = auth
                let context = modelContext
                Task { await AccountSync.pushCreate(receipt, auth: auth, context: context) }
            }
        case .discarded:
            break
        }
    }

    private func save() {
        let receipt = draft.makeReceipt()
        receipt.remoteID = pendingServerID
        modelContext.insert(receipt)
        savedTick += 1

        let auth = auth
        let context = modelContext
        if let scan = pending {
            // The server's read is still coming; `finish` lands it on this receipt.
            scan.outcome = .saved(receipt)
        } else if pendingServerID != nil {
            // The server row holds the raw extraction — push the confirmed edits.
            Task { await AccountSync.pushUpdate(receipt, auth: auth) }
        } else if auth.isSignedIn {
            // Manual entry (or the server read failed) — nothing on the server yet.
            Task { await AccountSync.pushCreate(receipt, auth: auth, context: context) }
        }
        pendingServerID = nil
        reset()
    }

    /// User bailed on the confirm screen. If the backend already created a row
    /// for this scan (signed in), remove it so nothing orphaned is left behind.
    private func discard() {
        pending?.outcome = .discarded
        if let id = pendingServerID { deleteServerReceipt(id) }
        pendingServerID = nil
        reset()
    }

    private func deleteServerReceipt(_ id: String) {
        let auth = auth
        Task {
            let client = await ReceiptExtractionService.makeAuthorizedClient(auth: auth)
            try? await client?.deleteReceipt(id: id)
        }
    }

    private func reset() {
        draft = ReceiptDraft()
        pending = nil
        refineNote = nil
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
