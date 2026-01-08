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

    @StateObject private var transactionsViewModel: AccountTransactionsViewModel
    @State private var showAddTransaction = false

    init(viewModel: FinancialAccountsViewModel, account: FinancialAccount) {
        self.viewModel = viewModel
        self.account = account
        let context = account.managedObjectContext ?? PersistenceController.shared.container.viewContext
        let transactionsVM = AccountTransactionsViewModel(account: account, context: context)
        transactionsVM.onAccountUpdated = { [weak viewModel] in
            viewModel?.fetchAccounts()
        }
        _transactionsViewModel = StateObject(wrappedValue: transactionsVM)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("Account Details") {
                    HStack {
                        Text("Account Type")
                        Spacer()
                        Text(account.accountType?.capitalized ?? "Unknown")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Balance")
                        Spacer()
                        Text((account.balance?.decimalValue ?? 0).asCurrency())
                            .foregroundColor(ColorTheme.primaryText)
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
        }
    }

    private func deleteTransactions(at offsets: IndexSet) {
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
