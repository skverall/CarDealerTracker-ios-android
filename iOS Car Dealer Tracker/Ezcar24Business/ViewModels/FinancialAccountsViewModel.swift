#sourceLocation(file: "FinancialAccountsVM_FileA.swift", line: 1)
//
//  FinancialAccountsViewModel.swift
//  Ezcar24Business
//
//  Created by User on 11/19/25.
//

import Foundation
import CoreData
import SwiftUI

class FinancialAccountsViewModel: ObservableObject {
    @Published var accounts: [FinancialAccount] = []
    
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
        fetchAccounts()
    }
    
    func fetchAccounts() {
        let request: NSFetchRequest<FinancialAccount> = FinancialAccount.fetchRequest()
        request.predicate = NSPredicate(format: "deletedAt == nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FinancialAccount.accountType, ascending: true)]
        
        do {
            accounts = try context.fetch(request)
        } catch {
            print("Error fetching accounts: \(error)")
            accounts = []
        }
    }
    
    func createDefaultAccounts() {
        let now = Date()

        let cashAccount = FinancialAccount(context: context)
        cashAccount.id = UUID()
        cashAccount.accountType = FinancialAccountKind.compose(kind: .cash, name: nil)
        cashAccount.balance = NSDecimalNumber(value: 0)
        cashAccount.openingBalance = NSDecimalNumber(value: 0)
        cashAccount.updatedAt = now

        let bankAccount = FinancialAccount(context: context)
        bankAccount.id = UUID()
        bankAccount.accountType = FinancialAccountKind.compose(kind: .bank, name: nil)
        bankAccount.balance = NSDecimalNumber(value: 0)
        bankAccount.openingBalance = NSDecimalNumber(value: 0)
        bankAccount.updatedAt = now

        saveContext()
        fetchAccounts()
        syncAccountsIfPossible([cashAccount, bankAccount])
    }

    func createAccount(kind: FinancialAccountKind, name: String?, startingBalance: Decimal) -> String? {
        let accountType = FinancialAccountKind.compose(kind: kind, name: name)
        let normalized = accountType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty {
            return "Account name is required."
        }
        if accounts.contains(where: { ($0.accountType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }) {
            return "An account with this name already exists."
        }

        let account = FinancialAccount(context: context)
        let now = Date()
        account.id = UUID()
        account.accountType = accountType
        account.balance = NSDecimalNumber(decimal: startingBalance)
        account.openingBalance = NSDecimalNumber(decimal: startingBalance)
        account.updatedAt = now

        saveContext()
        fetchAccounts()
        syncAccountsIfPossible([account])
        return nil
    }

    func updateAccount(_ account: FinancialAccount, kind: FinancialAccountKind, name: String?) -> String? {
        let accountType = FinancialAccountKind.compose(kind: kind, name: name)
        let normalized = accountType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty {
            return "Account name is required."
        }
        if accounts.contains(where: { $0.objectID != account.objectID && ($0.accountType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }) {
            return "An account with this name already exists."
        }

        account.accountType = accountType
        account.updatedAt = Date()
        saveContext()
        fetchAccounts()
        syncAccountsIfPossible([account])
        return nil
    }
    
    func updateBalance(account: FinancialAccount, newBalance: Decimal) {
        let currentBalance = account.balance?.decimalValue ?? 0
        let delta = newBalance - currentBalance
        guard delta != 0 else { return }

        let transaction = AccountTransaction(context: context)
        transaction.id = UUID()
        transaction.transactionType = delta >= 0 ? AccountTransactionType.deposit.rawValue : AccountTransactionType.withdrawal.rawValue
        transaction.amount = NSDecimalNumber(decimal: delta >= 0 ? delta : -delta)
        transaction.date = Date()
        transaction.note = "Manual balance adjustment"
        transaction.createdAt = Date()
        transaction.updatedAt = transaction.createdAt
        transaction.account = account

        account.balance = NSDecimalNumber(decimal: newBalance)
        account.updatedAt = Date()
        saveContext()
        fetchAccounts()
        syncAccountsIfPossible([account])

        Task { @MainActor in
            guard let dealerId = CloudSyncEnvironment.currentDealerId else { return }
            await CloudSyncManager.shared?.upsertAccountTransaction(transaction, dealerId: dealerId)
        }
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }

    private func syncAccountsIfPossible(_ accounts: [FinancialAccount]) {
        Task { @MainActor in
            guard let dealerId = CloudSyncEnvironment.currentDealerId else { return }
            for account in accounts {
                await CloudSyncManager.shared?.upsertFinancialAccount(account, dealerId: dealerId)
            }
        }
    }
}
