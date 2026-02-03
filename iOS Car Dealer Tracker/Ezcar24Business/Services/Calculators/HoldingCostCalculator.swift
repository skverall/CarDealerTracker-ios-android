import Foundation

class HoldingCostCalculator {
    
    private let settings: HoldingCostSettings?
    private static let eligibleStatuses: Set<String> = [
        "in_transit",
        "on_sale",
        "available",
        "reserved",
        "under_service",
        "owned",
        "sold"
    ]
    
    init(settings: HoldingCostSettings? = nil) {
        self.settings = settings
    }
    
    func calculateHoldingCost(for vehicle: Vehicle) -> Decimal {
        guard let settings = settings else { return 0 }
        guard Self.isHoldingCostEligible(vehicle: vehicle) else { return 0 }
        
        let expenses = vehicle.expenses?.allObjects as? [Expense] ?? []
        return Self.calculateAccumulatedHoldingCost(
            vehicle: vehicle,
            settings: settings,
            allExpenses: expenses
        )
    }
    
    func calculateHoldingCost(for vehicle: Vehicle, asOfDate: Date) -> Decimal {
        guard let settings = settings, settings.isEnabled else {
            return 0
        }
        
        guard Self.isHoldingCostEligible(vehicle: vehicle) else {
            return 0
        }
        
        let purchasePrice = vehicle.purchasePrice?.decimalValue ?? 0
        let expenses = vehicle.expenses?.allObjects as? [Expense] ?? []
        let baseExpenses = Self.getHoldingCostBaseExpenses(allExpenses: expenses)
        let expensesTotal = baseExpenses.reduce(Decimal(0)) { $0 + ($1.amount?.decimalValue ?? 0) }
        
        let capitalTiedUp = purchasePrice + expensesTotal
        let daysInInventory = Self.calculateDaysInInventory(vehicle: vehicle, asOfDate: asOfDate)
        
        let annualRate = settings.annualRatePercent?.decimalValue ?? 15.0
        let dailyRate = Self.calculateDailyRate(annualRatePercent: annualRate)
        
        return Decimal(daysInInventory) * dailyRate * capitalTiedUp
    }

    static func calculateDailyRate(annualRatePercent: Decimal) -> Decimal {
        guard annualRatePercent > 0 else { return 0 }
        return annualRatePercent / 365.0 / 100.0
    }
    
    static func calculateDaysInInventory(
        vehicle: Vehicle,
        asOfDate: Date = Date()
    ) -> Int {
        let purchaseDate = vehicle.purchaseDate ?? asOfDate
        let endDate = vehicle.saleDate ?? asOfDate
        let days = Calendar.current.dateComponents([.day], from: purchaseDate, to: endDate).day ?? 0
        return max(0, days)
    }
    
    static func getImprovementExpenses(allExpenses: [Expense]) -> [Expense] {
        allExpenses.filter { $0.deletedAt == nil && $0.categoryTypeEnum == .improvement }
    }
    
    static func getHoldingCostBaseExpenses(allExpenses: [Expense]) -> [Expense] {
        allExpenses.filter { $0.deletedAt == nil && $0.categoryTypeEnum != .holdingCost }
    }
    
    static func calculateDailyHoldingCost(
        vehicle: Vehicle,
        settings: HoldingCostSettings,
        improvementExpenses: [Expense]
    ) -> Decimal {
        guard settings.isEnabled else { return 0 }
        guard isHoldingCostEligible(vehicle: vehicle) else { return 0 }
        
        let purchasePrice = vehicle.purchasePrice?.decimalValue ?? 0
        let expensesTotal = improvementExpenses.reduce(Decimal(0)) { $0 + ($1.amount?.decimalValue ?? 0) }
        let capitalTiedUp = purchasePrice + expensesTotal
        
        let annualRate = settings.annualRatePercent?.decimalValue ?? 15.0
        let dailyRate = calculateDailyRate(annualRatePercent: annualRate)
        
        return capitalTiedUp * dailyRate
    }
    
    static func calculateAccumulatedHoldingCost(
        vehicle: Vehicle,
        settings: HoldingCostSettings,
        allExpenses: [Expense]
    ) -> Decimal {
        guard settings.isEnabled else { return 0 }
        guard isHoldingCostEligible(vehicle: vehicle) else { return 0 }
        
        let baseExpenses = getHoldingCostBaseExpenses(allExpenses: allExpenses)
        let dailyCost = calculateDailyHoldingCost(
            vehicle: vehicle,
            settings: settings,
            improvementExpenses: baseExpenses
        )
        
        let daysInInventory = calculateDaysInInventory(vehicle: vehicle)
        return Decimal(daysInInventory) * dailyCost
    }
    
    static func isHoldingCostEligible(vehicle: Vehicle) -> Bool {
        guard let status = vehicle.status, !status.isEmpty else { return true }
        return eligibleStatuses.contains(status)
    }
}
