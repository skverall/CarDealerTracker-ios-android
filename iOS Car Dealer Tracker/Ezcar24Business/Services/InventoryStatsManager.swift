import Foundation
import CoreData
import Combine

@MainActor
class InventoryStatsManager: ObservableObject {
    static let shared = InventoryStatsManager()
    
    @Published var healthScore: Int = 100
    @Published var totalHoldingCost: Decimal = 0
    @Published var agingDistribution: [AgingBucket: Int] = [:]
    @Published var alerts: [InventoryAlert] = []
    
    private var vehicleStats: [UUID: VehicleInventoryStats] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    private var context: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }
    
    private init() {}
    
    func recalculateStats(for vehicles: [Vehicle]) {
        var newStats: [UUID: VehicleInventoryStats] = [:]
        var totalHolding: Decimal = 0
        
        let settings = fetchHoldingCostSettings()
        
        for vehicle in vehicles {
            guard let vehicleId = vehicle.id else { continue }
            
            let expenses = fetchExpenses(for: vehicle)
            
            let stats = InventoryMetricsCalculator.calculateInventoryStats(
                vehicle: vehicle,
                expenses: expenses,
                settings: settings,
                context: context
            )
            
            newStats[vehicleId] = stats
            totalHolding += stats.holdingCostAccumulated?.decimalValue ?? 0
        }
        
        self.vehicleStats = newStats
        self.totalHoldingCost = totalHolding
        
        let statsArray = Array(newStats.values)
        self.agingDistribution = InventoryMetricsCalculator.calculateAgingDistribution(stats: statsArray)
        self.healthScore = InventoryMetricsCalculator.calculateHealthScore(
            vehicles: vehicles,
            stats: newStats
        )
    }
    
    func generateAlerts(for vehicles: [Vehicle]) {
        var newAlerts: [InventoryAlert] = []
        
        for vehicle in vehicles {
            guard let vehicleId = vehicle.id,
                  let stats = vehicleStats[vehicleId] else { continue }
            
            let vehicleAlerts = InventoryMetricsCalculator.generateInventoryAlerts(
                stats: stats,
                vehicle: vehicle,
                context: context
            )
            newAlerts.append(contentsOf: vehicleAlerts)
        }
        
        self.alerts = newAlerts.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
    
    func getStats(for vehicleId: UUID) -> VehicleInventoryStats? {
        return vehicleStats[vehicleId]
    }
    
    func getAllStats() -> [UUID: VehicleInventoryStats] {
        return vehicleStats
    }
    
    func refreshStats(for vehicle: Vehicle) {
        guard let vehicleId = vehicle.id else { return }
        
        let settings = fetchHoldingCostSettings()
        let expenses = fetchExpenses(for: vehicle)
        
        let stats = InventoryMetricsCalculator.calculateInventoryStats(
            vehicle: vehicle,
            expenses: expenses,
            settings: settings,
            context: context
        )
        
        vehicleStats[vehicleId] = stats
        
        recalculateTotals()
    }
    
    func deleteStats(for vehicleId: UUID) {
        vehicleStats.removeValue(forKey: vehicleId)
        recalculateTotals()
    }
    
    func dismissAlert(_ alert: InventoryAlert) {
        alert.dismissedAt = Date()
        alert.isRead = true
        
        do {
            try context.save()
            alerts.removeAll { $0.id == alert.id }
        } catch {
            print("Error dismissing alert: \(error)")
        }
    }
    
    func markAlertAsRead(_ alert: InventoryAlert) {
        alert.isRead = true
        
        do {
            try context.save()
        } catch {
            print("Error marking alert as read: \(error)")
        }
    }
    
    func getUnreadAlertsCount() -> Int {
        return alerts.filter { !$0.isRead }.count
    }
    
    func getAlertsBySeverity(_ severity: String) -> [InventoryAlert] {
        return alerts.filter { $0.severity == severity }
    }
    
    func getAlertsForVehicle(_ vehicleId: UUID) -> [InventoryAlert] {
        return alerts.filter { $0.vehicleId == vehicleId }
    }
    
    func calculateTurnoverRatio() -> Double {
        let averageDays = InventoryMetricsCalculator.calculateAverageDaysInInventory(
            stats: Array(vehicleStats.values)
        )
        return InventoryMetricsCalculator.calculateTurnoverRatio(averageDaysInInventory: averageDays)
    }
    
    func calculateAverageDaysInInventory(stats: [VehicleInventoryStats]) -> Int {
        InventoryMetricsCalculator.calculateAverageDaysInInventory(stats: stats)
    }
    
    func calculateTotalInventoryValue() -> Decimal {
        return InventoryMetricsCalculator.calculateTotalInventoryValue(
            stats: Array(vehicleStats.values)
        )
    }
    
    func getVehiclesByAgingBucket(_ bucket: AgingBucket) -> [UUID] {
        return vehicleStats
            .filter { _, stats in
                AgingBucket.fromDays(Int(stats.daysInInventory)) == bucket
            }
            .map { $0.key }
    }
    
    private func recalculateTotals() {
        let statsArray = Array(vehicleStats.values)
        
        totalHoldingCost = statsArray.reduce(Decimal(0)) { $0 + ($1.holdingCostAccumulated?.decimalValue ?? 0) }
        agingDistribution = InventoryMetricsCalculator.calculateAgingDistribution(stats: statsArray)
        
        let vehicles = fetchVehicles(withIds: Array(vehicleStats.keys))
        healthScore = InventoryMetricsCalculator.calculateHealthScore(
            vehicles: vehicles,
            stats: vehicleStats
        )
    }
    
    private func fetchHoldingCostSettings() -> HoldingCostSettings {
        let request = HoldingCostSettings.fetchRequest()
        
        do {
            let results = try context.fetch(request)
            return results.first ?? createDefaultHoldingCostSettings()
        } catch {
            print("Error fetching holding cost settings: \(error)")
            return createDefaultHoldingCostSettings()
        }
    }
    
    private func createDefaultHoldingCostSettings() -> HoldingCostSettings {
        let settings = HoldingCostSettings(context: context)
        settings.id = UUID()
        settings.annualRatePercent = NSDecimalNumber(decimal: 12.0)
        settings.dailyRatePercent = NSDecimalNumber(decimal: 0.0329)
        settings.isEnabled = true
        settings.createdAt = Date()
        settings.updatedAt = Date()
        
        do {
            try context.save()
        } catch {
            print("Error saving default holding cost settings: \(error)")
        }
        
        return settings
    }
    
    private func fetchExpenses(for vehicle: Vehicle) -> [Expense] {
        guard let vehicleId = vehicle.id else { return [] }
        
        let request = Expense.fetchRequest()
        request.predicate = NSPredicate(format: "vehicle.id == %@ AND deletedAt == nil", vehicleId as CVarArg)
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching expenses: \(error)")
            return []
        }
    }
    
    private func fetchVehicles(withIds ids: [UUID]) -> [Vehicle] {
        guard !ids.isEmpty else { return [] }
        
        let request = Vehicle.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", ids)
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching vehicles: \(error)")
            return []
        }
    }
}
