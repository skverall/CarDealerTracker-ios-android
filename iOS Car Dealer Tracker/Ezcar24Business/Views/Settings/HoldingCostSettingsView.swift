//
//  HoldingCostSettingsView.swift
//  Ezcar24Business
//
//  Settings screen for holding cost configuration
//

import SwiftUI

struct HoldingCostSettingsView: View {
    @StateObject private var viewModel = HoldingCostSettingsViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $viewModel.isEnabled) {
                        HStack {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.title2)
                                .foregroundColor(viewModel.isEnabled ? ColorTheme.success : ColorTheme.secondaryText)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("enable_holding_cost".localizedString)
                                    .font(.body)
                                
                                Text("calculate_inventory_cost".localizedString)
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.secondaryText)
                            }
                        }
                    }
                    .onChange(of: viewModel.isEnabled) { _, _ in
                        viewModel.saveSettings()
                    }
                }
                
                if viewModel.isEnabled {
                    Section("annual_rate".localizedString) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(viewModel.formattedAnnualRate)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(ColorTheme.primary)
                                
                                Spacer()
                                
                                Text("per_year".localizedString)
                                    .font(.subheadline)
                                    .foregroundColor(ColorTheme.secondaryText)
                            }
                            
                            Slider(
                                value: Binding(
                                    get: { NSDecimalNumber(decimal: viewModel.annualRatePercent).doubleValue },
                                    set: { viewModel.setAnnualRate(Decimal($0)) }
                                ),
                                in: 0...50,
                                step: 0.5
                            )
                            .tint(ColorTheme.primary)
                        }
                        .padding(.vertical, 8)
                        
                        HStack(spacing: 12) {
                            ForEach(viewModel.presetRates, id: \.self) { rate in
                                Button(action: {
                                    withAnimation {
                                        viewModel.setAnnualRate(rate)
                                        viewModel.saveSettings()
                                    }
                                }) {
                                    Text("\(NSDecimalNumber(decimal: rate).intValue)%")
                                        .font(.subheadline)
                                        .fontWeight(viewModel.annualRatePercent == rate ? .bold : .medium)
                                        .foregroundColor(viewModel.annualRatePercent == rate ? .white : ColorTheme.primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(viewModel.annualRatePercent == rate ? ColorTheme.primary : ColorTheme.secondaryBackground)
                                        )
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    Section("calculated_rates".localizedString) {
                        HStack {
                            Text("daily_rate".localizedString)
                                .font(.body)
                            
                            Spacer()
                            
                            Text(viewModel.formattedDailyRate)
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(ColorTheme.primary)
                        }
                        
                        HStack {
                            Text("monthly_rate".localizedString)
                                .font(.body)
                            
                            Spacer()
                            
                            let monthlyRate = viewModel.dailyRatePercent * 30
                            Text(String(format: "%.3f%%", NSDecimalNumber(decimal: monthlyRate).doubleValue))
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(ColorTheme.primary)
                        }
                    }
                    
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(ColorTheme.secondary)
                                
                                Text("about_holding_cost".localizedString)
                                    .font(.headline)
                            }
                            
                            Text(viewModel.explanationText)
                                .font(.subheadline)
                                .foregroundColor(ColorTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("holding_cost_settings".localizedString)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("done".localizedString) {
                        dismiss()
                    }
                }
            }
            .overlay {
                if viewModel.saveSuccess {
                    VStack {
                        Spacer()
                        
                        Label("saved".localizedString, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(ColorTheme.success)
                            .cornerRadius(20)
                            .padding(.bottom, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
    }
}

#Preview {
    HoldingCostSettingsView()
}