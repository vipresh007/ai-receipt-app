import SwiftUI

struct ReceiptDetailView: View {
    @Bindable var receipt: Receipt
    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext

    @State private var loadingImage = false

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    var body: some View {
        Form {
            if let data = receipt.imageData, let image = UIImage(data: data) {
                LedgerSection {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 260)
                }
            } else if loadingImage {
                LedgerSection {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .frame(height: 120)
                }
            }

            LedgerSection("Merchant") {
                TextField("Store name", text: $receipt.merchant)
                DatePicker("Date", selection: $receipt.date, displayedComponents: .date)
            }

            LedgerSection("Amount") {
                LabeledContent("Total") {
                    TextField("Total", value: $receipt.total, format: .currency(code: currencyCode))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                LabeledContent("Tax") {
                    TextField("Tax", value: $receipt.tax, format: .currency(code: currencyCode))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
            }

            LedgerSection("Category") {
                Picker("Category", selection: $receipt.category) {
                    ForEach(ExpenseCategory.allCases) { category in
                        Label(category.displayName, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
            }

            if !receipt.items.isEmpty {
                LedgerSection("Items") {
                    ForEach($receipt.items) { $item in
                        HStack {
                            TextField("Item", text: $item.name)
                            Spacer()
                            TextField("Price", value: $item.price, format: .currency(code: currencyCode))
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(width: 90)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .ledgerBackground()
        .navigationTitle(receipt.merchant)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadImageIfNeeded() }
        .onDisappear {
            // SwiftData autosaves the edits locally; mirror them to the account.
            let receipt = receipt
            let auth = auth
            Task { await AccountSync.pushUpdate(receipt, auth: auth) }
        }
    }

    /// A receipt pulled from another device carries no image bytes — fetch them
    /// from the backend the first time it's opened here.
    private func loadImageIfNeeded() async {
        guard receipt.imageData == nil, receipt.remoteID != nil, !loadingImage else { return }
        loadingImage = true
        defer { loadingImage = false }
        await AccountSync.fetchImageIfNeeded(receipt, auth: auth, context: modelContext)
    }
}
