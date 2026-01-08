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
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FinancialAccount.accountType, ascending: true)]
        
        do {
            accounts = try context.fetch(request)
        } catch {
            print("Error fetching accounts: \(error)")
            accounts = []
        }
    }
    
    func createDefaultAccounts() {
        let cashAccount = FinancialAccount(context: context)
        cashAccount.id = UUID()
        cashAccount.accountType = "Cash"
        cashAccount.balance = NSDecimalNumber(value: 0)
        cashAccount.updatedAt = Date()

        let bankAccount = FinancialAccount(context: context)
        bankAccount.id = UUID()
        bankAccount.accountType = "Bank"
        bankAccount.balance = NSDecimalNumber(value: 0)
        bankAccount.updatedAt = Date()

        saveContext()
        fetchAccounts()
        syncAccountsIfPossible([cashAccount, bankAccount])
    }
    
    func updateBalance(account: FinancialAccount, newBalance: Decimal) {
        account.balance = newBalance as NSDecimalNumber
        account.updatedAt = Date()
        saveContext()
        fetchAccounts()
        syncAccountsIfPossible([account])
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
