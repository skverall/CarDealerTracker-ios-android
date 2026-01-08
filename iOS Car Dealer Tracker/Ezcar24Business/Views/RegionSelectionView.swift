//
//  RegionSelectionView.swift
//  Ezcar24Business
//
//  First-launch region selection and settings page for language/currency preferences.
//

import SwiftUI

// MARK: - Region Selection Sheet (First Launch)

struct RegionSelectionSheet: View {
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedRegion: AppRegion = .uae
    
    var body: some View {
        NavigationStack {
            ZStack {
                ColorTheme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Header
                            VStack(spacing: 16) {
                                Circle()
                                    .fill(ColorTheme.secondaryBackground)
                                    .frame(width: 80, height: 80)
                                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                                    .overlay(
                                        Image(systemName: "banknote.fill") // Currency icon
                                            .font(.system(size: 40))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [ColorTheme.primary, ColorTheme.accent],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .padding(.bottom, 8)
                                
                                Text("welcome_to_app".localizedString)
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(ColorTheme.primaryText)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true) // Allow text to wrap/expand vertically
                                
                                Text("select_your_currency".localizedString) // Changed key
                                    .font(.body)
                                    .foregroundColor(ColorTheme.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }
                            .padding(.top, 60) // Add explicit top padding so it's not cut off
                            .padding(.bottom, 40)
                            .padding(.horizontal)
                            
                            // Region Grid
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ], spacing: 16) {
                                ForEach(AppRegion.allCases) { region in
                                    RegionCard(
                                        region: region,
                                        isSelected: selectedRegion == region
                                    ) {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedRegion = region
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 100) // Extra padding at bottom for scrolling
                        }
                    }
                    
                    // Continue Button - Pinned to bottom
                    VStack {
                        Button {
                            regionSettings.selectedRegion = selectedRegion
                            regionSettings.hasSelectedRegion = true
                            dismiss()
                        } label: {
                            Text("continue_button".localizedString)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    LinearGradient(
                                        colors: [ColorTheme.primary, ColorTheme.primary.opacity(0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(16)
                                .shadow(color: ColorTheme.primary.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(ColorTheme.background) // Ensure background covers list content upon scroll
                }
            }
            .interactiveDismissDisabled()
        }
    }
}

private struct RegionCard: View {
    let region: AppRegion
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    // Currency Icon Circle
                    ZStack {
                        Circle()
                            .fill(ColorTheme.secondaryBackground)
                            .frame(width: 44, height: 44)
                            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        
                        Text(region.currencySymbol)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(ColorTheme.primaryText)
                    }
                    
                    Spacer()
                    
                    // Selection indicator
                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? ColorTheme.primary : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1.5)
                            .frame(width: 24, height: 24)
                        
                        if isSelected {
                            Circle()
                                .fill(ColorTheme.primary)
                                .frame(width: 14, height: 14)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(region.displayName)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(ColorTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    Text("\(region.currencyCode) • \(region.usesKilometers ? "km" : "mi")")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(ColorTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(isSelected ? ColorTheme.primary : Color.clear, lineWidth: 2)
                    )
            )
            .shadow(
                color: Color.black.opacity(isSelected ? 0.08 : 0.04),
                radius: 12,
                x: 0,
                y: 4
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Region & Language Settings View

struct RegionLanguageSettingsView: View {
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            // Currency/Region Section
            Section {
                ForEach(AppRegion.allCases) { region in
                    Button {
                        withAnimation {
                            regionSettings.selectedRegion = region
                        }
                    } label: {
                        HStack(spacing: 16) {
                             // Currency Icon Circle
                            ZStack {
                                Circle()
                                    .fill(ColorTheme.secondaryBackground)
                                    .frame(width: 40, height: 40)
                                
                                Text(region.currencySymbol)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(ColorTheme.primaryText)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(region.displayName)
                                    .font(.body)
                                    .foregroundColor(ColorTheme.primaryText)
                                
                                Text("\(region.currencyCode) • \(region.usesKilometers ? "km" : "miles")")
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.secondaryText)
                            }
                            
                            Spacer()
                            
                            if regionSettings.selectedRegion == region {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(ColorTheme.primary)
                                    .font(.title3)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("select_currency".localizedString) // Changed
                    .textCase(nil)
            } footer: {
                Text("This affects currency formatting and distance units")
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }
            
            // Language Section
            Section {
                ForEach(AppLanguage.allCases.filter { $0 == .english || $0 == .russian }) { language in
                    Button {
                        withAnimation {
                            regionSettings.selectedLanguage = language
                        }
                    } label: {
                        HStack(spacing: 16) {
                            Text(language == .english ? "🇬🇧" : "🇷🇺") // Hardcoded flags for language only
                                .font(.title2)
                            
                            Text(language.nativeName)
                                .font(.body)
                                .foregroundColor(ColorTheme.primaryText)
                            
                            Spacer()
                            
                            if regionSettings.selectedLanguage == language {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(ColorTheme.primary)
                                    .font(.title3)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("app_language".localizedString)

                    .textCase(nil)
                    Text("App will use system language if available, or fallback to English")
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }
            
            // Current Settings Preview
            Section {
                HStack {
                    Text("currency".localizedString)
                    Spacer()
                    Text(regionSettings.selectedRegion.currencyCode)
                        .foregroundColor(ColorTheme.secondaryText)
                }
                
                HStack {
                    Text("mileage".localizedString)
                    Spacer()
                    Text(regionSettings.selectedRegion.usesKilometers ? "Kilometers" : "Miles")
                        .foregroundColor(ColorTheme.secondaryText)
                }
                
                HStack {
                    Text("Example")
                    Spacer()
                    Text(regionSettings.formatCurrency(Decimal(12345.67)))
                        .foregroundColor(ColorTheme.secondaryText)
                }
            } header: {
                Text("Preview")
                    .textCase(nil)
            }
        }
        .navigationTitle("region_language".localizedString)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    // Post notification to close account sheet and go to dashboard
                    NotificationCenter.default.post(name: .currencySettingsDidComplete, object: nil)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ColorTheme.primary)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Region Selection") {
    RegionSelectionSheet()
        .environmentObject(RegionSettingsManager.shared)
}

#Preview("Settings") {
    NavigationStack {
        RegionLanguageSettingsView()
            .environmentObject(RegionSettingsManager.shared)
    }
}
