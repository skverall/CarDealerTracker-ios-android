import Foundation
import CoreData
import Combine

@MainActor
final class PartSalesViewModel: ObservableObject {
    @Published var sales: [PartSale] = []
    @Published var saleItems: [PartSaleItem] = []
    @Published var searchText: String = ""

    private let context: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()

    init(context: NSManagedObjectContext) {
        self.context = context
        fetchSales()
        observeContextChanges()

        $searchText
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.fetchSales()
            }
            .store(in: &cancellables)
    }

    func fetchSales() {
        let request: NSFetchRequest<PartSale> = PartSale.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PartSale.date, ascending: false)]
        request.predicate = NSPredicate(format: "deletedAt == nil")

        do {
            let results = try context.fetch(request)
            let filtered = filterSales(results, searchText: searchText)
            sales = filtered
            saleItems = filtered.map { PartSaleItem(sale: $0) }
        } catch {
            print("PartSalesViewModel fetchSales error: \(error)")
        }
    }

    func deleteSale(_ sale: PartSale) {
        let lineItems = (sale.lineItems as? Set<PartSaleLineItem>) ?? []
        var updatedBatches: [PartBatch] = []
        var updatedPartsById: [UUID: Part] = [:]
        let now = Date()

        for item in lineItems {
            let qty = item.quantity?.decimalValue ?? 0
            if let batch = item.batch {
                let current = batch.quantityRemaining?.decimalValue ?? 0
                batch.quantityRemaining = NSDecimalNumber(decimal: current + qty)
                batch.updatedAt = now
                updatedBatches.append(batch)
            }
            if let part = item.part, let partId = part.id {
                part.updatedAt = now
                updatedPartsById[partId] = part
            }
        }

        let saleAccount = sale.account
        if let account = saleAccount {
            let amount = sale.amount?.decimalValue ?? PartSaleItem(sale: sale).totalAmount
            let currentBalance = account.balance?.decimalValue ?? 0
            account.balance = NSDecimalNumber(decimal: currentBalance - amount)
            account.updatedAt = now
        }

        let saleId = sale.id
        context.delete(sale)

        do {
            try context.save()
            fetchSales()

            if let dealerId = CloudSyncEnvironment.currentDealerId {
                Task {
                    for batch in updatedBatches {
                        await CloudSyncManager.shared?.upsertPartBatch(batch, dealerId: dealerId)
                    }
                    for part in updatedPartsById.values {
                        await CloudSyncManager.shared?.upsertPart(part, dealerId: dealerId)
                    }
                    if let account = saleAccount {
                        await CloudSyncManager.shared?.upsertFinancialAccount(account, dealerId: dealerId)
                    }
                    if let saleId {
                        await CloudSyncManager.shared?.deletePartSale(id: saleId, dealerId: dealerId)
                    }
                }
            }
        } catch {
            print("PartSalesViewModel deleteSale error: \(error)")
        }
    }

    private func filterSales(_ sales: [PartSale], searchText: String) -> [PartSale] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sales }
        let lower = trimmed.lowercased()

        return sales.filter { sale in
            if sale.buyerName?.lowercased().contains(lower) == true { return true }
            if sale.buyerPhone?.lowercased().contains(lower) == true { return true }
            let items = sale.lineItems as? Set<PartSaleLineItem> ?? []
            return items.contains { item in
                item.part?.name?.lowercased().contains(lower) == true
            }
        }
    }

    private func observeContextChanges() {
        NotificationCenter.default
            .publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
            .sink { [weak self] notification in
                guard let self, let info = notification.userInfo else { return }
                if Self.shouldRefresh(userInfo: info) {
                    self.fetchSales()
                }
            }
            .store(in: &cancellables)
    }

    private static func shouldRefresh(userInfo: [AnyHashable: Any]) -> Bool {
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]
        for key in keys {
            guard let objects = userInfo[key] as? Set<NSManagedObject> else { continue }
            if objects.contains(where: { $0 is PartSale || $0 is PartSaleLineItem || $0 is PartBatch }) {
                return true
            }
        }
        return false
    }
}

struct PartSaleItem: Identifiable {
    let id: NSManagedObjectID
    let sale: PartSale
    let saleDate: Date
    let buyerName: String
    let totalAmount: Decimal
    let totalCost: Decimal
    let profit: Decimal
    let itemsSummary: String

    init(sale: PartSale) {
        self.id = sale.objectID
        self.sale = sale
        self.saleDate = sale.date ?? Date()
        self.buyerName = sale.buyerName?.isEmpty == false ? sale.buyerName! : "Walk-in"

        let items = sale.lineItems as? Set<PartSaleLineItem> ?? []
        if items.isEmpty {
            self.totalAmount = sale.amount?.decimalValue ?? 0
            self.totalCost = 0
            self.profit = totalAmount - totalCost
            self.itemsSummary = ""
            return
        }

        var amount = Decimal(0)
        var cost = Decimal(0)
        var grouped: [String: Decimal] = [:]

        for item in items {
            let qty = item.quantity?.decimalValue ?? 0
            let price = item.unitPrice?.decimalValue ?? 0
            let unitCost = item.unitCost?.decimalValue ?? 0
            amount += qty * price
            cost += qty * unitCost

            let partName = item.part?.displayName ?? "Part"
            grouped[partName, default: 0] += qty
        }

        self.totalAmount = amount
        self.totalCost = cost
        self.profit = amount - cost
        self.itemsSummary = grouped
            .sorted(by: { $0.key < $1.key })
            .map { "\(Self.formatQuantity($0.value)) x \($0.key)" }
            .joined(separator: ", ")
    }

    private static func formatQuantity(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}
