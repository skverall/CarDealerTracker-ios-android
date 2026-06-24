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

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 28) {
                            header
                            currencyList
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                        .padding(.bottom, 24)
                        .frame(maxWidth: isPad ? 560 : .infinity)
                        .frame(maxWidth: .infinity)
                    }

                    continueBar
                }
            }
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(ColorTheme.primary.opacity(0.12))
                    .frame(width: 64, height: 64)

                Image(systemName: "banknote.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ColorTheme.primary, ColorTheme.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text("welcome_to_app".localizedString)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(ColorTheme.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("select_your_currency".localizedString)
                .font(.subheadline)
                .foregroundColor(ColorTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    // MARK: - Currency List

    private var currencyList: some View {
        VStack(spacing: 0) {
            ForEach(Array(AppRegion.allCases.enumerated()), id: \.element.id) { index, region in
                CurrencyRow(
                    region: region,
                    isSelected: selectedRegion == region
                ) {
                    withAnimation(.snappy(duration: 0.2)) {
                        selectedRegion = region
                    }
                }
                .staggeredAppear(index: index)

                if index < AppRegion.allCases.count - 1 {
                    Divider()
                        .padding(.leading, 70)
                }
            }
        }
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    // MARK: - Continue Button

    private var continueBar: some View {
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
                .frame(height: 54)
                .background(
                    LinearGradient(
                        colors: [ColorTheme.primary, ColorTheme.primary.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: ColorTheme.primary.opacity(0.25), radius: 10, x: 0, y: 5)
        }
        .frame(maxWidth: isPad ? 560 : .infinity)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(
            ColorTheme.background
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: -4)
        )
    }
}

private struct CurrencyRow: View {
    let region: AppRegion
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Currency symbol badge
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? ColorTheme.primary.opacity(0.14) : ColorTheme.secondaryBackground)
                        .frame(width: 42, height: 42)

                    Text(region.currencySymbol)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? ColorTheme.primary : ColorTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 4)
                }

                // Name + code/unit
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.displayName)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(ColorTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text("\(region.currencyCode) • \(region.usesKilometers ? "km".localizedString : "mi".localizedString)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(ColorTheme.secondaryText)
                }

                Spacer(minLength: 8)

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? ColorTheme.primary : Color.gray.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(isSelected ? ColorTheme.primary.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
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
                                
                                Text("\(region.currencyCode) • \(region.usesKilometers ? "km".localizedString : "miles".localizedString)")
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
                Text("select_currency".localizedString)
                    .textCase(nil)
            } footer: {
                Text("This affects currency formatting and distance units".localizedString)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }
            
            // Language Section
            Section {
                ForEach(AppLanguage.selectableLanguages) { language in
                    Button {
                        withAnimation {
                            regionSettings.selectedLanguage = language
                        }
                    } label: {
                        HStack(spacing: 16) {
                            Text(language.listIcon)
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
            } footer: {
                Text("App will use system language if available, or fallback to English".localizedString)
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
                    Text((regionSettings.selectedRegion.usesKilometers ? "Kilometers" : "Miles").localizedString)
                        .foregroundColor(ColorTheme.secondaryText)
                }
                
                HStack {
                    Text("Example".localizedString)
                    Spacer()
                    Text(regionSettings.formatCurrency(Decimal(12345.67)))
                        .foregroundColor(ColorTheme.secondaryText)
                }
            } header: {
                Text("Preview".localizedString)
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
