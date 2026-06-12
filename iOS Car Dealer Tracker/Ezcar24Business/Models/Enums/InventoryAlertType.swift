import Foundation

enum InventoryAlertType: String, CaseIterable {
    case aging = "aging"
    case highHoldingCost = "high_holding_cost"
    case lowROI = "low_roi"
    case longDaysInInventory = "long_days_in_inventory"
    case priceDrop = "price_drop"
    case staleInventory = "stale_inventory"

    var displayName: String {
        switch self {
        case .aging:
            return "Aging Alert".localizedStringFallback
        case .highHoldingCost:
            return "High Holding Cost".localizedStringFallback
        case .lowROI:
            return "Low ROI".localizedStringFallback
        case .longDaysInInventory:
            return "Long Time in Inventory".localizedStringFallback
        case .priceDrop:
            return "Price Drop Suggested".localizedStringFallback
        case .staleInventory:
            return "Stale Inventory".localizedStringFallback
        }
    }

    var iconName: String {
        switch self {
        case .aging:
            return "calendar.badge.clock"
        case .highHoldingCost:
            return "dollarsign.circle.fill"
        case .lowROI:
            return "chart.line.downtrend.xyaxis"
        case .longDaysInInventory:
            return "clock.badge.exclamationmark"
        case .priceDrop:
            return "arrow.down.circle.fill"
        case .staleInventory:
            return "exclamationmark.triangle.fill"
        }
    }
}
