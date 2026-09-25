import SwiftUI

/// Quick confirmation screen: the user fixes anything the extractor got wrong,
/// then saves.
struct ConfirmReceiptView: View {
    @Binding var draft: ReceiptDraft
    var title = "Confirm"
    /// The fields show the phone's quick read; the server's full read is on
    /// its way and will fill in the rest.
    var isRefining = false
    /// Why the server's read won't arrive, if it failed.
    var refineNote: String?
    var onSave: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        Form {
            if isRefining || refineNote != nil {
                LedgerSection {
                    refineStatus
                }
            }

            LedgerSection("Merchant") {
                TextField("Store name", text: $draft.merchant)
                DatePicker("Date", selection: $draft.date, displayedComponents: .date)
            }

            LedgerSection("Amount") {
                CurrencyRow(label: "Total", value: $draft.total)
                if isRefining && draft.tax == 0 {
                    pendingRow("Tax", width: 56)
                } else {
                    CurrencyRow(label: "Tax", value: $draft.tax)
                }
            }

            LedgerSection("Category") {
                // The phone doesn't guess categories — the server's read does.
                if isRefining && draft.category == .other {
                    pendingRow("Category", width: 96)
                } else {
                    Picker("Category", selection: $draft.category) {
                        ForEach(ExpenseCategory.allCases) { category in
                            Label(category.displayName, systemImage: category.systemImage)
                                .tag(category)
                        }
                    }
                }
            }

            if !draft.items.isEmpty {
                LedgerSection("Items") {
                    ForEach($draft.items) { $item in
                        HStack {
                            TextField("Item", text: $item.name)
                            Spacer()
                            Text(item.price, format: .currency(code: currencyCode))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { draft.items.remove(atOffsets: $0) }
                }
            } else if isRefining {
                LedgerSection("Items") {
                    ForEach([170.0, 130.0, 150.0], id: \.self) { width in
                        HStack {
                            SkeletonBlock(height: 14, width: width)
                            Spacer()
                            SkeletonBlock(height: 14, width: 52)
                        }
                        .padding(.vertical, Theme.Space.xs)
                    }
                }
            }
        }
        .ledgerBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Discard", role: .destructive, action: onDiscard)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: onSave)
                    .disabled(!draft.isValid)
            }
        }
    }

    /// A field the quick read didn't find, while the server's read is coming.
    private func pendingRow(_ label: String, width: CGFloat) -> some View {
        HStack {
            Text(label)
            Spacer()
            SkeletonBlock(height: 14, width: width)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), reading")
    }

    @ViewBuilder
    private var refineStatus: some View {
        if isRefining {
            HStack(spacing: Theme.Space.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("Reading the rest of the receipt…")
                    .font(.appCallout)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
        } else if let refineNote {
            Label {
                Text(refineNote)
                    .font(.appCallout)
                    .foregroundStyle(Theme.Palette.textSecondary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Palette.warning)
            }
        }
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }
}

/// A right-aligned, editable currency amount.
private struct CurrencyRow: View {
    let label: String
    @Binding var value: Decimal

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: $value, format: .currency(code: currencyCode))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    NavigationStack {
        ConfirmReceiptView(
            draft: .constant(
                ReceiptDraft(
                    merchant: "Whole Foods Market",
                    date: .now,
                    total: 22.79,
                    tax: 1.34,
                    category: .groceries,
                    items: [ReceiptLineItem(name: "Bananas", price: 1.79)]
                )
            ),
            onSave: {},
            onDiscard: {}
        )
    }
}
