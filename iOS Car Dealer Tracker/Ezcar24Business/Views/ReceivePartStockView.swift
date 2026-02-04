import SwiftUI
import CoreData

struct ReceivePartStockView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Part.name, ascending: true)],
        predicate: NSPredicate(format: "deletedAt == nil"),
        animation: .default
    )
    private var parts: FetchedResults<Part>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FinancialAccount.accountType, ascending: true)],
        predicate: NSPredicate(format: "deletedAt == nil"),
        animation: .default
    )
    private var accounts: FetchedResults<FinancialAccount>

    @State private var selectedPart: Part?
    @State private var selectedAccount: FinancialAccount?
    @State private var quantity: String = ""
    @State private var unitCost: String = ""
    @State private var batchLabel: String = ""
    @State private var notes: String = ""
    @State private var purchaseDate: Date = Date()
    @State private var showError = false

    var body: some View {
        Form {
            Section(header: Text("parts_receive_stock_section".localizedString)) {
                Picker("parts_receive_stock_part".localizedString, selection: $selectedPart) {
                    Text("parts_select_part".localizedString).tag(nil as Part?)
                    ForEach(parts) { part in
                        Text(part.displayName).tag(part as Part?)
                    }
                }

                TextField("parts_receive_stock_quantity".localizedString, text: $quantity)
                    .keyboardType(.decimalPad)
                    .onChange(of: quantity) { _, newValue in
                        quantity = filterDecimalInput(newValue)
                    }

                TextField("parts_receive_stock_unit_cost".localizedString, text: $unitCost)
                    .keyboardType(.decimalPad)
                    .onChange(of: unitCost) { _, newValue in
                        unitCost = filterDecimalInput(newValue)
                    }

                DatePicker("parts_receive_stock_date".localizedString, selection: $purchaseDate, displayedComponents: .date)
                TextField("parts_receive_stock_batch_label".localizedString, text: $batchLabel)
                TextField("parts_receive_stock_notes".localizedString, text: $notes, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
            }

            Section(header: Text("deposit_to_section".localizedString)) {
                Picker("account_label".localizedString, selection: $selectedAccount) {
                    Text("select_account".localizedString).tag(nil as FinancialAccount?)
                    ForEach(accounts) { account in
                        Text(account.displayTitle).tag(account as FinancialAccount?)
                    }
                }
            }

            Section(header: Text("parts_receive_stock_summary".localizedString)) {
                HStack {
                    Text("parts_receive_stock_total".localizedString)
                    Spacer()
                    Text(totalCost.asCurrency())
                        .foregroundColor(ColorTheme.primaryText)
                }
            }
        }
        .navigationTitle("parts_receive_stock_title".localizedString)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("cancel".localizedString) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("save".localizedString) { saveBatch() }
                    .disabled(!isFormValid)
            }
        }
        .alert("parts_receive_stock_error".localizedString, isPresented: $showError) {
            Button("ok".localizedString, role: .cancel) {}
        }
        .onAppear {
            if selectedPart == nil {
                selectedPart = parts.first
            }
            if selectedAccount == nil {
                selectedAccount = accounts.first(where: { $0.kind == .cash }) ?? accounts.first
            }
            if accounts.isEmpty {
                createDefaultAccountsIfNeeded()
            }
        }
        .onChange(of: accounts.count) { _, _ in
            if selectedAccount == nil {
                selectedAccount = accounts.first(where: { $0.kind == .cash }) ?? accounts.first
            }
        }
    }

    private var quantityDecimal: Decimal {
        Decimal(string: quantity) ?? 0
    }

    private var unitCostDecimal: Decimal {
        Decimal(string: unitCost) ?? 0
    }

    private var totalCost: Decimal {
        quantityDecimal * unitCostDecimal
    }

    private var isFormValid: Bool {
        selectedPart != nil && selectedAccount != nil && quantityDecimal > 0 && unitCostDecimal >= 0
    }

    private func saveBatch() {
        guard let part = selectedPart, let account = selectedAccount, quantityDecimal > 0 else { return }

        let batch = PartBatch(context: viewContext)
        batch.id = UUID()
        batch.part = part
        batch.batchLabel = batchLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : batchLabel
        batch.quantityReceived = NSDecimalNumber(decimal: quantityDecimal)
        batch.quantityRemaining = NSDecimalNumber(decimal: quantityDecimal)
        batch.unitCost = NSDecimalNumber(decimal: unitCostDecimal)
        batch.purchaseDate = purchaseDate
        batch.purchaseAccountId = account.id
        batch.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        batch.createdAt = Date()
        batch.updatedAt = batch.createdAt

        part.updatedAt = batch.updatedAt

        let currentBalance = account.balance?.decimalValue ?? 0
        account.balance = NSDecimalNumber(decimal: currentBalance - totalCost)
        account.updatedAt = batch.updatedAt

        do {
            try viewContext.save()
            if let dealerId = CloudSyncEnvironment.currentDealerId {
                Task {
                    await CloudSyncManager.shared?.upsertPart(part, dealerId: dealerId)
                    await CloudSyncManager.shared?.upsertPartBatch(batch, dealerId: dealerId)
                    await CloudSyncManager.shared?.upsertFinancialAccount(account, dealerId: dealerId)
                }
            }
            dismiss()
        } catch {
            print("ReceivePartStockView saveBatch error: \(error)")
            showError = true
        }
    }

    private func filterDecimalInput(_ value: String) -> String {
        value.filter { "0123456789.".contains($0) }
    }

    private func createDefaultAccountsIfNeeded() {
        guard accounts.isEmpty else { return }

        let cash = FinancialAccount(context: viewContext)
        cash.id = UUID()
        cash.accountType = "Cash"
        cash.balance = NSDecimalNumber(value: 0)
        cash.updatedAt = Date()

        let bank = FinancialAccount(context: viewContext)
        bank.id = UUID()
        bank.accountType = "Bank"
        bank.balance = NSDecimalNumber(value: 0)
        bank.updatedAt = Date()

        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            print("ReceivePartStockView createDefaultAccounts error: \(error)")
        }
    }
}
