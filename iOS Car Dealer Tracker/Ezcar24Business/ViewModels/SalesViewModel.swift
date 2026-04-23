//
//  SalesViewModel.swift
//  Ezcar24Business
//
//  Created by Shokhabbos Makhmudov on 20/11/2025.
//

import Foundation
import CoreData
import Combine
import SwiftUI

@MainActor
class SalesViewModel: ObservableObject {
    // MARK: - Enums
    enum SaleTypeFilter {
        case all
        case vehicles
        case parts
    }
    
    // MARK: - Published Properties
    @Published var unifiedSales: [UnifiedSaleItem] = []
    @Published var filter: SaleTypeFilter = .all {
        didSet {
            applyFilters()
        }
    }
    @Published var searchText: String = "" {
        didSet {
            applyFilters()
        }
    }

    // MARK: - Private Properties
    private let viewContext: NSManagedObjectContext
    private var allVehicleSales: [Sale] = []
    private var allPartSales: [PartSale] = []
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        fetchAll()
        observeContextChanges()
    }

    // MARK: - Fetching
    func fetchAll() {
        fetchVehicleSales()
        fetchPartSales()
        applyFilters()
    }
    
    private func fetchVehicleSales() {
        let request: NSFetchRequest<Sale> = Sale.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Sale.date, ascending: false)]
        request.predicate = NSPredicate(format: "deletedAt == nil")
        
        do {
            allVehicleSales = try viewContext.fetch(request)
        } catch {
            print("Failed to fetch vehicle sales: \(error)")
            allVehicleSales = []
        }
    }
    
    private func fetchPartSales() {
        let request: NSFetchRequest<PartSale> = PartSale.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PartSale.date, ascending: false)]
        request.predicate = NSPredicate(format: "deletedAt == nil")
        
        do {
            allPartSales = try viewContext.fetch(request)
        } catch {
            print("Failed to fetch part sales: \(error)")
            allPartSales = []
        }
    }
    
    // MARK: - Filtering & Processing
    private func applyFilters() {
        var items: [UnifiedSaleItem] = []
        
        // 1. Process Vehicle Sales
        if filter == .all || filter == .vehicles {
            let settings = fetchHoldingCostSettings()
            let filteredVehicles = allVehicleSales.filter { sale in
                if searchText.isEmpty { return true }
                let query = searchText.lowercased()
                
                let matchesVehicle = (sale.vehicle?.make?.lowercased().contains(query) ?? false) ||
                                     (sale.vehicle?.model?.lowercased().contains(query) ?? false)
                let matchesBuyer = sale.buyerName?.lowercased().contains(query) ?? false
                
                return matchesVehicle || matchesBuyer
            }
            items.append(contentsOf: filteredVehicles.map { sale in
                let holdingCost = holdingCostForSale(sale, settings: settings)
                return UnifiedSaleItem(vehicleSale: sale, holdingCost: holdingCost)
            })
        }
        
        // 2. Process Part Sales
        if filter == .all || filter == .parts {
            let filteredParts = allPartSales.filter { sale in
                if searchText.isEmpty { return true }
                let query = searchText.lowercased()
                
                let matchesBuyer = sale.buyerName?.lowercased().contains(query) ?? false
                let matchesPhone = sale.buyerPhone?.lowercased().contains(query) ?? false
                
                // Search in line items
                let lineItems = sale.activeLineItemsArray
                let matchesPart = lineItems.contains { item in
                    item.part?.displayName.lowercased().contains(query) == true
                }
                
                return matchesBuyer || matchesPhone || matchesPart
            }
            items.append(contentsOf: filteredParts.map { UnifiedSaleItem(partSale: $0) })
        }
        
        // 3. Sort Combined List (Newest first)
        items.sort { $0.date > $1.date }
        
        self.unifiedSales = items
    }

    // MARK: - Actions
    
    @MainActor
    func deleteItem(_ item: UnifiedSaleItem) {
        switch item.type {
        case .vehicle(let sale):
            deleteVehicleSale(sale)
        case .part(let sale):
            deletePartSale(sale)
        }
    }

    @MainActor
    private func deleteVehicleSale(_ sale: Sale) {
        // Revert vehicle status if linked
        if let vehicle = sale.vehicle {
            vehicle.status = "available"
            vehicle.salePrice = nil
            vehicle.saleDate = nil
            vehicle.buyerName = nil
            vehicle.buyerPhone = nil
            vehicle.paymentMethod = nil
            vehicle.updatedAt = Date()
            
            if let dealerId = CloudSyncEnvironment.currentDealerId {
                Task {
                    await CloudSyncManager.shared?.upsertVehicle(vehicle, dealerId: dealerId)
                }
            }
        }
        
        if let account = sale.account {
            let currentBalance = account.balance?.decimalValue ?? 0
            account.balance = NSDecimalNumber(decimal: currentBalance - sale.accountDepositAmount)
            account.updatedAt = Date()
            if let dealerId = CloudSyncEnvironment.currentDealerId {
                Task {
                    await CloudSyncManager.shared?.upsertFinancialAccount(account, dealerId: dealerId)
                }
            }
        }

        let saleId = sale.id
        viewContext.delete(sale)
        
        saveAndSync(saleId: saleId, isPartSale: false)
    }
    
    @MainActor
    private func deletePartSale(_ sale: PartSale) {
        let lineItems = sale.activeLineItemsArray
        var updatedBatches: [PartBatch] = []
        var updatedPartsById: [UUID: Part] = [:]
        let now = Date()

        // Restore stock
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

        // Revert account balance
        if let account = sale.account {
            let amount = sale.amount?.decimalValue ?? PartSaleItem(sale: sale).totalAmount
            let currentBalance = account.balance?.decimalValue ?? 0
            account.balance = NSDecimalNumber(decimal: currentBalance - amount)
            account.updatedAt = now
            
            if let dealerId = CloudSyncEnvironment.currentDealerId {
                Task {
                    await CloudSyncManager.shared?.upsertFinancialAccount(account, dealerId: dealerId)
                }
            }
        }

        let saleId = sale.id
        viewContext.delete(sale)

        do {
            try viewContext.save()
            fetchAll()

            if let dealerId = CloudSyncEnvironment.currentDealerId {
                Task {
                    for batch in updatedBatches {
                        await CloudSyncManager.shared?.upsertPartBatch(batch, dealerId: dealerId)
                    }
                    for part in updatedPartsById.values {
                        await CloudSyncManager.shared?.upsertPart(part, dealerId: dealerId)
                    }
                    if let saleId {
                        await CloudSyncManager.shared?.deletePartSale(id: saleId, dealerId: dealerId)
                    }
                }
            }
        } catch {
            print("Failed to delete part sale: \(error)")
        }
    }

    private func holdingCostForSale(_ sale: Sale, settings: HoldingCostSettings?) -> Decimal {
        guard let vehicle = sale.vehicle else { return 0 }
        guard let settings, settings.isEnabled else { return 0 }
        let calculator = HoldingCostCalculator(settings: settings)
        let date = sale.date ?? vehicle.saleDate ?? Date()
        return calculator.calculateHoldingCost(for: vehicle, asOfDate: date)
    }

    private func fetchHoldingCostSettings() -> HoldingCostSettings? {
        let request = HoldingCostSettings.fetchRequest()
        request.fetchLimit = 1
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \HoldingCostSettings.updatedAt, ascending: false),
            NSSortDescriptor(keyPath: \HoldingCostSettings.createdAt, ascending: false)
        ]
        if let dealerId = CloudSyncEnvironment.currentDealerId {
            request.predicate = NSPredicate(format: "dealerId == %@", dealerId as CVarArg)
        }
        if let settings = try? viewContext.fetch(request).first {
            if settings.dealerId == nil, let dealerId = CloudSyncEnvironment.currentDealerId {
                settings.dealerId = dealerId
                settings.updatedAt = Date()
                try? viewContext.save()
            }
            return settings
        }

        let settings = HoldingCostSettings(context: viewContext)
        settings.id = UUID()
        settings.dealerId = CloudSyncEnvironment.currentDealerId
        settings.isEnabled = false
        settings.annualRatePercent = NSDecimalNumber(decimal: 15.0)
        settings.dailyRatePercent = NSDecimalNumber(decimal: 0.0411)
        settings.createdAt = Date()
        settings.updatedAt = Date()
        try? viewContext.save()
        return settings
    }

    private func saveAndSync(saleId: UUID?, isPartSale: Bool) {
        do {
            try viewContext.save()
            fetchAll()
            
            if let id = saleId, let dealerId = CloudSyncEnvironment.currentDealerId {
                Task {
                    if isPartSale {
                        await CloudSyncManager.shared?.deletePartSale(id: id, dealerId: dealerId)
                    } else {
                        await CloudSyncManager.shared?.deleteSale(id: id, dealerId: dealerId)
                    }
                }
            }
        } catch {
            print("Failed to save deletion context: \(error)")
        }
    }

    // MARK: - Observer
    private func observeContextChanges() {
        NotificationCenter.default
            .publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)
            .sink { [weak self] notification in
                guard let self, let info = notification.userInfo else { return }
                if Self.shouldRefresh(userInfo: info) {
                    DispatchQueue.main.async {
                        self.fetchAll()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private static func shouldRefresh(userInfo: [AnyHashable: Any]) -> Bool {
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]
        for key in keys {
            guard let objects = userInfo[key] as? Set<NSManagedObject> else { continue }
            if objects.contains(where: {
                $0 is Sale || $0 is Vehicle || $0 is Expense ||
                $0 is PartSale || $0 is PartSaleLineItem || $0 is PartBatch ||
                $0 is HoldingCostSettings
            }) {
                return true
            }
        }
        return false
    }
}

// MARK: - Unified Model
struct UnifiedSaleItem: Identifiable {
    enum SaleType {
        case vehicle(Sale)
        case part(PartSale)
    }
    
    let id: NSManagedObjectID
    let type: SaleType
    
    // Common Properties
    let title: String
    let subtitle: String?
    let buyerName: String
    let date: Date
    let amount: Decimal
    let cost: Decimal
    let profit: Decimal
    
    init(vehicleSale: Sale, holdingCost: Decimal = 0) {
        self.id = vehicleSale.objectID
        self.type = .vehicle(vehicleSale)
        self.date = vehicleSale.date ?? Date()
        self.buyerName = vehicleSale.buyerName ?? "Unknown Buyer"
        
        // Title
        if let vehicle = vehicleSale.vehicle {
            let make = vehicle.make ?? ""
            let model = vehicle.model ?? ""
            let combined = "\(make) \(model)".trimmingCharacters(in: .whitespaces)
            self.title = combined.isEmpty ? "Vehicle" : combined
            // Optional: trim name if needed
            self.subtitle = vehicle.vin
        } else {
            self.title = "Vehicle Removed"
            self.subtitle = nil
        }
        
        let price = vehicleSale.amount?.decimalValue ?? 0
        self.amount = price
        
        let purchasePrice = vehicleSale.vehicle?.purchasePrice?.decimalValue ?? 0
        let expenses = ((vehicleSale.vehicle?.expenses as? Set<Expense>) ?? [])
            .filter { $0.deletedAt == nil }
            .reduce(Decimal(0)) { $0 + ($1.amount?.decimalValue ?? 0) }
        self.cost = purchasePrice + expenses + holdingCost
        
        // Include VAT refund in profit
        let vatRefund = vehicleSale.vatRefundAmount?.decimalValue ?? 0
        self.profit = price - self.cost + vatRefund
    }
    
    @MainActor init(partSale: PartSale) {
        self.id = partSale.objectID
        self.type = .part(partSale)
        self.date = partSale.date ?? Date()
        self.buyerName = partSale.buyerName ?? "Walk-in"
        
        // Wrap PartSale logic
        let wrappedPartSale = PartSaleItem(sale: partSale)
        self.title = "parts_sale_title".localizedString
        self.subtitle = wrappedPartSale.itemsSummary
        
        self.amount = wrappedPartSale.totalAmount
        self.cost = wrappedPartSale.totalCost
        self.profit = wrappedPartSale.profit
    }
}

// Define SaleItem alias for backward compatibility if needed, or remove if fully replaced.
typealias SaleItem = UnifiedSaleItem
