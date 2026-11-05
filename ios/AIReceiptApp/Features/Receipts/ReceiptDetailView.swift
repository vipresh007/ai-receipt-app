import SwiftData
import SwiftUI

struct ReceiptDetailView: View {
    @Bindable var receipt: Receipt
    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext

    @State private var loadingImage = false
    @State private var showingPhoto = false
    /// The receipt as it was when opened: leaving without a change doesn't
    /// count as an edit (or call the server).
    @State private var opened: Data?
    @Query private var allReceipts: [Receipt]

    /// Items you've bought before, for "was $3.99 on Jun 12" under each line.
    private var tracked: [TrackedItem] { PriceTracker.items(in: allReceipts) }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    var body: some View {
        Form {
            if let data = receipt.imageData, let image = UIImage(data: data) {
                LedgerSection {
                    Button {
                        showingPhoto = true
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 260)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(7)
                                    .background(.black.opacity(0.45), in: Circle())
                                    .padding(6)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Receipt photo")
                    .accessibilityHint("Opens it full screen to zoom")
                }
                .fullScreenCover(isPresented: $showingPhoto) {
                    ReceiptPhotoViewer(image: image)
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
                if let myShare = receipt.myShare {
                    LabeledContent("Your share") {
                        Text(myShare, format: .currency(code: currencyCode))
                            .font(.appMoney)
                    }
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
                    let tracked = tracked
                    ForEach($receipt.items) { $item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                TextField("Item", text: $item.name)
                                Spacer()
                                TextField(
                                    "Price",
                                    value: $item.priceMovingTotal($receipt.total),
                                    format: .currency(code: currencyCode)
                                )
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(width: 90)
                                .foregroundStyle(.secondary)
                            }
                            if item.quantity > 1 {
                                Text("\(item.quantity) × \((item.price / Decimal(item.quantity)).formatted(.currency(code: currencyCode)))")
                                    .font(.appCaption)
                                    .foregroundStyle(Theme.Palette.textTertiary)
                            }
                            if let before = PriceTracker.earlier(for: item, on: receipt, in: tracked) {
                                PriceWasNote(before: before, now: item, currencyCode: currencyCode)
                            }
                        }
                    }
                    .onDelete { offsets in
                        receipt.total = max(0, receipt.total - receipt.items.priceSum(at: offsets))
                        receipt.items.remove(atOffsets: offsets)
                    }
                }
            }

            // Not for everyday spending (groceries, meals, rides, bills) unless a date was set.
            if ![.groceries, .restaurants, .transport, .utilities].contains(receipt.category)
                || receipt.returnBy != nil || receipt.warrantyUntil != nil {
                ReturnWarrantySection(receipt: receipt)
            }

            ReceiptSplitSection(receipt: receipt)

            Section {
            } footer: {
                Text(timesText)
                    .font(.appCaption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .ledgerBackground()
        .navigationTitle(receipt.merchant)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadImageIfNeeded() }
        .onAppear { if opened == nil { opened = snapshot } }
        .onChange(of: receipt.returnBy) { _, _ in Task { await rescheduleReminders() } }
        .onChange(of: receipt.warrantyUntil) { _, _ in Task { await rescheduleReminders() } }
        .onDisappear {
            // SwiftData autosaves the edits locally; mirror them to the account.
            guard snapshot != opened else { return }
            receipt.updatedAt = .now
            opened = snapshot
            let receipt = receipt
            let auth = auth
            Task { await AccountSync.pushUpdate(receipt, auth: auth) }
        }
    }

    private var snapshot: Data? {
        try? JSONEncoder().encode(ReceiptExtractionAPIClient.ReceiptWrite(from: receipt, includeImage: false))
    }

    /// "Added Nov 5, 2026 at 10:31 AM · Edited Nov 5 at 10:36 AM"
    private var timesText: String {
        func when(_ date: Date, year: Bool) -> String {
            let day = year
                ? date.formatted(.dateTime.month(.abbreviated).day().year())
                : date.formatted(.dateTime.month(.abbreviated).day())
            return "\(day) at \(date.formatted(date: .omitted, time: .shortened))"
        }
        var text = "Added \(when(receipt.createdAt, year: true))"
        if let edited = receipt.updatedAt, edited.timeIntervalSince(receipt.createdAt) > 60 {
            let sameYear = Calendar.current.isDate(edited, equalTo: receipt.createdAt, toGranularity: .year)
            text += " · Edited \(when(edited, year: !sameYear))"
        }
        return text
    }

    private func rescheduleReminders() async {
        await ReturnReminders.requestPermission()
        await ReturnReminders.sync(modelContext)
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


/// The last day it can go back and when the warranty ends, each reminded
/// ahead of time. Quick picks count from the purchase date.
private struct ReturnWarrantySection: View {
    @Bindable var receipt: Receipt

    private func from(_ component: Calendar.Component, _ value: Int) -> Date {
        Calendar.current.date(byAdding: component, value: value, to: receipt.date) ?? receipt.date
    }

    var body: some View {
        LedgerSection("Return & warranty") {
            if let returnBy = receipt.returnBy {
                DatePicker(
                    "Return by",
                    selection: Binding(get: { returnBy }, set: { receipt.returnBy = $0 }),
                    displayedComponents: .date
                )
                .swipeActions { Button("Remove", role: .destructive) { receipt.returnBy = nil } }
                DaysLeft(until: returnBy, noun: "to return it")
            } else {
                Menu {
                    Button("14 days after purchase") { receipt.returnBy = from(.day, 14) }
                    Button("30 days after purchase") { receipt.returnBy = from(.day, 30) }
                    Button("90 days after purchase") { receipt.returnBy = from(.day, 90) }
                } label: {
                    Label("Add a return date", systemImage: "arrow.uturn.backward.circle")
                }
            }
            if let warranty = receipt.warrantyUntil {
                DatePicker(
                    "Warranty until",
                    selection: Binding(get: { warranty }, set: { receipt.warrantyUntil = $0 }),
                    displayedComponents: .date
                )
                .swipeActions { Button("Remove", role: .destructive) { receipt.warrantyUntil = nil } }
            } else {
                Menu {
                    Button("1 year") { receipt.warrantyUntil = from(.year, 1) }
                    Button("2 years") { receipt.warrantyUntil = from(.year, 2) }
                    Button("3 years") { receipt.warrantyUntil = from(.year, 3) }
                } label: {
                    Label("Add a warranty", systemImage: "checkmark.shield")
                }
            }
        }
    }
}

private struct DaysLeft: View {
    let until: Date
    let noun: String

    var body: some View {
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: until)
        ).day ?? 0
        Text(
            days < 0 ? "The return window has closed."
                : days == 0 ? "Today is the last day \(noun)."
                : "\(days) day\(days == 1 ? "" : "s") left \(noun). You'll get a reminder 3 days before."
        )
        .font(.appCaption)
        .foregroundStyle(days >= 0 && days <= 3 ? Theme.Palette.danger : Theme.Palette.textSecondary)
    }
}
