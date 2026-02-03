import Foundation
import CoreData

class InventoryMetricsCalculator {
    
    private static let displayScale = 2
    
    private static let thresholdAging60 = 60
    private static let thresholdAging90 = 90
    private static let thresholdLowROI: Decimal = 10
    private static let thresholdHighHoldingCostPercent: Decimal = 15
    
    static func getAgingBucket(daysInInventory: Int) -> AgingBucket {
        return AgingBucket.fromDays(daysInInventory)
    }
    
    static func calculateHealthScore(
        vehicles: [Vehicle],
        stats: [UUID: VehicleInventoryStats]
    ) -> Int {
        guard !vehicles.isEmpty else {
            return 100
        }
        
        var totalScore = 0
        
        for vehicle in vehicles {
            guard let vehicleStats = stats[vehicle.id ?? UUID()] else {
                totalScore += 100
                continue
            }
            
            var vehicleScore = 100
            
            let agingBucket = AgingBucket.fromDays(Int(vehicleStats.daysInInventory))
            switch agingBucket {
            case .aging:
                vehicleScore -= 10
            case .stale:
                vehicleScore -= 25
            case .critical:
                vehicleScore -= 40
            default:
                break
            }
            
            if let roi = vehicleStats.roiPercent?.decimalValue {
                if roi < 0 {
                    vehicleScore -= 30
                } else if roi < 10 {
                    vehicleScore -= 15
                } else if roi < 20 {
                    vehicleScore -= 5
                } else {
                    vehicleScore += 5
                }
            }
            
            let holdingCostPercentage = (vehicleStats.holdingCostAccumulated?.decimalValue ?? 0) /
                (vehicleStats.totalCost?.decimalValue ?? 1) * 100
            
            if holdingCostPercentage > 20 {
                vehicleScore -= 20
            } else if holdingCostPercentage > 10 {
                vehicleScore -= 10
            }
            
            totalScore += max(0, min(100, vehicleScore))
        }
        
        return totalScore / vehicles.count
    }
    
    static func calculateTurnoverRatio(
        averageDaysInInventory: Int
    ) -> Double {
        guard averageDaysInInventory > 0 else {
            return 0.0
        }
        return Double(365) / Double(averageDaysInInventory)
    }
    
    static func calculateAgingDistribution(
        stats: [VehicleInventoryStats]
    ) -> [AgingBucket: Int] {
        var distribution: [AgingBucket: Int] = [:]
        
        for stat in stats {
            let bucket = AgingBucket.fromDays(Int(stat.daysInInventory))
            distribution[bucket, default: 0] += 1
        }
        
        return distribution
    }
    
    static func shouldGenerateAlert(
        vehicle: Vehicle,
        stats: VehicleInventoryStats
    ) -> InventoryAlertType? {
        let daysInInventory = Int(stats.daysInInventory)
        
        if daysInInventory >= thresholdAging90 {
            return .longDaysInInventory
        }
        
        if daysInInventory >= thresholdAging60 {
            return .aging
        }
        
        if let roi = stats.roiPercent?.decimalValue, roi < thresholdLowROI {
            return .lowROI
        }
        
        let holdingCostPercentage = (stats.holdingCostAccumulated?.decimalValue ?? 0) /
            (stats.totalCost?.decimalValue ?? 1) * 100
        
        if holdingCostPercentage > thresholdHighHoldingCostPercent {
            return .highHoldingCost
        }
        
        if shouldRecommendPriceReduction(stats: stats, vehicle: vehicle) {
            return .priceDrop
        }
        
        return nil
    }
    
    static func calculateInventoryStats(
        vehicle: Vehicle,
        expenses: [Expense],
        settings: HoldingCostSettings,
        context: NSManagedObjectContext
    ) -> VehicleInventoryStats {
        let daysInInventory = HoldingCostCalculator.calculateDaysInInventory(vehicle: vehicle)
        let agingBucket = getAgingBucket(daysInInventory: daysInInventory)
        
        let holdingCostAccumulated = HoldingCostCalculator.calculateAccumulatedHoldingCost(
            vehicle: vehicle,
            settings: settings,
            allExpenses: expenses
        )
        
        let totalCost = VehicleFinancialsCalculator.calculateTotalCost(
            vehicle: vehicle,
            expenses: expenses,
            holdingCost: holdingCostAccumulated
        )
        
        let roiPercent: NSDecimalNumber? = vehicle.salePrice.flatMap { salePrice in
            let roi = VehicleFinancialsCalculator.calculateROI(
                salePrice: salePrice.decimalValue,
                totalCost: totalCost
            )
            return roi.map { NSDecimalNumber(decimal: $0) }
        }
        
        let profitEstimate: NSDecimalNumber? = vehicle.askingPrice.flatMap { askingPrice in
            let profit = VehicleFinancialsCalculator.calculateProfitEstimate(
                askingPrice: askingPrice.decimalValue,
                totalCost: totalCost
            )
            return profit.map { NSDecimalNumber(decimal: $0) }
        }
        
        let now = Date()
        
        let stats = VehicleInventoryStats(context: context)
        stats.id = UUID()
        stats.vehicleId = vehicle.id
        stats.daysInInventory = Int32(daysInInventory)
        stats.agingBucket = agingBucket.rawValue
        stats.totalCost = NSDecimalNumber(decimal: totalCost)
        stats.holdingCostAccumulated = NSDecimalNumber(decimal: holdingCostAccumulated)
        stats.roiPercent = roiPercent
        stats.profitEstimate = profitEstimate
        stats.lastCalculatedAt = now
        stats.createdAt = now
        stats.updatedAt = now
        
        return stats
    }
    
    static func generateInventoryAlerts(
        stats: VehicleInventoryStats,
        vehicle: Vehicle,
        context: NSManagedObjectContext
    ) -> [InventoryAlert] {
        var alerts: [InventoryAlert] = []
        let now = Date()
        
        let daysInInventory = Int(stats.daysInInventory)
        
        if daysInInventory >= thresholdAging90 {
            let alert = InventoryAlert(context: context)
            alert.id = UUID()
            alert.vehicleId = vehicle.id
            alert.alertType = InventoryAlertType.longDaysInInventory.rawValue
            alert.severity = "high"
            alert.message = "Vehicle has been in inventory for \(daysInInventory) days. Consider aggressive pricing."
            alert.isRead = false
            alert.createdAt = now
            alert.dismissedAt = nil
            alerts.append(alert)
        } else if daysInInventory >= thresholdAging60 {
            let alert = InventoryAlert(context: context)
            alert.id = UUID()
            alert.vehicleId = vehicle.id
            alert.alertType = InventoryAlertType.aging.rawValue
            alert.severity = "medium"
            alert.message = "Vehicle has been in inventory for \(daysInInventory) days. Review pricing strategy."
            alert.isRead = false
            alert.createdAt = now
            alert.dismissedAt = nil
            alerts.append(alert)
        }
        
        if let roi = stats.roiPercent?.decimalValue, roi < thresholdLowROI {
            let alert = InventoryAlert(context: context)
            alert.id = UUID()
            alert.vehicleId = vehicle.id
            alert.alertType = InventoryAlertType.lowROI.rawValue
            alert.severity = "high"
            alert.message = String(format: "Projected ROI is %.1f%%. Consider cost reduction or price increase.", NSDecimalNumber(decimal: roi).doubleValue)
            alert.isRead = false
            alert.createdAt = now
            alert.dismissedAt = nil
            alerts.append(alert)
        }
        
        let holdingCostPercentage = (stats.holdingCostAccumulated?.decimalValue ?? 0) /
            (stats.totalCost?.decimalValue ?? 1) * 100
        
        if holdingCostPercentage > thresholdHighHoldingCostPercent {
            let alert = InventoryAlert(context: context)
            alert.id = UUID()
            alert.vehicleId = vehicle.id
            alert.alertType = InventoryAlertType.highHoldingCost.rawValue
            alert.severity = "medium"
            alert.message = String(format: "Holding cost is %.1f%% of total cost. Consider faster turnover.", NSDecimalNumber(decimal: holdingCostPercentage).doubleValue)
            alert.isRead = false
            alert.createdAt = now
            alert.dismissedAt = nil
            alerts.append(alert)
        }
        
        if shouldRecommendPriceReduction(stats: stats, vehicle: vehicle) {
            let alert = InventoryAlert(context: context)
            alert.id = UUID()
            alert.vehicleId = vehicle.id
            alert.alertType = InventoryAlertType.priceDrop.rawValue
            alert.severity = "medium"
            alert.message = "Based on aging and market conditions, consider a price reduction to accelerate sale."
            alert.isRead = false
            alert.createdAt = now
            alert.dismissedAt = nil
            alerts.append(alert)
        }
        
        return alerts
    }
    
    static func calculateAverageDaysInInventory(
        stats: [VehicleInventoryStats]
    ) -> Int {
        guard !stats.isEmpty else {
            return 0
        }
        let totalDays = stats.reduce(0) { $0 + Int($1.daysInInventory) }
        return totalDays / stats.count
    }
    
    static func calculateTotalHoldingCost(
        stats: [VehicleInventoryStats]
    ) -> Decimal {
        return stats
            .reduce(Decimal(0)) { $0 + ($1.holdingCostAccumulated?.decimalValue ?? 0) }
            .rounded(to: displayScale)
    }
    
    static func calculateTotalInventoryValue(
        stats: [VehicleInventoryStats]
    ) -> Decimal {
        return stats
            .reduce(Decimal(0)) { $0 + ($1.totalCost?.decimalValue ?? 0) }
            .rounded(to: displayScale)
    }
    
    private static func shouldRecommendPriceReduction(
        stats: VehicleInventoryStats,
        vehicle: Vehicle
    ) -> Bool {
        guard vehicle.saleDate == nil else {
            return false
        }
        
        let isAging = stats.daysInInventory >= thresholdAging60
        
        let hasLowROI = stats.roiPercent.flatMap { roi in
            roi.decimalValue < 15
        } ?? false
        
        let holdingCostPercentage = (stats.holdingCostAccumulated?.decimalValue ?? 0) /
            (stats.totalCost?.decimalValue ?? 1) * 100
        let hasHighHoldingCost = holdingCostPercentage > 12
        
        return isAging && (hasLowROI || hasHighHoldingCost)
    }
}

private extension Decimal {
    func rounded(to scale: Int) -> Decimal {
        var result = Decimal()
        var localCopy = self
        NSDecimalRound(&result, &localCopy, scale, .plain)
        return result
    }
}
