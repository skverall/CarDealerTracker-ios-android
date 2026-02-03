import Foundation

enum LeadStage: String, CaseIterable {
    case new = "new"
    case contacted = "contacted"
    case qualified = "qualified"
    case negotiation = "negotiation"
    case offer = "offer"
    case testDrive = "test_drive"
    case closedWon = "closed_won"
    case closedLost = "closed_lost"

    var displayName: String {
        switch self {
        case .new:
            return "New"
        case .contacted:
            return "Contacted"
        case .qualified:
            return "Qualified"
        case .negotiation:
            return "Negotiation"
        case .offer:
            return "Offer"
        case .testDrive:
            return "Test Drive"
        case .closedWon:
            return "Closed Won"
        case .closedLost:
            return "Closed Lost"
        }
    }

    var isClosed: Bool {
        self == .closedWon || self == .closedLost
    }
}
