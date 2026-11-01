import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Share → Tally" from Photos, Files, Mail or a browser: the photo or PDF is
/// dropped into the shared inbox and Tally reads it next time it opens
/// (`SharedInbox` in the app).
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.take(extensionContext?.inputItems as? [NSExtensionItem] ?? []) }
    }
}

@MainActor
@Observable
final class ShareModel {
    enum State { case working, saved, failed(String) }
    var state: State = .working

    func take(_ items: [NSExtensionItem]) async {
        let providers = items.flatMap { $0.attachments ?? [] }
        guard let inbox = AppGroup.inbox else {
            state = .failed("Tally couldn't open its inbox.")
            return
        }
        for provider in providers {
            for type in [UTType.pdf, UTType.image] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                if let url = await copy(provider, type: type, into: inbox) {
                    _ = url
                    state = .saved
                    return
                }
            }
        }
        state = .failed("That isn't a photo or a PDF.")
    }

    private func copy(_ provider: NSItemProvider, type: UTType, into inbox: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { file, _ in
                guard let file else { return continuation.resume(returning: nil) }
                let ext = type == .pdf ? "pdf" : (file.pathExtension.isEmpty ? "jpg" : file.pathExtension)
                let target = inbox.appendingPathComponent("\(UUID().uuidString).\(ext)")
                do {
                    try FileManager.default.copyItem(at: file, to: target)
                    continuation.resume(returning: target)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

struct ShareView: View {
    let model: ShareModel
    let done: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            switch model.state {
            case .working:
                ProgressView()
                Text("Adding to Tally…")
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color(red: 0.851, green: 0.682, blue: 0.361))
                Text("Added to Tally").font(.headline)
                Text("Open Tally and it's read for you to check and save.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(.orange)
                Text(message).multilineTextAlignment(.center)
            }
            if case .working = model.state {} else {
                Button("Done", action: done)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.851, green: 0.682, blue: 0.361))
                    .padding(.top, 8)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
