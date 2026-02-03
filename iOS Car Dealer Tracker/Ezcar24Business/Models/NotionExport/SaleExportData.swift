import Foundation

struct SaleExportData {
    let id: UUID
    let vehicleMake: String
    let vehicleModel: String
    let vehicleYear: Int
    let salePrice: Decimal
    let saleDate: Date
    let buyerName: String?
    let totalCost: Decimal
    let profit: Decimal
    let roiPercent: Decimal
    let daysToSell: Int
}

extension SaleExportData {
    init(from vehicle: Vehicle, holdingCostCalculator: HoldingCostCalculator) {
        self.id = vehicle.id ?? UUID()
        self.vehicleMake = vehicle.make ?? ""
        self.vehicleModel = vehicle.model ?? ""
        self.vehicleYear = Int(vehicle.year)
        self.salePrice = vehicle.salePrice?.decimalValue ?? 0
        self.saleDate = vehicle.saleDate ?? Date()
        self.buyerName = vehicle.buyerName
        
        let expenses = vehicle.expenses?.allObjects as? [Expense] ?? []
        let totalExpenses = expenses
            .filter { $0.deletedAt == nil }
            .reduce(Decimal(0)) { $0 + ($1.amount?.decimalValue ?? 0) }
        
        let purchasePrice = vehicle.purchasePrice?.decimalValue ?? 0
        let holdingCost = holdingCostCalculator.calculateHoldingCost(for: vehicle)
        self.totalCost = purchasePrice + totalExpenses + holdingCost
        
        self.profit = salePrice - totalCost
        
        if totalCost > 0 {
            self.roiPercent = ((profit / totalCost) * 100)
        } else {
            self.roiPercent = 0
        }
        
        if let purchaseDate = vehicle.purchaseDate,
           let saleDate = vehicle.saleDate {
            self.daysToSell = Calendar.current.dateComponents([.day], from: purchaseDate, to: saleDate).day ?? 0
        } else {
            self.daysToSell = 0
        }
    }
}