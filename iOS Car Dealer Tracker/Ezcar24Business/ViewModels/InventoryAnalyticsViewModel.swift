//
//  InventoryAnalyticsViewModel.swift
//  Ezcar24Business
//
//  ViewModel for inventory analytics dashboard
//

import Foundation
import CoreData
import Combine
import SwiftUI

@MainActor
class InventoryAnalyticsViewModel: ObservableObject {
    @Published var healthScore: Int = 100
    @Published var totalHoldingCost: Decimal = 0
    @Published var averageDaysInInventory: Int = 0
    @Published var turnoverRatio: Double = 0
    @Published var agingDistribution: [AgingBucket: Int] = [:]
    @Published var alerts: [InventoryAlertItem] = []
    @Published var vehicles: [Vehicle] = []
    @Published var vehicleStats: [UUID: VehicleInventoryStats] = [:]
    @Published var isLoading: Bool = false
    @Published var selectedFilter: FilterOption = .all
    @Published var sortOption: SortOption = .daysDesc
    
    enum FilterOption: String, CaseIterable, Identifiable {
        case all = "all"
        case burning = "burning"
        case highHoldingCost = "high_holding_cost"
        case lowROI = "low_roi"
        case aging = "aging"
        
        var id: String { rawValue }
        
        @MainActor var displayName: String {
            switch self {
            case .all:
                return "all_vehicles".localizedString
            case .burning:
                return "burning_inventory".localizedString
            case .highHoldingCost:
                return "high_holding_cost".localizedString
            case .lowROI:
                return "low_roi".localizedString
            case .aging:
                return "aging".localizedString
            }
        }
    }
    
    enum SortOption: String, CaseIterable, Identifiable {
        case daysDesc = "days_desc"
        case daysAsc = "days_asc"
        case holdingCostDesc = "holding_cost_desc"
        case roiAsc = "roi_asc"
        
        var id: String { rawValue }
        
        @MainActor var displayName: String {
            switch self {
            case .daysDesc:
                return "oldest_first".localizedString
            case .daysAsc:
                return "newest_first".localizedString
            case .holdingCostDesc:
                return "highest_holding_cost".localizedString
            case .roiAsc:
                return "lowest_roi".localizedString
            }
        }
    }
    
    private let context: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()
    private var inventoryStatsManager: InventoryStatsManager
    
    var burningThreshold: Int {
        NotificationPreference.inventoryStaleThreshold
    }
    
    init(context: NSManagedObjectContext? = nil) {
        self.context = context ?? PersistenceController.shared.container.viewContext
        self.inventoryStatsManager = InventoryStatsManager.shared
        
        setupBindings()
        loadData()
    }
    
    private func setupBindings() {
        inventoryStatsManager.$healthScore
            .receive(on: DispatchQueue.main)
            .assign(to: \.healthScore, on: self)
            .store(in: &cancellables)
        
        inventoryStatsManager.$totalHoldingCost
            .receive(on: DispatchQueue.main)
            .assign(to: \.totalHoldingCost, on: self)
            .store(in: &cancellables)
        
        inventoryStatsManager.$agingDistribution
            .receive(on: DispatchQueue.main)
            .assign(to: \.agingDistribution, on: self)
            .store(in: &cancellables)
        
        inventoryStatsManager.$alerts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] alerts in
                self?.updateAlertItems(from: alerts)
            }
            .store(in: &cancellables)
    }
    
    func loadData() {
        isLoading = true
        
        fetchVehicles()
        recalculateStats()
        
        averageDaysInInventory = inventoryStatsManager.calculateAverageDaysInInventory(
            stats: Array(vehicleStats.values)
        )
        turnoverRatio = inventoryStatsManager.calculateTurnoverRatio()
        
        isLoading = false
    }
    
    func refreshData() {
        loadData()
    }
    
    func dismissAlert(_ alertItem: InventoryAlertItem) {
        guard let alert = alertItem.alert else { return }
        
        inventoryStatsManager.dismissAlert(alert)
        alerts.removeAll { $0.id == alertItem.id }
    }
    
    func getVehicle(for alertItem: InventoryAlertItem) -> Vehicle? {
        return vehicles.first { $0.id == alertItem.vehicleId }
    }
    
    func getStats(for vehicleId: UUID) -> VehicleInventoryStats? {
        return vehicleStats[vehicleId]
    }
    
    var filteredVehicles: [Vehicle] {
        let filtered: [Vehicle]
        
        switch selectedFilter {
        case .all:
            filtered = vehicles
        case .burning:
            filtered = vehicles.filter { vehicle in
                guard let vehicleId = vehicle.id,
                      let stats = vehicleStats[vehicleId] else { return false }
                return Int(stats.daysInInventory) >= burningThreshold
            }
        case .highHoldingCost:
            filtered = vehicles.filter { vehicle in
                guard let vehicleId = vehicle.id,
                      let stats = vehicleStats[vehicleId],
                      let holdingCost = stats.holdingCostAccumulated?.decimalValue,
                      let totalCost = stats.totalCost?.decimalValue,
                      totalCost > 0 else { return false }
                return (holdingCost / totalCost) > 0.15
            }
        case .lowROI:
            filtered = vehicles.filter { vehicle in
                guard let vehicleId = vehicle.id,
                      let stats = vehicleStats[vehicleId],
                      let roi = stats.roiPercent?.decimalValue else { return false }
                return roi < 10
            }
        case .aging:
            filtered = vehicles.filter { vehicle in
                guard let vehicleId = vehicle.id,
                      let stats = vehicleStats[vehicleId] else { return false }
                return stats.daysInInventory >= 60
            }
        }
        
        return sortVehicles(filtered)
    }
    
    var burningVehicles: [Vehicle] {
        vehicles.filter { vehicle in
            guard let vehicleId = vehicle.id,
                  let stats = vehicleStats[vehicleId] else { return false }
            return Int(stats.daysInInventory) >= burningThreshold
        }
    }
    
    var totalVehicles: Int {
        vehicles.count
    }
    
    var totalInventoryValue: Decimal {
        inventoryStatsManager.calculateTotalInventoryValue()
    }
    
    private func fetchVehicles() {
        let request: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
        request.predicate = NSPredicate(format: "status != %@ AND deletedAt == nil", "sold")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Vehicle.purchaseDate, ascending: false)]
        
        do {
            vehicles = try context.fetch(request)
        } catch {
            print("Error fetching vehicles: \(error)")
            vehicles = []
        }
    }
    
    private func recalculateStats() {
        inventoryStatsManager.recalculateStats(for: vehicles)
        inventoryStatsManager.generateAlerts(for: vehicles)
        
        vehicleStats = inventoryStatsManager.getAllStats()
    }
    
    private func updateAlertItems(from alerts: [InventoryAlert]) {
        self.alerts = alerts.map { alert in
            InventoryAlertItem(
                id: alert.id ?? UUID(),
                alert: alert,
                vehicleId: alert.vehicleId
            )
        }
    }
    
    private func sortVehicles(_ vehicles: [Vehicle]) -> [Vehicle] {
        switch sortOption {
        case .daysDesc:
            return vehicles.sorted { v1, v2 in
                let days1 = vehicleStats[v1.id ?? UUID()]?.daysInInventory ?? 0
                let days2 = vehicleStats[v2.id ?? UUID()]?.daysInInventory ?? 0
                return days1 > days2
            }
        case .daysAsc:
            return vehicles.sorted { v1, v2 in
                let days1 = vehicleStats[v1.id ?? UUID()]?.daysInInventory ?? 0
                let days2 = vehicleStats[v2.id ?? UUID()]?.daysInInventory ?? 0
                return days1 < days2
            }
        case .holdingCostDesc:
            return vehicles.sorted { v1, v2 in
                let cost1 = vehicleStats[v1.id ?? UUID()]?.holdingCostAccumulated?.decimalValue ?? 0
                let cost2 = vehicleStats[v2.id ?? UUID()]?.holdingCostAccumulated?.decimalValue ?? 0
                return cost1 > cost2
            }
        case .roiAsc:
            return vehicles.sorted { v1, v2 in
                let roi1 = vehicleStats[v1.id ?? UUID()]?.roiPercent?.decimalValue ?? 0
                let roi2 = vehicleStats[v2.id ?? UUID()]?.roiPercent?.decimalValue ?? 0
                return roi1 < roi2
            }
        }
    }

    
    // MARK: - Insights & Helpers
    
    var healthStatusTitle: String {
        switch healthScore {
        case 90...100: return "Excellent Health"
        case 75..<90: return "Good Health"
        case 60..<75: return "Fair Health"
        default: return "Needs Attention"
        }
    }
    
    var healthStatusMessage: String {
        switch healthScore {
        case 90...100: return "Your inventory efficiency is top tier."
        case 75..<90: return "Inventory flow is healthy."
        case 60..<75: return "Consider discounting older units."
        default: return "High holding costs detected."
        }
    }
    
    var healthColor: ColorTheme.Key {
        switch healthScore {
        case 90...100: return .success
        case 75..<90: return .warning
        case 60..<75: return .orange
        default: return .danger
        }
    }
    
    func getTurnoverStatus() -> (String, ColorTheme.Key) {
        if averageDaysInInventory < 30 { return ("Fast", .success) }
        if averageDaysInInventory < 60 { return ("Normal", .warning) }
        return ("Slow", .danger)
    }
}

extension ColorTheme {
    enum Key {
        case success, warning, danger, orange
        
        var color: SwiftUI.Color {
            switch self {
            case .success: return ColorTheme.success
            case .warning: return ColorTheme.warning
            case .danger: return ColorTheme.danger
            case .orange: return Color.orange
            }
        }
    }
}

struct InventoryAlertItem: Identifiable {
    let id: UUID
    let alert: InventoryAlert?
    let vehicleId: UUID?
}
