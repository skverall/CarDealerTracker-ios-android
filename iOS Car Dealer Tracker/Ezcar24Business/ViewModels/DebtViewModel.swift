import Foundation
import CoreData
import Combine

final class DebtViewModel: ObservableObject {
    @Published var debts: [Debt] = []
    @Published var debtItems: [DebtItem] = []
    @Published var searchText: String = "" {
        didSet {
            fetchDebts()
        }
    }

    @Published var filter: DebtFilter = .open {
        didSet {
            fetchDebts()
        }
    }

    private let context: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()

    enum DebtFilter: String, CaseIterable, Identifiable {
        case open
        case paid
        case all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .open: return "Open"
            case .paid: return "Paid"
            case .all: return "All"
            }
        }
    }

    init(context: NSManagedObjectContext) {
        self.context = context
        fetchDebts()
        observeContextChanges()
    }

    func fetchDebts() {
        let request: NSFetchRequest<Debt> = Debt.fetchRequest()
        var predicates: [NSPredicate] = []

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let predicate = NSPredicate(
                format: "counterpartyName CONTAINS[cd] %@ OR counterpartyPhone CONTAINS[cd] %@ OR notes CONTAINS[cd] %@",
                trimmed, trimmed, trimmed
            )
            predicates.append(predicate)
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Debt.updatedAt, ascending: false),
            NSSortDescriptor(keyPath: \Debt.createdAt, ascending: false)
        ]

        do {
            let list = try context.fetch(request)
            let filteredList: [Debt]
            switch filter {
            case .open:
                filteredList = list.filter { !$0.isPaid }
            case .paid:
                filteredList = list.filter { $0.isPaid }
            case .all:
                filteredList = list
            }
            debts = filteredList
            debtItems = filteredList.map { DebtItem(debt: $0) }
        } catch {
            print("Failed to fetch debts: \(error)")
        }
    }

    private func observeContextChanges() {
        NotificationCenter.default
            .publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
            .sink { [weak self] notification in
                guard let self, let info = notification.userInfo else { return }
                if Self.shouldRefresh(userInfo: info) {
                    DispatchQueue.main.async {
                        self.fetchDebts()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private static func shouldRefresh(userInfo: [AnyHashable: Any]) -> Bool {
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]
        for key in keys {
            guard let objects = userInfo[key] as? Set<NSManagedObject> else { continue }
            if objects.contains(where: { $0 is Debt || $0 is DebtPayment }) {
                return true
            }
        }
        return false
    }

    @MainActor
    func deleteDebt(_ debt: Debt) {
        let paymentItems = debt.paymentsArray
        let debtId = debt.id
        let paymentIds = paymentItems.compactMap { $0.id }
        var accountsToSync: [NSManagedObjectID: FinancialAccount] = [:]

        for payment in paymentItems {
            adjustAccountBalanceForPaymentDeletion(payment)
            if let account = payment.account {
                accountsToSync[account.objectID] = account
            }
        }

        context.delete(debt)
        do {
            try context.save()
            fetchDebts()
            Task {
                await LocalNotificationManager.shared.refreshAll(context: context)
            }

            if let dealerId = CloudSyncEnvironment.currentDealerId {
                Task {
                    if let id = debtId {
                        await CloudSyncManager.shared?.deleteDebt(id: id, dealerId: dealerId)
                    }
                    for paymentId in paymentIds {
                        await CloudSyncManager.shared?.deleteDebtPayment(id: paymentId, dealerId: dealerId)
                    }
                    for account in accountsToSync.values {
                        await CloudSyncManager.shared?.upsertFinancialAccount(account, dealerId: dealerId)
                    }
                }
            }
        } catch {
            context.rollback()
            print("Failed to delete debt: \(error)")
        }
    }

    @MainActor
    func deletePayment(_ payment: DebtPayment) {
        guard let debt = payment.debt else { return }
        let paymentId = payment.id
        let debtId = debt.id
        let accountToSync = payment.account

        adjustAccountBalanceForPaymentDeletion(payment)

        debt.updatedAt = Date()
        context.delete(payment)
        do {
            try context.save()
            fetchDebts()
            Task {
                await LocalNotificationManager.shared.refreshAll(context: context)
            }

            if let dealerId = CloudSyncEnvironment.currentDealerId {
                Task {
                    if let id = paymentId {
                        await CloudSyncManager.shared?.deleteDebtPayment(id: id, dealerId: dealerId)
                    }
                    if debtId != nil {
                        await CloudSyncManager.shared?.upsertDebt(debt, dealerId: dealerId)
                    }
                    if let account = accountToSync {
                        await CloudSyncManager.shared?.upsertFinancialAccount(account, dealerId: dealerId)
                    }
                }
            }
        } catch {
            context.rollback()
            print("Failed to delete payment: \(error)")
        }
    }

    private func adjustAccountBalanceForPaymentDeletion(_ payment: DebtPayment) {
        guard let account = payment.account else { return }
        let amount = payment.amount?.decimalValue ?? 0
        let direction = payment.debt?.directionEnum ?? .owedToMe

        let currentBalance = account.balance?.decimalValue ?? 0
        switch direction {
        case .owedToMe:
            account.balance = NSDecimalNumber(decimal: currentBalance - amount)
        case .iOwe:
            account.balance = NSDecimalNumber(decimal: currentBalance + amount)
        }
        account.updatedAt = Date()
    }
}

struct DebtItem: Identifiable {
    let id: NSManagedObjectID
    let debt: Debt
    let name: String
    let phone: String
    let direction: DebtDirection
    let totalAmount: Decimal
    let paidAmount: Decimal
    let outstandingAmount: Decimal
    let dueDate: Date?
    let lastPaymentDate: Date?
    let isPaid: Bool
    let isOverdue: Bool

    init(debt: Debt) {
        self.id = debt.objectID
        self.debt = debt
        self.name = debt.counterpartyName ?? "Unknown"
        self.phone = debt.counterpartyPhone ?? ""
        self.direction = debt.directionEnum
        self.totalAmount = debt.totalAmountDecimal
        self.paidAmount = debt.totalPaid
        self.outstandingAmount = debt.outstandingAmount
        self.dueDate = debt.dueDate
        self.lastPaymentDate = debt.lastPaymentDate
        self.isPaid = debt.isPaid
        if let due = debt.dueDate, !debt.isPaid {
            self.isOverdue = Calendar.current.startOfDay(for: due) < Calendar.current.startOfDay(for: Date())
        } else {
            self.isOverdue = false
        }
    }
}
