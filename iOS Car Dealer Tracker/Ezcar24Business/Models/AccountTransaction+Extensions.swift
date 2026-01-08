import Foundation
import SwiftUI

enum AccountTransactionType: String, CaseIterable, Identifiable {
    case deposit
    case withdrawal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deposit: return "Deposit"
        case .withdrawal: return "Withdrawal"
        }
    }

    var color: Color {
        switch self {
        case .deposit: return ColorTheme.success
        case .withdrawal: return ColorTheme.danger
        }
    }

    var iconName: String {
        switch self {
        case .deposit: return "arrow.down.circle.fill"
        case .withdrawal: return "arrow.up.circle.fill"
        }
    }
}

extension AccountTransaction {
    var transactionTypeEnum: AccountTransactionType {
        get { AccountTransactionType(rawValue: transactionType ?? AccountTransactionType.deposit.rawValue) ?? .deposit }
        set { transactionType = newValue.rawValue }
    }

    var amountDecimal: Decimal {
        amount?.decimalValue ?? 0
    }

    var signedAmount: Decimal {
        switch transactionTypeEnum {
        case .deposit: return amountDecimal
        case .withdrawal: return -amountDecimal
        }
    }
}

extension FinancialAccount {
    var transactionsArray: [AccountTransaction] {
        let set = transactions as? Set<AccountTransaction> ?? []
        return set.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}
