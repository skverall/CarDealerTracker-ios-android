import Foundation

class VehicleFinancialsCalculator {
    
    private static let intermediateScale = 4
    private static let displayScale = 2
    private static let percentageScale = 2
    
    static func calculateTotalCost(
        vehicle: Vehicle,
        expenses: [Expense],
        holdingCost: Decimal
    ) -> Decimal {
        let purchasePrice = vehicle.purchasePrice?.decimalValue ?? 0
        
        let expensesTotal = expenses
            .filter { $0.deletedAt == nil }
            .reduce(Decimal(0)) { $0 + ($1.amount?.decimalValue ?? 0) }
        
        return (purchasePrice + expensesTotal + holdingCost).rounded(to: displayScale)
    }
    
    static func calculateTotalExpensesOnly(
        vehicle: Vehicle,
        expenses: [Expense]
    ) -> Decimal {
        let expensesTotal = expenses
            .filter { $0.deletedAt == nil }
            .reduce(Decimal(0)) { $0 + ($1.amount?.decimalValue ?? 0) }
        
        return ((vehicle.purchasePrice?.decimalValue ?? 0) + expensesTotal).rounded(to: displayScale)
    }
    
    static func calculateROI(
        salePrice: Decimal,
        totalCost: Decimal
    ) -> Decimal? {
        guard totalCost != 0 else {
            return nil
        }
        
        let profit = salePrice - totalCost
        return ((profit / totalCost) * 100).rounded(to: percentageScale)
    }
    
    static func calculateProfitEstimate(
        askingPrice: Decimal,
        totalCost: Decimal
    ) -> Decimal? {
        return (askingPrice - totalCost).rounded(to: displayScale)
    }
    
    static func calculateActualProfit(
        salePrice: Decimal,
        totalCost: Decimal
    ) -> Decimal {
        return (salePrice - totalCost).rounded(to: displayScale)
    }
    
    static func calculateBreakEvenPrice(
        totalCost: Decimal,
        targetROI: Decimal = 0
    ) -> Decimal {
        guard targetROI != 0 else {
            return totalCost
        }
        
        let roiMultiplier = (targetROI / 100) + 1
        return (totalCost * roiMultiplier).rounded(to: displayScale)
    }
    
    static func calculateHoldingCostPercentage(
        holdingCost: Decimal,
        totalCost: Decimal
    ) -> Decimal? {
        guard totalCost != 0 else {
            return nil
        }
        
        return ((holdingCost / totalCost) * 100).rounded(to: percentageScale)
    }
    
    static func calculateExpenseBreakdown(
        expenses: [Expense]
    ) -> [ExpenseCategoryType: Decimal] {
        return expenses
            .filter { $0.deletedAt == nil }
            .compactMap { expense -> (ExpenseCategoryType, Decimal)? in
                guard let categoryType = expense.categoryTypeEnum else { return nil }
                return (categoryType, expense.amount?.decimalValue ?? 0)
            }
            .reduce(into: [:]) { result, pair in
                result[pair.0, default: 0] += pair.1
            }
            .mapValues { $0.rounded(to: displayScale) }
    }
    
    static func calculateRecommendedAskingPrice(
        vehicle: Vehicle,
        expenses: [Expense],
        holdingCost: Decimal,
        targetROI: Decimal = 20
    ) -> Decimal {
        let totalCost = calculateTotalCost(vehicle: vehicle, expenses: expenses, holdingCost: holdingCost)
        return calculateBreakEvenPrice(totalCost: totalCost, targetROI: targetROI)
    }
    
    static func isProfitable(salePrice: Decimal, totalCost: Decimal) -> Bool {
        return salePrice > totalCost
    }
    
    static func getProfitStatus(
        salePrice: Decimal,
        totalCost: Decimal
    ) -> ProfitStatus {
        let profit = salePrice - totalCost
        let roi = calculateROI(salePrice: salePrice, totalCost: totalCost)
        
        if profit < 0 {
            return .loss
        } else if profit == 0 {
            return .breakEven
        } else if let roi = roi, roi >= 20 {
            return .highProfit
        } else {
            return .profit
        }
    }
}

enum ProfitStatus {
    case loss
    case breakEven
    case profit
    case highProfit
    
    var displayName: String {
        switch self {
        case .loss:
            return "Loss"
        case .breakEven:
            return "Break Even"
        case .profit:
            return "Profit"
        case .highProfit:
            return "High Profit"
        }
    }
    
    var colorName: String {
        switch self {
        case .loss:
            return "red"
        case .breakEven:
            return "yellow"
        case .profit:
            return "green"
        case .highProfit:
            return "blue"
        }
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
