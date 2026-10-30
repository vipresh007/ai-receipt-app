import SwiftUI

/// "Take a photo" from a group or person: scan it (saved to Receipts like any
/// scan), wait for it to reach the account, then hand it to the split editor.
struct ScanToSplitModifier: ViewModifier {
    @Binding var isPresented: Bool
    /// Set to the receipt once it's ready to split.
    @Binding var ready: Receipt?
    @Binding var status: String?

    @State private var scanned: Receipt?

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: $isPresented,
            onDismiss: {
                guard let receipt = scanned else { return }
                scanned = nil
                Task { await waitForAccount(receipt) }
            }
        ) {
            ScanFlowView(onSaved: { receipt in
                scanned = receipt
                isPresented = false
            })
        }
    }

    /// A scan saved on the phone's quick read gets its account id when the
    /// server's read lands (a few seconds); splitting needs that id.
    @MainActor
    private func waitForAccount(_ receipt: Receipt) async {
        status = "Finishing the scan…"
        for _ in 0..<60 {
            if receipt.remoteID != nil {
                status = nil
                ready = receipt
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        status = "Saved to Receipts. Split it from there, or use \u{201C}From a receipt\u{201D}, once it syncs."
    }
}

extension View {
    func scanToSplit(isPresented: Binding<Bool>, ready: Binding<Receipt?>, status: Binding<String?>) -> some View {
        modifier(ScanToSplitModifier(isPresented: isPresented, ready: ready, status: status))
    }
}
