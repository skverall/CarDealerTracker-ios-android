import Foundation

enum ExpenseCategoryType: String, CaseIterable {
    case holdingCost = "holding_cost"
    case improvement = "improvement"
    case operational = "operational"

    var displayName: String {
        switch self {
        case .holdingCost:
            return "Holding Cost"
        case .improvement:
            return "Improvement"
        case .operational:
            return "Operational"
        }
    }

    var iconName: String {
        switch self {
        case .holdingCost:
            return "clock.arrow.circlepath"
        case .improvement:
            return "wrench.fill"
        case .operational:
            return "building.columns.fill"
        }
    }
}
