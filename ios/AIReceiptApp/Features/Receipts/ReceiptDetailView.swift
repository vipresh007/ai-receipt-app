import SwiftUI

struct ReceiptDetailView: View {
    @Bindable var receipt: Receipt

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    var body: some View {
        Form {
            if let data = receipt.imageData, let image = UIImage(data: data) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 260)
                }
            }

            Section("Merchant") {
                TextField("Store name", text: $receipt.merchant)
                DatePicker("Date", selection: $receipt.date, displayedComponents: .date)
            }

            Section("Amount") {
                LabeledContent("Total") {
                    Text(receipt.total, format: .currency(code: currencyCode))
                }
                LabeledContent("Tax") {
                    Text(receipt.tax, format: .currency(code: currencyCode))
                }
            }

            Section("Category") {
                Picker("Category", selection: $receipt.category) {
                    ForEach(ExpenseCategory.allCases) { category in
                        Label(category.displayName, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
            }

            if !receipt.items.isEmpty {
                Section("Items") {
                    ForEach(receipt.items) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text(item.price, format: .currency(code: currencyCode))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(receipt.merchant)
        .navigationBarTitleDisplayMode(.inline)
    }
}
