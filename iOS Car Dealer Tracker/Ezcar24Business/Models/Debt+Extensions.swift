import Foundation
import SwiftUI

enum DebtDirection: String, CaseIterable, Identifiable {
    case owedToMe = "owed_to_me"
    case iOwe = "i_owe"

    var id: String { rawValue }

    @MainActor
    var title: String {
        switch self {
        case .owedToMe: return "owed_to_me".localizedString
        case .iOwe: return "i_owe".localizedString
        }
    }

    var badgeTitle: String {
        switch self {
        case .owedToMe: return "Receivable"
        case .iOwe: return "Payable"
        }
    }

    var color: Color {
        switch self {
        case .owedToMe: return ColorTheme.success
        case .iOwe: return ColorTheme.warning
        }
    }
}

extension Debt {
    var directionEnum: DebtDirection {
        get { DebtDirection(rawValue: direction ?? DebtDirection.owedToMe.rawValue) ?? .owedToMe }
        set { direction = newValue.rawValue }
    }

    var totalAmountDecimal: Decimal {
        amount?.decimalValue ?? 0
    }

    var paymentsArray: [DebtPayment] {
        let set = payments as? Set<DebtPayment> ?? []
        return set.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    var totalPaid: Decimal {
        paymentsArray.reduce(Decimal(0)) { sum, payment in
            sum + (payment.amount?.decimalValue ?? 0)
        }
    }

    var outstandingAmount: Decimal {
        let remaining = totalAmountDecimal - totalPaid
        return max(remaining, 0)
    }

    var isPaid: Bool {
        outstandingAmount <= Decimal(string: "0.01") ?? 0.01
    }

    var lastPaymentDate: Date? {
        paymentsArray.last?.date
    }
}
