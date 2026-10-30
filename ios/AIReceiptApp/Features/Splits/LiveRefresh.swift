import SwiftUI

/// One open live-updates stream (Server-Sent Events, `GET /v1/events`) while
/// the app is in the foreground and signed in. The server says "changed"
/// when something of yours changes; `tick` goes up, and screens showing
/// shared data refetch. No polling.
@Observable
@MainActor
final class LiveEvents {
    private(set) var tick = 0
    private var task: Task<Void, Never>?

    func start(_ auth: AuthManager) {
        guard task == nil else { return }
        task = Task { await run(auth) }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func run(_ auth: AuthManager) async {
        var delay = 2.0
        while !Task.isCancelled {
            do {
                guard let client = await ReceiptExtractionService.makeAuthorizedClient(auth: auth) else {
                    try await Task.sleep(for: .seconds(30))
                    continue
                }
                var request = try client.authorized("v1/events", method: "GET")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                // The server sends a heartbeat every 25s; silence longer than
                // this means the connection is gone.
                request.timeoutInterval = 90
                let (bytes, response) = try await client.session.bytes(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                delay = 2
                for try await line in bytes.lines where line.hasPrefix("event: changed") {
                    tick += 1
                }
            } catch is CancellationError {
                return
            } catch {
                // Dropped or refused: try again shortly, backing off.
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay * 2, 30)
        }
    }
}

extension View {
    /// Keep a screen of shared data current without pulling to refresh:
    /// re-run `load` whenever the server pushes a change, and when the app
    /// comes back to the foreground.
    func liveRefresh(_ load: @escaping () async -> Void) -> some View {
        modifier(LiveRefresh(load: load))
    }
}

private struct LiveRefresh: ViewModifier {
    let load: () async -> Void
    @Environment(LiveEvents.self) private var live
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: live.tick) { _, _ in Task { await load() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await load() } }
            }
    }
}
