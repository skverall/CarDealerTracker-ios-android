//
//  EditAccountView.swift
//  Ezcar24Business
//
//  Created by User on 11/19/25.
//

import SwiftUI

struct EditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: FinancialAccountsViewModel
    let account: FinancialAccount
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject private var permissionService = PermissionService.shared

    @StateObject private var transactionsViewModel: AccountTransactionsViewModel
    @State private var showAddTransaction = false
    @State private var editedKind: FinancialAccountKind
    @State private var editedName: String
    @State private var errorMessage: String?

    private var canDeleteRecords: Bool {
        if case .signedIn = sessionStore.status {
            return permissionService.can(.deleteRecords)
        }
        return true
    }

    init(viewModel: FinancialAccountsViewModel, account: FinancialAccount) {
        self.viewModel = viewModel
        self.account = account
        let context = account.managedObjectContext ?? PersistenceController.shared.container.viewContext
        let transactionsVM = AccountTransactionsViewModel(account: account, context: context)
        transactionsVM.onAccountUpdated = { [weak viewModel] in
            viewModel?.fetchAccounts()
        }
        _transactionsViewModel = StateObject(wrappedValue: transactionsVM)
        let parsed = FinancialAccountKind.parse(account.accountType)
        _editedKind = State(initialValue: parsed.kind)
        _editedName = State(initialValue: parsed.name ?? (parsed.kind == .other ? (account.accountType ?? "") : ""))
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("Account Details") {
                    Picker("Account Type", selection: $editedKind) {
                        ForEach(FinancialAccountKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    
                    TextField(editedKind == .cash ? "Account Name (optional)" : "Account Name", text: $editedName)

                    HStack {
                        Text("Balance")
                        Spacer()
                        Text((account.balance?.decimalValue ?? 0).asCurrency())
                            .foregroundColor(ColorTheme.primaryText)
                    }
                    
                    Button("Save Changes") {
                        let error = viewModel.updateAccount(account, kind: editedKind, name: editedName)
                        if let error {
                            errorMessage = error
                        } else {
                            dismiss()
                        }
                    }
                }

                Section("Transactions") {
                    if transactionsViewModel.transactions.isEmpty {
                        ContentUnavailableView(
                            "No Transactions",
                            systemImage: "arrow.up.arrow.down.circle",
                            description: Text("Add a deposit or withdrawal to track cash flow.")
                        )
                    } else {
                        ForEach(transactionsViewModel.transactions, id: \.objectID) { transaction in
                            AccountTransactionRow(transaction: transaction)
                        }
                        .onDelete(perform: deleteTransactions)
                        .deleteDisabled(!canDeleteRecords)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Account Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localizedString) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showAddTransaction = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(ColorTheme.primary)
                    }
                }
            }
            .sheet(isPresented: $showAddTransaction) {
                AddAccountTransactionView { type, amount, date, note in
                    transactionsViewModel.addTransaction(type: type, amount: amount, date: date, note: note)
                }
                .presentationDetents([.medium, .large])
            }
            .alert("Account Error", isPresented: Binding(get: {
                errorMessage != nil
            }, set: { _ in
                errorMessage = nil
            })) {
                Button("ok".localizedString, role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func deleteTransactions(at offsets: IndexSet) {
        guard canDeleteRecords else { return }
        for index in offsets {
            let transaction = transactionsViewModel.transactions[index]
            transactionsViewModel.deleteTransaction(transaction)
        }
    }
}

private struct AccountTransactionRow: View {
    let transaction: AccountTransaction

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: transaction.date ?? Date())
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.transactionTypeEnum.iconName)
                .foregroundColor(transaction.transactionTypeEnum.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.transactionTypeEnum.title)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)

                if let note = transaction.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }

                Text(formattedDate)
                    .font(.caption2)
                    .foregroundColor(ColorTheme.tertiaryText)
            }

            Spacer()

            Text(transaction.amountDecimal.asCurrency())
                .font(.headline)
                .foregroundColor(transaction.transactionTypeEnum.color)
        }
        .padding(.vertical, 4)
    }
}
