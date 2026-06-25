//
//  VehicleViewModel.swift
//  Ezcar24Business
//
//  ViewModel for vehicle management
//

import Foundation
import CoreData
import Combine

@MainActor
class VehicleViewModel: ObservableObject {
    @Published var displayMode: DisplayMode = .inventory
    @Published var vehicles: [Vehicle] = []
    @Published private var vehicleExpenseSummaries: [NSManagedObjectID: VehicleExpenseSummary] = [:]
    @Published var selectedStatus: String = "all"
    @Published var searchText: String = ""
    @Published var sortOption: SortOption = .dateDesc

    // MARK: - Dashboard Stats
    @Published var totalVehiclesCount: Int = 0
    @Published var onSaleCount: Int = 0
    @Published var soldCount: Int = 0
    @Published var inGarageCount: Int = 0
    @Published var inTransitCount: Int = 0
    @Published var underServiceCount: Int = 0

    enum DisplayMode: String, CaseIterable, Identifiable {
        case inventory = "Inventory"
        case sold = "Sold"
        
        var id: String { self.rawValue }
        
        @MainActor var title: String {
            switch self {
            case .inventory: return "inventory".localizedString
            case .sold: return "sold".localizedString
            }
        }
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case dateDesc = "Newest First"
        case dateAsc = "Oldest First"
        case priceDesc = "Price: High to Low"
        case priceAsc = "Price: Low to High"
        case daysDesc = "Days: High to Low"
        case daysAsc = "Days: Low to High"
        
        var id: String { self.rawValue }
        
        @MainActor var title: String {
            switch self {
            case .dateDesc: return "newest_first".localizedString
            case .dateAsc: return "oldest_first".localizedString
            case .priceDesc: return "price_high_to_low".localizedString
            case .priceAsc: return "price_low_to_high".localizedString
            case .daysDesc: return "oldest_inventory".localizedString
            case .daysAsc: return "newest_inventory".localizedString
            }
        }
    }

    private let context: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()
    private var pendingRefreshWorkItem: DispatchWorkItem?
    private var vehicleFetchGeneration = 0
    private var statsFetchGeneration = 0


    init(context: NSManagedObjectContext) {
        self.context = context
        fetchVehicles()
        fetchStats()
        observeContextChanges()
        
        // Debounce search
        $searchText
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.fetchVehicles()
            }
            .store(in: &cancellables)
            
        // React to sort changes
        $sortOption
            .dropFirst()
            .sink { [weak self] _ in
                // Small delay to allow state update before fetch
                DispatchQueue.main.async {
                    self?.fetchVehicles()
                }
            }
            .store(in: &cancellables)

        // React to status filter changes
        $selectedStatus
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.fetchVehicles()
                }
            }
            .store(in: &cancellables)
            
        // React to display mode changes
        $displayMode
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.fetchVehicles()
                }
            }
            .store(in: &cancellables)
    }


    func fetchVehicles() {
        let request: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
        
        // Sorting
        switch sortOption {
        case .dateDesc:
            if displayMode == .sold {
                // Show newly-sold vehicles first (status flips update `updatedAt`, while `createdAt` may be old)
                request.sortDescriptors = [
                    NSSortDescriptor(keyPath: \Vehicle.updatedAt, ascending: false),
                    NSSortDescriptor(keyPath: \Vehicle.createdAt, ascending: false)
                ]
            } else {
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Vehicle.createdAt, ascending: false)]
            }
        case .dateAsc:
            if displayMode == .sold {
                request.sortDescriptors = [
                    NSSortDescriptor(keyPath: \Vehicle.updatedAt, ascending: true),
                    NSSortDescriptor(keyPath: \Vehicle.createdAt, ascending: true)
                ]
            } else {
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Vehicle.createdAt, ascending: true)]
            }
        case .priceDesc:
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Vehicle.purchasePrice, ascending: false)]
        case .priceAsc:
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Vehicle.purchasePrice, ascending: true)]
        case .daysDesc:
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Vehicle.purchaseDate, ascending: true)]
        case .daysAsc:
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Vehicle.purchaseDate, ascending: false)]
        }

        // Filtering
        var predicates: [NSPredicate] = []
        
        // Display Mode Filter (Inventory vs Sold)
        if displayMode == .inventory {
            // Exclude soft-deleted vehicles
            predicates.append(NSPredicate(format: "deletedAt == nil"))
            
            predicates.append(NSPredicate(format: "status != %@", "sold"))
            
            // Status Filter (Only applies in Inventory mode)
            if selectedStatus != "all" {
                if selectedStatus == "on_sale" {
                    predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [
                        NSPredicate(format: "status == %@", "on_sale"),
                        NSPredicate(format: "status == %@", "available")
                    ]))
                } else if selectedStatus == "reserved" {
                     // "In Garage" now includes Reserved + Under Service
                    predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [
                        NSPredicate(format: "status == %@", "reserved"),
                        NSPredicate(format: "status == %@", "under_service")
                    ]))
                } else {
                    predicates.append(NSPredicate(format: "status == %@", selectedStatus))
                }
            }
        } else {
            // Sold Mode
            predicates.append(NSPredicate(format: "status == %@", "sold"))
            // Exclude soft-deleted vehicles here too
            predicates.append(NSPredicate(format: "deletedAt == nil"))
        }
        
        // Search Filter
        if !searchText.isEmpty {
            let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "make CONTAINS[cd] %@", search),
                NSPredicate(format: "model CONTAINS[cd] %@", search),
                NSPredicate(format: "vin CONTAINS[cd] %@", search),
                NSPredicate(format: "inventoryID CONTAINS[cd] %@", search)
            ])
            predicates.append(searchPredicate)
        }
        
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        do {
            let fetchedVehicles = try context.fetch(request)
            let expenseSummaries = fetchVehicleExpenseSummaries()
            vehicleExpenseSummaries = expenseSummaries
            scheduleVehiclesPublish(fetchedVehicles)
        } catch {
            print("Error fetching vehicles: \(error)")
        }
    }

    func fetchStats() {
        let fetchedStats = calculateStats()
        scheduleStatsPublish(fetchedStats)
    }

    private func calculateStats() -> VehicleStats {
        let basePredicate = NSPredicate(format: "deletedAt == nil")
        
        // Helper to count with status
        func count(status: String) -> Int {
            let req: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
            req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                basePredicate,
                NSPredicate(format: "status == %@", status)
            ])
            return (try? context.count(for: req)) ?? 0
        }
        
        // Total (Active inventory, excluding sold)
        let totalReq: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
        totalReq.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            basePredicate,
            NSPredicate(format: "status != %@", "sold")
        ])
        let totalVehiclesCount = (try? context.count(for: totalReq)) ?? 0
        
        // Sold (All time)
        let soldCount = count(status: "sold")
        
        // In Garage (Owned + Service)
        let garageReq: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
        garageReq.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
             basePredicate,
             NSCompoundPredicate(orPredicateWithSubpredicates: [
                 NSPredicate(format: "status == %@", "reserved"),
                 NSPredicate(format: "status == %@", "under_service")
             ])
        ])
        let inGarageCount = (try? context.count(for: garageReq)) ?? 0
        
        // In Transit
        let inTransitCount = count(status: "in_transit")
        
        // Service (kept for internal tracking if needed, but not distinct in dashboard anymore)
        let underServiceCount = count(status: "under_service")
        
        // On Sale (Combine on_sale and available)
        let onSaleReq: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
        onSaleReq.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            basePredicate,
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "status == %@", "on_sale"),
                NSPredicate(format: "status == %@", "available")
            ])
        ])
        let onSaleCount = (try? context.count(for: onSaleReq)) ?? 0

        return VehicleStats(
            totalVehiclesCount: totalVehiclesCount,
            onSaleCount: onSaleCount,
            soldCount: soldCount,
            inGarageCount: inGarageCount,
            inTransitCount: inTransitCount,
            underServiceCount: underServiceCount
        )
    }

    // Optional imageData will be saved to disk (not Core Data) to avoid bloat and keep UI fast.
    @discardableResult
    func addVehicle(
        vin: String,
        inventoryID: String,
        make: String,
        model: String,
        year: Int32,
        purchasePrice: Decimal,
        purchaseDate: Date,
        status: String,
        notes: String,
        account: FinancialAccount? = nil,
        imageData: Data? = nil,
        salePrice: Decimal? = nil,
        saleDate: Date? = nil,
        mileage: Int32 = 0
    ) -> Vehicle {
        let vehicle = Vehicle(context: context)
        vehicle.id = UUID()
        vehicle.vin = vin
        vehicle.inventoryID = inventoryID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        vehicle.make = make
        vehicle.model = model
        vehicle.year = year
        vehicle.purchasePrice = NSDecimalNumber(decimal: purchasePrice)
        vehicle.purchaseDate = purchaseDate
        vehicle.status = status
        vehicle.notes = notes
        vehicle.createdAt = Date()
        vehicle.updatedAt = vehicle.createdAt
        if let salePrice { vehicle.salePrice = NSDecimalNumber(decimal: salePrice) }
        if let saleDate { vehicle.saleDate = saleDate }
        vehicle.mileage = mileage

        // Deduct purchase amount from selected account (if provided)
        if let account {
            vehicle.purchaseAccountId = account.id
            let currentBalance = account.balance?.decimalValue ?? 0
            account.balance = NSDecimalNumber(decimal: currentBalance - purchasePrice)
            account.updatedAt = Date()
        }
        
        if status == "sold", let salePrice, salePrice > 0 {
            let sale = Sale(context: context)
            sale.id = UUID()
            sale.vehicle = vehicle
            sale.amount = NSDecimalNumber(decimal: salePrice)
            sale.date = saleDate ?? Date()
            sale.createdAt = Date()
            sale.updatedAt = sale.createdAt
            sale.account = account
            
            if let account {
                let currentBalance = account.balance?.decimalValue ?? 0
                account.balance = NSDecimalNumber(decimal: currentBalance + salePrice)
                account.updatedAt = Date()
            }
        }

        // Persist Core Data first
        saveContext()

        // Save image (if any) in background associated with the newly created id
        if let data = imageData, let id = vehicle.id {
            let dealerId = CloudSyncEnvironment.currentDealerId
            ImageStore.shared.save(imageData: data, for: id, dealerId: dealerId)
        }

        fetchVehicles()
        return vehicle
    }

    @discardableResult
    func deleteVehicle(_ vehicle: Vehicle) -> UUID? {
        let id = vehicle.id
        context.delete(vehicle)
        saveContext()
        fetchVehicles()
        return id
    }


    func duplicateVehicle(_ original: Vehicle) {
        let new = Vehicle(context: context)
        new.id = UUID()
        new.vin = "" // avoid VIN duplicates
        new.inventoryID = original.inventoryID
        new.make = original.make
        new.model = original.model
        new.year = original.year
        new.purchasePrice = original.purchasePrice
        new.purchaseDate = original.purchaseDate
        new.status = original.status
        new.notes = original.notes
        new.createdAt = Date()
        new.updatedAt = new.createdAt
        // Do not copy sale details by default
        new.salePrice = nil
        new.saleDate = nil
        saveContext()
        // Copy photo if exists
        let dealerId = CloudSyncEnvironment.currentDealerId
        if let oldID = original.id, let newID = new.id, ImageStore.shared.hasImage(id: oldID, dealerId: dealerId) {
            let url = ImageStore.shared.imageURL(for: oldID, dealerId: dealerId)
            if let data = try? Data(contentsOf: url) {
                ImageStore.shared.save(imageData: data, for: newID, dealerId: dealerId)
            }
        }
        fetchVehicles()
    }

    func totalCost(for vehicle: Vehicle) -> Decimal {
        let purchasePrice = vehicle.purchasePrice?.decimalValue ?? 0
        return purchasePrice + expenseTotal(for: vehicle)
    }

    func expenseCount(for vehicle: Vehicle) -> Int {
        vehicleExpenseSummaries[vehicle.objectID]?.count ?? 0
    }

    func expenseTotal(for vehicle: Vehicle) -> Decimal {
        vehicleExpenseSummaries[vehicle.objectID]?.total ?? 0
    }

    private func observeContextChanges() {
        NotificationCenter.default
            .publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
            .sink { [weak self] notification in
                guard let self, let userInfo = notification.userInfo else { return }
                if Self.shouldRefreshVehicles(userInfo: userInfo) {
                    self.scheduleRefresh()
                }
            }
            .store(in: &cancellables)
    }

    private static func shouldRefreshVehicles(userInfo: [AnyHashable: Any]) -> Bool {
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]
        for key in keys {
            guard let objects = userInfo[key] as? Set<NSManagedObject> else { continue }
            if objects.contains(where: { $0 is Vehicle || $0 is Expense || $0 is HoldingCostSettings }) {
                return true
            }
        }
        return false
    }

    private func scheduleRefresh() {
        pendingRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.fetchVehicles()
            self?.fetchStats()
        }
        pendingRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func fetchVehicleExpenseSummaries() -> [NSManagedObjectID: VehicleExpenseSummary] {
        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        request.predicate = NSPredicate(format: "deletedAt == nil AND vehicle != nil")

        do {
            let expenses = try context.fetch(request)
            var summaries: [NSManagedObjectID: VehicleExpenseSummary] = [:]
            summaries.reserveCapacity(expenses.count)
            for expense in expenses {
                guard let vehicle = expense.vehicle else { continue }
                let current = summaries[vehicle.objectID] ?? .zero
                summaries[vehicle.objectID] = VehicleExpenseSummary(
                    count: current.count + 1,
                    total: current.total + (expense.amount?.decimalValue ?? 0)
                )
            }
            return summaries
        } catch {
            print("Error fetching vehicle expense summaries: \(error)")
            return vehicleExpenseSummaries
        }
    }

    private func scheduleVehiclesPublish(_ fetchedVehicles: [Vehicle]) {
        vehicleFetchGeneration += 1
        let generation = vehicleFetchGeneration

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, generation == self.vehicleFetchGeneration else { return }
            self.vehicles = fetchedVehicles
            InventoryStatsManager.shared.recalculateStats(for: fetchedVehicles)
        }
    }

    private func scheduleStatsPublish(_ stats: VehicleStats) {
        statsFetchGeneration += 1
        let generation = statsFetchGeneration

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, generation == self.statsFetchGeneration else { return }
            self.totalVehiclesCount = stats.totalVehiclesCount
            self.onSaleCount = stats.onSaleCount
            self.soldCount = stats.soldCount
            self.inGarageCount = stats.inGarageCount
            self.inTransitCount = stats.inTransitCount
            self.underServiceCount = stats.underServiceCount
        }
    }


    private func saveContext() {
        do {
            try context.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }

    private struct VehicleStats {
        let totalVehiclesCount: Int
        let onSaleCount: Int
        let soldCount: Int
        let inGarageCount: Int
        let inTransitCount: Int
        let underServiceCount: Int
    }

    private struct VehicleExpenseSummary {
        let count: Int
        let total: Decimal

        static let zero = VehicleExpenseSummary(count: 0, total: 0)
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension Vehicle {
    var inventoryIDValue: String? {
        let trimmed = inventoryID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var vinValue: String? {
        let trimmed = vin?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var displayNameWithInventory: String {
        let normalizedMake = make?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = [normalizedMake, normalizedModel].filter { !$0.isEmpty }.joined(separator: " ")

        if let inventoryIDValue {
            if !name.isEmpty {
                return String(format: "%@ • ID %@".localizedStringFallback, name, inventoryIDValue)
            }
            return String(format: "ID %@".localizedStringFallback, inventoryIDValue)
        }

        if !name.isEmpty {
            return name
        }

        if let vinValue {
            return vinValue
        }

        return "vehicle".localizedStringFallback
    }

    var inventoryOrVINLabel: String? {
        if let inventoryIDValue {
            return String(format: "ID: %@".localizedStringFallback, inventoryIDValue)
        }
        if let vinValue {
            return String(format: "VIN: %@".localizedStringFallback, vinValue)
        }
        return nil
    }

    func matchesVehicleSearchQuery(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return true }

        let candidates = [
            make,
            model,
            vinValue,
            inventoryIDValue,
            year > 0 ? String(year) : nil
        ]

        return candidates
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(normalizedQuery) }
    }
}
