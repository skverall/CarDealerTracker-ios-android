import SwiftUI

extension FinancialAccountKind {
    var iconName: String {
        switch self {
        case .cash: return "banknote.fill"
        case .bank: return "building.columns.fill"
        case .creditCard: return "creditcard.fill"
        case .other: return "wallet.pass.fill"
        }
    }

    var color: Color {
        switch self {
        case .cash: return .green
        case .bank: return .blue
        case .creditCard: return .purple
        case .other: return .gray
        }
    }
}
