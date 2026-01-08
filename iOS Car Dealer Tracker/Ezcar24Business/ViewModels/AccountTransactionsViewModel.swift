import Foundation
import CoreData
import Combine

final class AccountTransactionsViewModel: ObservableObject {
    @Published var transactions: [AccountTransaction] = []

    private let account: FinancialAccount
    private let context: NSManagedObjectContext

    var onAccountUpdated: (() -> Void)?

    init(account: FinancialAccount, context: NSManagedObjectContext) {
        self.account = account
        self.context = context
        fetchTransactions()
        observeContextChanges()
    }

    func fetchTransactions() {
        let request: NSFetchRequest<AccountTransaction> = AccountTransaction.fetchRequest()
        request.predicate = NSPredicate(format: "account == %@", account)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AccountTransaction.date, ascending: false)]

        do {
            transactions = try context.fetch(request)
        } catch {
            print("Failed to fetch account transactions: \(error)")
            transactions = []
        }
    }

    func addTransaction(type: AccountTransactionType, amount: Decimal, date: Date, note: String?) {
        let transaction = AccountTransaction(context: context)
        transaction.id = UUID()
        transaction.transactionType = type.rawValue
        transaction.amount = NSDecimalNumber(decimal: amount)
        transaction.date = date
        transaction.note = note
        transaction.createdAt = Date()
        transaction.updatedAt = transaction.createdAt
        transaction.account = account

        updateBalance(for: type, amount: amount)

        saveContext()
        fetchTransactions()
        onAccountUpdated?()

        Task { @MainActor in
            guard let dealerId = CloudSyncEnvironment.currentDealerId else { return }
            await CloudSyncManager.shared?.upsertAccountTransaction(transaction, dealerId: dealerId)
            await CloudSyncManager.shared?.upsertFinancialAccount(account, dealerId: dealerId)
        }
    }

    @MainActor
    func deleteTransaction(_ transaction: AccountTransaction) {
        let type = transaction.transactionTypeEnum
        let amount = transaction.amount?.decimalValue ?? 0
        let transactionId = transaction.id

        reverseBalance(for: type, amount: amount)

        context.delete(transaction)
        saveContext()
        fetchTransactions()
        onAccountUpdated?()

        if let dealerId = CloudSyncEnvironment.currentDealerId, let id = transactionId {
            Task {
                await CloudSyncManager.shared?.deleteAccountTransaction(id: id, dealerId: dealerId)
                await CloudSyncManager.shared?.upsertFinancialAccount(account, dealerId: dealerId)
            }
        }
    }

    private func updateBalance(for type: AccountTransactionType, amount: Decimal) {
        let currentBalance = account.balance?.decimalValue ?? 0
        switch type {
        case .deposit:
            account.balance = NSDecimalNumber(decimal: currentBalance + amount)
        case .withdrawal:
            account.balance = NSDecimalNumber(decimal: currentBalance - amount)
        }
        account.updatedAt = Date()
    }

    private func reverseBalance(for type: AccountTransactionType, amount: Decimal) {
        let currentBalance = account.balance?.decimalValue ?? 0
        switch type {
        case .deposit:
            account.balance = NSDecimalNumber(decimal: currentBalance - amount)
        case .withdrawal:
            account.balance = NSDecimalNumber(decimal: currentBalance + amount)
        }
        account.updatedAt = Date()
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            context.rollback()
            print("Failed to save account transaction: \(error)")
        }
    }

    private func observeContextChanges() {
        NotificationCenter.default
            .publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
            .sink { [weak self] notification in
                guard let self, let info = notification.userInfo else { return }
                if Self.shouldRefresh(userInfo: info) {
                    DispatchQueue.main.async {
                        self.fetchTransactions()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    private static func shouldRefresh(userInfo: [AnyHashable: Any]) -> Bool {
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]
        for key in keys {
            guard let objects = userInfo[key] as? Set<NSManagedObject> else { continue }
            if objects.contains(where: { $0 is AccountTransaction }) {
                return true
            }
        }
        return false
    }
}
