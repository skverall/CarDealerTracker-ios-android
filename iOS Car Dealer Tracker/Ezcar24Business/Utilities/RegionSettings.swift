//
//  RegionSettings.swift
//  Ezcar24Business
//
//  Centralized region and localization configuration.
//  Easily extensible for adding new regions and currencies.
//

import Foundation
import SwiftUI

// MARK: - Supported Regions

enum AppRegion: String, CaseIterable, Codable, Identifiable {
    case uae = "UAE"
    case usa = "USA"
    case uk = "UK"
    case europe = "Europe"
    case russia = "Russia"
    case turkey = "Turkey"
    case japan = "Japan"
    case india = "India"
    case korea = "Korea"
    
    var id: String { rawValue }
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .uae: return "UAE Dirham"
        case .usa: return "US Dollar"
        case .uk: return "British Pound"
        case .europe: return "Euro"
        case .russia: return "Russian Ruble"
        case .turkey: return "Turkish Lira"
        case .japan: return "Japanese Yen"
        case .india: return "Indian Rupee"
        case .korea: return "Korean Won"
        }
    }
    
    /// ISO 4217 currency code
    var currencyCode: String {
        switch self {
        case .uae: return "AED"
        case .usa: return "USD"
        case .uk: return "GBP"
        case .europe: return "EUR"
        case .russia: return "RUB"
        case .turkey: return "TRY"
        case .japan: return "JPY"
        case .india: return "INR"
        case .korea: return "KRW"
        }
    }
    
    /// Currency symbol for display
    var currencySymbol: String {
        switch self {
        case .uae: return "AED"
        case .usa: return "$"
        case .uk: return "£"
        case .europe: return "€"
        case .russia: return "₽"
        case .turkey: return "₺"
        case .japan: return "¥"
        case .india: return "₹"
        case .korea: return "₩"
        }
    }
    
    /// Locale identifier for formatting
    var localeIdentifier: String {
        switch self {
        case .uae: return "en_AE"
        case .usa: return "en_US"
        case .uk: return "en_GB"
        case .europe: return "en_IE" // Ireland uses Euro and English
        case .russia: return "ru_RU"
        case .turkey: return "tr_TR"
        case .japan: return "ja_JP"
        case .india: return "en_IN"
        case .korea: return "ko_KR"
        }
    }
    
    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }
    
    /// Whether this region uses kilometers (false = miles)
    var usesKilometers: Bool {
        return self != .usa && self != .uk // UK uses miles for roads
    }
    
    /// Number of decimal places for currency
    var currencyDecimals: Int {
        switch self {
        case .korea, .japan: return 0  // Won and Yen typically don't use decimals
        default: return 2
        }
    }
}

// MARK: - Supported Languages

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case english = "en"
    case russian = "ru"
    case arabic = "ar"
    case korean = "ko"
    
    var id: String { rawValue }
    
    /// Display name in native language
    var nativeName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Русский"
        case .arabic: return "العربية"
        case .korean: return "한국어"
        }
    }
    
    // Flag removed as requested, using just text or generic icons in UI if needed.
    // Keeping this property for compatibility if needed elsewhere, but changing implementation?
    // User specifically asked to remove flag emojis. I will remove the property to force compilation errors where it's used, to ensure I catch all usages.
    
    /// Whether this language uses RTL (Right-to-Left)
    var isRTL: Bool {
        return self == .arabic
    }
    
    var locale: Locale {
        Locale(identifier: rawValue)
    }
}

// MARK: - Region Settings Manager

@MainActor
final class RegionSettingsManager: ObservableObject {
    static let shared = RegionSettingsManager()
    
    private let regionKey = "app_selected_region"
    private let languageKey = "app_selected_language"
    private let hasSelectedRegionKey = "app_has_selected_region"
    
    @Published var selectedRegion: AppRegion {
        didSet {
            UserDefaults.standard.set(selectedRegion.rawValue, forKey: regionKey)
            updateFormatters()
        }
    }
    
    @Published var selectedLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: languageKey)
        }
    }
    
    @Published var hasSelectedRegion: Bool {
        didSet {
            UserDefaults.standard.set(hasSelectedRegion, forKey: hasSelectedRegionKey)
        }
    }
    
    // Formatters
    private(set) var currencyFormatter: NumberFormatter!
    private(set) var compactCurrencyFormatter: NumberFormatter!
    private(set) var dateFormatter: DateFormatter!
    private(set) var numberFormatter: NumberFormatter!
    
    private init() {
        // Load saved preferences or use defaults
        if let savedRegion = UserDefaults.standard.string(forKey: regionKey),
           let region = AppRegion(rawValue: savedRegion) {
            self.selectedRegion = region
        } else {
            self.selectedRegion = .uae  // Default for existing users
        }
        
        if let savedLanguage = UserDefaults.standard.string(forKey: languageKey),
           let language = AppLanguage(rawValue: savedLanguage) {
            self.selectedLanguage = language
        } else {
            self.selectedLanguage = .english
        }
        
        self.hasSelectedRegion = UserDefaults.standard.bool(forKey: hasSelectedRegionKey)
        
        updateFormatters()
    }
    
    private func updateFormatters() {
        // Currency formatter with full precision
        currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .currency
        currencyFormatter.currencyCode = selectedRegion.currencyCode
        currencyFormatter.currencySymbol = selectedRegion.currencySymbol + " "
        currencyFormatter.maximumFractionDigits = selectedRegion.currencyDecimals
        currencyFormatter.minimumFractionDigits = selectedRegion.currencyDecimals
        currencyFormatter.locale = selectedRegion.locale
        
        // Compact currency formatter (no decimals)
        compactCurrencyFormatter = NumberFormatter()
        compactCurrencyFormatter.numberStyle = .currency
        compactCurrencyFormatter.currencyCode = selectedRegion.currencyCode
        compactCurrencyFormatter.currencySymbol = selectedRegion.currencySymbol + " "
        compactCurrencyFormatter.maximumFractionDigits = 0
        compactCurrencyFormatter.minimumFractionDigits = 0
        compactCurrencyFormatter.locale = selectedRegion.locale
        
        // Date formatter
        dateFormatter = DateFormatter()
        dateFormatter.locale = selectedRegion.locale
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        
        // Number formatter
        numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.locale = selectedRegion.locale
    }
    
    // MARK: - Formatting Methods
    
    func formatCurrency(_ value: Decimal) -> String {
        return currencyFormatter.string(from: NSDecimalNumber(decimal: value)) 
            ?? "\(selectedRegion.currencySymbol) 0"
    }
    
    func formatCurrencyCompact(_ value: Decimal) -> String {
        return compactCurrencyFormatter.string(from: NSDecimalNumber(decimal: value)) 
            ?? "\(selectedRegion.currencySymbol) 0"
    }
    
    func formatDistance(_ kilometers: Double) -> String {
        if selectedRegion.usesKilometers {
            return numberFormatter.string(from: NSNumber(value: kilometers))! + " km"
        } else {
            let miles = kilometers * 0.621371
            return numberFormatter.string(from: NSNumber(value: miles))! + " mi"
        }
    }
    
    func formatMileage(_ value: Int) -> String {
        let formatted = numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return formatted + (selectedRegion.usesKilometers ? " km" : " mi")
    }
    
    /// Convert stored kilometers to display value
    func displayMileage(fromKilometers km: Int) -> Int {
        if selectedRegion.usesKilometers {
            return km
        } else {
            return Int(Double(km) * 0.621371)
        }
    }
    
    /// Convert input mileage to kilometers for storage
    func kilometersFromInput(_ value: Int) -> Int {
        if selectedRegion.usesKilometers {
            return value
        } else {
            return Int(Double(value) / 0.621371)
        }
    }
}

// MARK: - Environment Key
// Removed unused RegionSettingsKey to resolve Swift 6 concurrency strictness with MainActor singleton.
// The app consistently uses @EnvironmentObject for RegionSettingsManager.

// MARK: - Convenience Extensions

extension View {
    func withRegionSettings() -> some View {
        self.environmentObject(RegionSettingsManager.shared)
    }
}
