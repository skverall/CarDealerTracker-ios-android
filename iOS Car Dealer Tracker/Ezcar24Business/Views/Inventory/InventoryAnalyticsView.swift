//
//  InventoryAnalyticsView.swift
//  Ezcar24Business
//
//  Inventory analytics dashboard with health score and alerts
//

import SwiftUI

struct InventoryAnalyticsView: View {
    @StateObject private var viewModel = InventoryAnalyticsViewModel()
    @Environment(\.dismiss) private var dismiss
    var showNavigation: Bool = true
    
    var body: some View {
        Group {
            if showNavigation {
                NavigationStack {
                    content
                }
            } else {
                content
            }
        }
    }
    
    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                healthScoreSection
                
                keyMetricsSection
                
                agingDistributionSection
                
                if !viewModel.alerts.isEmpty {
                    alertsSection
                }
                
                burningInventorySection
            }
            .padding(.vertical)
        }
        .background(ColorTheme.secondaryBackground)
        .navigationTitle("inventory_analytics".localizedString)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    viewModel.refreshData()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .refreshable {
            viewModel.refreshData()
        }
    }
    
    private var healthScoreSection: some View {
        VStack(spacing: 16) {
            InventoryHealthScore(
                score: viewModel.healthScore,
                size: 140,
                showGrade: true,
                showLabel: true
            )
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
    }
    
    private var keyMetricsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            InventoryMetricsCard(
                title: "total_holding_cost".localizedString,
                value: viewModel.totalHoldingCost.asCurrency(),
                subtitle: "\(viewModel.totalVehicles) vehicles",
                icon: "dollarsign.circle.fill",
                color: ColorTheme.warning
            )
            
            InventoryMetricsCard(
                title: "avg_days_inventory".localizedString,
                value: "\(viewModel.averageDaysInInventory)",
                subtitle: "Target: < 30 days",
                icon: "calendar",
                color: viewModel.averageDaysInInventory > 60 ? ColorTheme.danger : ColorTheme.primary
            )
            
            TurnoverMetricsCard(
                ratio: viewModel.turnoverRatio,
                averageDays: viewModel.averageDaysInInventory
            )
            
            InventoryMetricsCard(
                title: "inventory_value".localizedString,
                value: viewModel.totalInventoryValue.asCurrency(),
                subtitle: "Total investment",
                icon: "car.fill",
                color: ColorTheme.success
            )
        }
        .padding(.horizontal)
    }
    
    private var agingDistributionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("aging_distribution".localizedString)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)
                
                Spacer()
                
                Text("\(viewModel.totalVehicles) total")
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }
            
            AgingDistributionChart(distribution: viewModel.agingDistribution)
            
            HStack(spacing: 8) {
                ForEach(AgingBucket.allCases, id: \.self) { bucket in
                    let count = viewModel.agingDistribution[bucket] ?? 0
                    if count > 0 {
                        AgingBucketBadge(bucket: bucket, showCount: count)
                    }
                }
            }
        }
        .padding()
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
    }
    
    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("active_alerts".localizedString)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)
                
                Spacer()
                
                Text("\(viewModel.alerts.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ColorTheme.danger)
                    .cornerRadius(12)
            }
            
            LazyVStack(spacing: 12) {
                ForEach(viewModel.alerts.prefix(5)) { alertItem in
                    if let alert = alertItem.alert {
                        InventoryAlertCard(
                            alert: alert,
                            vehicle: viewModel.getVehicle(for: alertItem),
                            onDismiss: {
                                viewModel.dismissAlert(alertItem)
                            }
                        )
                    }
                }
            }
            
            if viewModel.alerts.count > 5 {
                Button(action: {
                    // Navigate to full alerts list
                }) {
                    Text("view_all_alerts".localizedString)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(ColorTheme.primary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
            }
        }
        .padding()
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
    }
    
    private var burningInventorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("burning_inventory".localizedString)
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText)
                    
                    Text(String(format: "vehicles_over_days".localizedString, viewModel.burningThreshold))
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
                
                Spacer()
                
                Menu {
                    Picker("Filter", selection: $viewModel.selectedFilter) {
                        ForEach(InventoryAnalyticsViewModel.FilterOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    
                    Divider()
                    
                    Picker("Sort", selection: $viewModel.sortOption) {
                        ForEach(InventoryAnalyticsViewModel.SortOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title3)
                        .foregroundColor(ColorTheme.primary)
                }
            }
            
            if viewModel.filteredVehicles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(ColorTheme.success)
                    
                    Text("no_burning_inventory".localizedString)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.filteredVehicles.prefix(10), id: \.id) { vehicle in
                        BurningVehicleRow(
                            vehicle: vehicle,
                            stats: viewModel.getStats(for: vehicle.id ?? UUID())
                        )
                    }
                }
                
                if viewModel.filteredVehicles.count > 10 {
                    Text("+ \(viewModel.filteredVehicles.count - 10) more vehicles")
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                }
            }
        }
        .padding()
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
    }
}

struct BurningVehicleRow: View {
    let vehicle: Vehicle
    let stats: VehicleInventoryStats?
    
    private var daysInInventory: Int {
        Int(stats?.daysInInventory ?? 0)
    }
    
    private var holdingCost: Decimal {
        stats?.holdingCostAccumulated?.decimalValue ?? 0
    }
    
    private var totalCost: Decimal {
        stats?.totalCost?.decimalValue ?? 0
    }
    
    private var roi: Decimal? {
        stats?.roiPercent?.decimalValue
    }

    private var dailyHoldingCost: Decimal {
        guard daysInInventory > 0 else { return 0 }
        return holdingCost / Decimal(daysInInventory)
    }
    
    var body: some View {
        NavigationLink(destination: VehicleDetailView(vehicle: vehicle)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(ColorTheme.primaryText)
                    
                    Text("\(vehicle.year.asYear()) • \(vehicle.vin ?? "")")
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    DaysInInventoryIndicator(days: daysInInventory, isCompact: true)
                    
                    if holdingCost > 0 {
                        HoldingCostMiniIndicator(
                            dailyCost: dailyHoldingCost,
                            accumulatedCost: holdingCost
                        )
                    }
                    
                    if let roi = roi {
                        ROIBadge(roi: roi, isCompact: true, showLabel: false)
                    }
                }
            }
            .padding()
            .background(ColorTheme.secondaryBackground)
            .cornerRadius(12)
        }
    }
}

#Preview {
    InventoryAnalyticsView()
}
