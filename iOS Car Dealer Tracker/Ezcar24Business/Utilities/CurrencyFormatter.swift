//
//  CurrencyFormatter.swift
//  Ezcar24Business
//
//  Dynamic currency formatting utilities.
//  Uses RegionSettingsManager for region-aware formatting.
//

import Foundation

@MainActor
struct CurrencyFormatter {
    static let shared = CurrencyFormatter()
    
    /// Format with full precision (e.g., "$ 1,234.56")
    func format(_ value: Decimal) -> String {
        return RegionSettingsManager.shared.formatCurrency(value)
    }
    
    /// Format without decimals (e.g., "$ 1,235")
    func formatCompact(_ value: Decimal) -> String {
        return RegionSettingsManager.shared.formatCurrencyCompact(value)
    }
    
    /// Current currency code (e.g., "USD", "RUB")
    var currencyCode: String {
        return RegionSettingsManager.shared.selectedRegion.currencyCode
    }
    
    /// Current currency symbol (e.g., "$", "₽")
    var currencySymbol: String {
        return RegionSettingsManager.shared.selectedRegion.currencySymbol
    }
}

// MARK: - Decimal Extension (nonisolated fallback)

extension Decimal {
    /// Formats the decimal as currency using the current region settings.
    /// Use this from MainActor context. For nonisolated use, call formatCurrencyStatic.
    @MainActor
    func asCurrency() -> String {
        return CurrencyFormatter.shared.format(self)
    }
    
    @MainActor
    func asCurrencyCompact() -> String {
        return CurrencyFormatter.shared.formatCompact(self)
    }
    
    /// Static fallback for nonisolated contexts - uses default AED formatting
    func asCurrencyFallback() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "AED"
        formatter.currencySymbol = "AED "
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: self as NSDecimalNumber) ?? "\(self)"
    }
}

// MARK: - Mileage Formatting

extension Int {
    /// Format as mileage with region-aware units (km/mi)
    @MainActor
    func asMileage() -> String {
        return RegionSettingsManager.shared.formatMileage(self)
    }
    
    /// Fallback for nonisolated context
    func asMileageFallback() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return (formatter.string(from: NSNumber(value: self)) ?? "\(self)") + " km"
    }
}
