import SwiftUI
import PhotosUI

/// Capture flow: pick an image (camera or library) → run the extractor →
/// confirm and save.
struct ScanFlowView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var pickedItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var stage: Stage = .idle
    @State private var draft = ReceiptDraft()
    @State private var errorMessage: String?

    private enum Stage {
        case idle, working, confirming
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .idle:
                    captureOptions
                case .working:
                    ProgressView("Reading receipt…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .confirming:
                    ConfirmReceiptView(draft: $draft, onSave: save, onDiscard: reset)
                }
            }
            .navigationTitle("Scan")
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

    private var captureOptions: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Snap a photo of a receipt and it'll be added to your spending automatically.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button {
                showCamera = true
            } label: {
                Label("Take photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            PhotosPicker(selection: $pickedItem, matching: .images) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func handle(_ image: UIImage) {
        stage = .working
        Task {
            do {
                draft = try await ReceiptExtractionService.current.extractReceipt(from: image)
                stage = .confirming
            } catch {
                errorMessage = error.localizedDescription
                stage = .idle
            }
        }
    }

    private func save() {
        modelContext.insert(draft.makeReceipt())
        reset()
    }

    private func reset() {
        draft = ReceiptDraft()
        pickedItem = nil
        stage = .idle
    }
}

#Preview {
    ScanFlowView()
        .modelContainer(for: Receipt.self, inMemory: true)
}
