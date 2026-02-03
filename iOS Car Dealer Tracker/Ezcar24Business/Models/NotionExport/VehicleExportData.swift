import Foundation

struct VehicleExportData {
    let id: UUID
    let make: String
    let model: String
    let year: Int
    let vin: String?
    let purchasePrice: Decimal
    let purchaseDate: Date
    let daysInInventory: Int
    let agingBucket: String
    let totalExpenses: Decimal
    let holdingCostAccumulated: Decimal
    let dailyHoldingCost: Decimal
    let totalCost: Decimal
    let askingPrice: Decimal?
    let profitEstimate: Decimal?
    let roiPercent: Decimal?
    let status: String
    let salePrice: Decimal?
    let saleDate: Date?
    let actualProfit: Decimal?
}

extension VehicleExportData {
    init(from vehicle: Vehicle, holdingCostCalculator: HoldingCostCalculator) {
        self.id = vehicle.id ?? UUID()
        self.make = vehicle.make ?? ""
        self.model = vehicle.model ?? ""
        self.year = Int(vehicle.year)
        self.vin = vehicle.vin
        self.purchasePrice = vehicle.purchasePrice?.decimalValue ?? 0
        self.purchaseDate = vehicle.purchaseDate ?? Date()
        self.status = vehicle.status ?? "owned"
        self.salePrice = vehicle.salePrice?.decimalValue
        self.saleDate = vehicle.saleDate
        self.askingPrice = vehicle.askingPrice?.decimalValue
        
        let purchaseDate = vehicle.purchaseDate ?? Date()
        let referenceDate = vehicle.saleDate ?? Date()
        self.daysInInventory = Calendar.current.dateComponents([.day], from: purchaseDate, to: referenceDate).day ?? 0
        
        self.agingBucket = Self.calculateAgingBucket(days: daysInInventory)
        
        let expenses = vehicle.expenses?.allObjects as? [Expense] ?? []
        self.totalExpenses = expenses
            .filter { $0.deletedAt == nil }
            .reduce(Decimal(0)) { $0 + ($1.amount?.decimalValue ?? 0) }
        
        self.holdingCostAccumulated = holdingCostCalculator.calculateHoldingCost(for: vehicle)
        if daysInInventory > 0 {
            self.dailyHoldingCost = holdingCostAccumulated / Decimal(daysInInventory)
        } else {
            self.dailyHoldingCost = 0
        }
        self.totalCost = purchasePrice + totalExpenses + holdingCostAccumulated
        
        if let askingPrice = self.askingPrice {
            self.profitEstimate = askingPrice - totalCost
            if totalCost > 0 {
                self.roiPercent = ((askingPrice - totalCost) / totalCost) * 100
            } else {
                self.roiPercent = nil
            }
        } else {
            self.profitEstimate = nil
            self.roiPercent = nil
        }
        
        if let salePrice = self.salePrice {
            self.actualProfit = salePrice - totalCost
        } else {
            self.actualProfit = nil
        }
    }
    
    private static func calculateAgingBucket(days: Int) -> String {
        switch days {
        case 0...30:
            return "0-30"
        case 31...60:
            return "31-60"
        case 61...90:
            return "61-90"
        default:
            return "90+"
        }
    }
}
