import Foundation
import CoreData

enum FinancialAccountKind: String, CaseIterable, Identifiable {
    case cash
    case bank
    case creditCard
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: return "Cash"
        case .bank: return "Bank"
        case .creditCard: return "Credit Card"
        case .other: return "Other"
        }
    }

    var localizedTitle: String {
        switch self {
        case .cash: return "cash".localizedStringFallback
        case .bank: return "bank".localizedStringFallback
        case .creditCard: return "credit_card".localizedStringFallback
        case .other: return "other".localizedStringFallback
        }
    }

    static let separator = " - "

    static func fromPrefix(_ value: String) -> FinancialAccountKind {
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lower {
        case "cash": return .cash
        case "bank": return .bank
        case "card", "creditcard", "credit card": return .creditCard
        default: return .other
        }
    }

    static func parse(_ accountType: String?) -> (kind: FinancialAccountKind, name: String?) {
        let raw = accountType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty {
            return (.other, nil)
        }
        if let range = raw.range(of: separator) {
            let prefix = String(raw[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let name = String(raw[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let kind = fromPrefix(prefix)
            return (kind, name.isEmpty ? nil : name)
        }
        let kind = fromPrefix(raw)
        if kind == .other {
            return (kind, raw)
        }
        return (kind, nil)
    }

    static func compose(kind: FinancialAccountKind, name: String?) -> String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedName.isEmpty {
            return kind.title
        }
        if kind == .other {
            return trimmedName
        }
        return "\(kind.title)\(separator)\(trimmedName)"
    }
}

extension FinancialAccount {
    var kind: FinancialAccountKind {
        FinancialAccountKind.parse(accountType).kind
    }

    var accountName: String? {
        FinancialAccountKind.parse(accountType).name
    }

    var displayTitle: String {
        let parsed = FinancialAccountKind.parse(accountType)
        if let name = parsed.name, !name.isEmpty {
            if parsed.kind == .other {
                return name
            }
            return "\(parsed.kind.localizedTitle)\(FinancialAccountKind.separator)\(name)"
        }
        if parsed.kind == .other {
            let raw = accountType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? "account".localizedStringFallback : raw
        }
        return parsed.kind.localizedTitle
    }

    var shortTitle: String {
        let parsed = FinancialAccountKind.parse(accountType)
        if let name = parsed.name, !name.isEmpty {
            return name
        }
        if parsed.kind == .other {
            let raw = accountType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? "account".localizedStringFallback : raw
        }
        return parsed.kind.localizedTitle
    }

    var subtitleTitle: String? {
        let parsed = FinancialAccountKind.parse(accountType)
        if let name = parsed.name, !name.isEmpty, parsed.kind != .other {
            return parsed.kind.localizedTitle
        }
        return nil
    }
}
