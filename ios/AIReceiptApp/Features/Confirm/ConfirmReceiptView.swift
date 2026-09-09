import SwiftUI

/// Quick confirmation screen: the user fixes anything the extractor got wrong,
/// then saves.
struct ConfirmReceiptView: View {
    @Binding var draft: ReceiptDraft
    var title = "Confirm"
    var onSave: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        Form {
            Section("Merchant") {
                TextField("Store name", text: $draft.merchant)
                DatePicker("Date", selection: $draft.date, displayedComponents: .date)
            }

            Section("Amount") {
                CurrencyRow(label: "Total", value: $draft.total)
                CurrencyRow(label: "Tax", value: $draft.tax)
            }

            Section("Category") {
                Picker("Category", selection: $draft.category) {
                    ForEach(ExpenseCategory.allCases) { category in
                        Label(category.displayName, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
            }

            if !draft.items.isEmpty {
                Section("Items") {
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
            }
        }
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
