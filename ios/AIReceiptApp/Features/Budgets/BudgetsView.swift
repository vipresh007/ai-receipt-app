import SwiftUI

/// Monthly per-category spending limits. Signed-in only — the limit lives on
/// the account (`AccountSync.listBudgets`/`setBudget`/`deleteBudget`) so it's
/// the same on every device.
struct BudgetsView: View {
    @Environment(AuthManager.self) private var auth

    @State private var budgets: [ReceiptExtractionAPIClient.BudgetDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAdd = false
    @State private var editingBudget: ReceiptExtractionAPIClient.BudgetDTO?

    var body: some View {
        NavigationStack {
            Group {
                switch auth.state {
                case .signedIn:
                    signedInContent
                case .anonymous:
                    anonymousPrompt
                }
            }
            .navigationTitle("Budgets")
            .toolbar {
                if auth.isSignedIn, !budgets.isEmpty {
                    ToolbarItem {
                        EditButton()
                    }
                }
                if auth.isSignedIn {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingAdd = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingAdd) {
            AddBudgetSheet(existingCategories: Set(budgets.map(\.categorySlug))) { category, limit in
                await save(category: category, limit: limit)
            }
        }
        .sheet(item: $editingBudget) { budget in
            AddBudgetSheet(editing: budget) { category, limit in
                await save(category: category, limit: limit)
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var signedInContent: some View {
        if isLoading && budgets.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if budgets.isEmpty {
            ContentUnavailableView(
                "No budgets yet",
                systemImage: "chart.pie",
                description: Text("Tap + to set a monthly limit for a category.")
            )
        } else {
            List {
                ForEach(budgets) { budget in
                    Button {
                        editingBudget = budget
                    } label: {
                        BudgetRow(budget: budget)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: delete)
            }
            .refreshable { await load() }
        }
    }

    private var anonymousPrompt: some View {
        ScrollView {
            AppCard {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    SectionLabel("Sign in to set budgets")
                    Text("Budgets live on your account, so a limit you set here also shows on the web app.")
                        .font(.appCallout)
                        .foregroundStyle(Theme.Palette.text)
                    SignInButton(onSignedIn: { Task { await load() } })
                }
            }
            .padding(Theme.Space.lg)
        }
    }

    private func load() async {
        guard auth.isSignedIn else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            budgets = try await AccountSync.listBudgets(auth: auth)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(category: ExpenseCategory, limit: String) async {
        do {
            try await AccountSync.setBudget(category: category, monthlyLimit: limit, auth: auth)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        let targets = offsets.map { budgets[$0] }
        Task {
            for budget in targets {
                let category = ExpenseCategory(rawValue: budget.categorySlug) ?? .other
                try? await AccountSync.deleteBudget(category: category, auth: auth)
            }
            await load()
        }
    }
}

// internal (not private) — also used by the Dashboard's Budgets summary card.
struct BudgetRow: View {
    let budget: ReceiptExtractionAPIClient.BudgetDTO

    private var category: ExpenseCategory {
        ExpenseCategory(rawValue: budget.categorySlug) ?? .other
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var progressColor: Color {
        switch budget.percentUsed {
        case ..<70: Theme.Palette.success
        case 70..<100: Theme.Palette.warning
        default: Theme.Palette.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.md) {
                CategoryGlyph(category: category, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.displayName)
                        .font(.appCallout.weight(.medium))
                        .foregroundStyle(Theme.Palette.text)
                    Text(subtitle)
                        .font(.mono(12, relativeTo: .caption))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                Text("\(Int(budget.percentUsed.rounded()))%")
                    .font(.mono(13, medium: true, relativeTo: .callout))
                    .foregroundStyle(progressColor)
            }
            ProgressView(value: min(budget.percentUsed, 100), total: 100)
                .tint(progressColor)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let spent = Decimal(string: budget.spent) ?? 0
        let limit = Decimal(string: budget.monthlyLimit) ?? 0
        let spentText = spent.formatted(.currency(code: currencyCode))
        let limitText = limit.formatted(.currency(code: currencyCode))
        return "\(spentText) of \(limitText)"
    }
}

/// Add a budget for a not-yet-budgeted category, or edit an existing one's
/// limit (category is fixed once a budget exists — delete and re-add to
/// change it, same as everywhere else category-scoped things work here).
private struct AddBudgetSheet: View {
    var existingCategories: Set<String> = []
    var editing: ReceiptExtractionAPIClient.BudgetDTO?
    let onSave: (ExpenseCategory, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category: ExpenseCategory?
    @State private var limitText = ""
    @State private var isSaving = false

    init(
        existingCategories: Set<String> = [],
        editing: ReceiptExtractionAPIClient.BudgetDTO? = nil,
        onSave: @escaping (ExpenseCategory, String) async -> Void
    ) {
        self.existingCategories = existingCategories
        self.editing = editing
        self.onSave = onSave
        _category = State(initialValue: editing.map { ExpenseCategory(rawValue: $0.categorySlug) ?? .other })
        _limitText = State(initialValue: editing?.monthlyLimit ?? "")
    }

    private var availableCategories: [ExpenseCategory] {
        ExpenseCategory.allCases.filter { !existingCategories.contains($0.rawValue) }
    }

    private var canSave: Bool {
        category != nil && Decimal(string: limitText).map { $0 > 0 } == true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    if let editing {
                        let fixedCategory = ExpenseCategory(rawValue: editing.categorySlug) ?? .other
                        Label(fixedCategory.displayName, systemImage: fixedCategory.systemImage)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    } else {
                        Picker("Category", selection: $category) {
                            Text("Choose one").tag(ExpenseCategory?.none)
                            ForEach(availableCategories) { category in
                                Text(category.displayName).tag(ExpenseCategory?.some(category))
                            }
                        }
                    }
                }
                Section("Monthly limit") {
                    TextField("Amount", text: $limitText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle(editing == nil ? "Add Budget" : "Edit Budget")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let category else { return }
                        isSaving = true
                        Task {
                            await onSave(category, limitText)
                            dismiss()
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
    }
}

#Preview {
    BudgetsView()
        .environment(AuthManager())
}
