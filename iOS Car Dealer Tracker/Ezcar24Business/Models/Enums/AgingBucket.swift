import Foundation

enum AgingBucket: String, CaseIterable {
    case fresh = "fresh"
    case normal = "normal"
    case aging = "aging"
    case stale = "stale"
    case critical = "critical"

    var displayName: String {
        switch self {
        case .fresh:
            return "Fresh"
        case .normal:
            return "Normal"
        case .aging:
            return "Aging"
        case .stale:
            return "Stale"
        case .critical:
            return "Critical"
        }
    }

    var colorName: String {
        switch self {
        case .fresh:
            return "green"
        case .normal:
            return "blue"
        case .aging:
            return "yellow"
        case .stale:
            return "orange"
        case .critical:
            return "red"
        }
    }

    var maxDays: Int {
        switch self {
        case .fresh:
            return 7
        case .normal:
            return 30
        case .aging:
            return 60
        case .stale:
            return 90
        case .critical:
            return Int.max
        }
    }

    static func fromDays(_ days: Int) -> AgingBucket {
        switch days {
        case 0...7:
            return .fresh
        case 8...30:
            return .normal
        case 31...60:
            return .aging
        case 61...90:
            return .stale
        default:
            return .critical
        }
    }
}
