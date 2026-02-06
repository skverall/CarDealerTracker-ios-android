//
//  SalesListView.swift
//  Ezcar24Business
//
//  Created by Shokhabbos Makhmudov on 20/11/2025.
//

import SwiftUI

struct SalesListView: View {
    @StateObject private var viewModel: SalesViewModel
    @StateObject private var debtViewModel: DebtViewModel


    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @ObservedObject private var permissionService = PermissionService.shared
    private let showNavigation: Bool
    @State private var selectedSection: SalesSection = .sales
    
    // Sheet State
    @State private var showAddSaleSheet: Bool = false
    @State private var showAddDebtSheet: Bool = false

    private var canDeleteRecords: Bool {
        if case .signedIn = sessionStore.status {
            return permissionService.can(.deleteRecords)
        }
        return true
    }

    private var canViewFinancials: Bool {
        permissionService.can(.viewFinancials)
    }

    enum SalesSection: String, CaseIterable, Identifiable {
        case sales
        case debts

        var id: String { rawValue }

        @MainActor
        var title: String {
            switch self {
            case .sales: return "sales".localizedString
            case .debts: return "debts".localizedString
            }
        }
    }
    
    init(showNavigation: Bool = true) {
        self.showNavigation = showNavigation
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: SalesViewModel(context: context))
        _debtViewModel = StateObject(wrappedValue: DebtViewModel(context: context))
    }
    
    var body: some View {
        if showNavigation {
            NavigationStack {
                content
            }
            .id(regionSettings.selectedRegion.rawValue) // Force re-render when currency changes
        } else {
            content
                .id(regionSettings.selectedRegion.rawValue) // Force re-render when currency changes
        }
    }
    
    var content: some View {
        ZStack {
                ColorTheme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if showNavigation, canViewFinancials {
                        Picker("Section", selection: $selectedSection) {
                            ForEach(SalesSection.allCases) { section in
                                Text(section.title).tag(section)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }

                    // Search Bar
                    HStack {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(ColorTheme.secondaryText)
                            TextField(searchPlaceholder, text: activeSearchText)
                                .foregroundColor(ColorTheme.primaryText)
                        }
                        .padding(12)
                        .background(ColorTheme.secondaryBackground)
                        .cornerRadius(12)
                    }
                    .padding()

                    if activeSection == .debts {
                        Picker("Debt Filter", selection: $debtViewModel.filter) {
                            ForEach(DebtViewModel.DebtFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                    
                    if activeSection == .sales {
                        // Type Filter
                        Picker("Sales Filter", selection: $viewModel.filter) {
                            Text("all_filter".localizedString).tag(SalesViewModel.SaleTypeFilter.all)
                            Text("vehicles".localizedString).tag(SalesViewModel.SaleTypeFilter.vehicles)
                            Text("parts_filter".localizedString).tag(SalesViewModel.SaleTypeFilter.parts)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        
                        SalesInsightsView(
                            salesCount: viewModel.unifiedSales.count,
                            netProfit: totalNetProfit,
                            totalReceivables: totalReceivables,
                            showProfit: permissionService.canViewVehicleProfit() // TODO: Check if this covers parts profit perm
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    switch activeSection {
                    case .sales:
                        if viewModel.unifiedSales.isEmpty {
                            EmptySalesView()
                        } else {
                            List {
                                ForEach(viewModel.unifiedSales) { item in
                                    ZStack {
                                        // Navigation Link only for vehicles to see details?
                                        if case .vehicle(let sale) = item.type, let vehicle = sale.vehicle {
                                            NavigationLink(destination: VehicleDetailView(vehicle: vehicle)) {
                                                EmptyView()
                                            }
                                            .opacity(0)
                                        }

                                        SaleCard(item: item)
                                    }
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                }
                                .onDelete(perform: deleteItems)
                                .deleteDisabled(!canDeleteRecords)
                            }
                            .listStyle(.plain)
                            .padding(.bottom, 90) // Ensure content clears tab bar
                            .refreshable {
                                if case .signedIn(let user) = sessionStore.status {
                                    await cloudSyncManager.manualSync(user: user)
                                    viewModel.fetchAll()
                                }
                            }
                        }
                    case .debts:
                        DebtsListView(viewModel: debtViewModel)
                    }
                }
            }
            .navigationTitle(activeSection == .sales ? "sales_history".localizedString : "debts".localizedString)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if showNavigation {
                        switch activeSection {
                        case .sales:
                            if permissionService.can(.createSale) {
                                Button {
                                    showAddSaleSheet = true
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(ColorTheme.primary)
                                }
                            }
                        case .debts:
                            Button {
                                showAddDebtSheet = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(ColorTheme.primary)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddSaleSheet) {
                AddSaleView()
            }
            .sheet(isPresented: $showAddDebtSheet) {
                AddDebtView()
            }
        }
    
    private func deleteItems(at offsets: IndexSet) {
        guard canDeleteRecords else { return }
        for index in offsets {
            let item = viewModel.unifiedSales[index]
            viewModel.deleteItem(item)
        }
    }

    private var activeSection: SalesSection {
        if !showNavigation || !canViewFinancials {
            return .sales
        }
        return selectedSection
    }

    private var activeSearchText: Binding<String> {
        switch activeSection {
        case .sales:
            return $viewModel.searchText
        case .debts:
            return $debtViewModel.searchText
        }
    }

    private var searchPlaceholder: String {
        switch activeSection {
        case .sales:
            return "search".localizedString
        case .debts:
            return "search_name_or_notes".localizedString
        }
    }
    private var totalRevenue: Decimal {
        viewModel.unifiedSales.reduce(Decimal(0)) { $0 + $1.amount }
    }
    
    private var totalNetProfit: Decimal {
        viewModel.unifiedSales.reduce(Decimal(0)) { $0 + $1.profit }
    }
    
    private var totalReceivables: Decimal {
        debtViewModel.debts
            .filter { $0.directionEnum == .owedToMe && !$0.isPaid }
            .reduce(Decimal(0)) { $0 + $1.outstandingAmount }
    }
}


struct SaleCard: View {
    let item: UnifiedSaleItem
    @ObservedObject private var permissionService = PermissionService.shared
    
    private struct Metric: Identifiable {
        let id = UUID()
        let title: String
        let amount: Decimal
        let color: Color
        let isBold: Bool
    }

    private var metrics: [Metric] {
        var items: [Metric] = [
            Metric(
                title: "revenue".localizedString,
                amount: item.amount,
                color: ColorTheme.primaryText,
                isBold: false
            )
        ]

        if permissionService.canViewVehicleCost() {
            items.append(
                Metric(
                    title: "cost".localizedString,
                    amount: item.cost,
                    color: ColorTheme.secondaryText,
                    isBold: false
                )
            )
        }

        if permissionService.canViewVehicleProfit() {
            items.append(
                Metric(
                    title: "net_profit".localizedString,
                    amount: item.profit,
                    color: item.profit >= 0 ? ColorTheme.success : ColorTheme.danger,
                    isBold: true
                )
            )
        }

        return items
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        // Icon based on type
                        Image(systemName: iconName)
                            .font(.caption)
                            .foregroundColor(ColorTheme.primary)
                            .padding(4)
                            .background(ColorTheme.primary.opacity(0.1))
                            .clipShape(Circle())
                        
                        Text(item.title)
                            .font(.headline)
                            .foregroundColor(ColorTheme.primaryText)
                    }
                    
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption)
                        Text(item.buyerName)
                            .font(.caption)
                    }
                    .foregroundColor(ColorTheme.secondaryText)
                }
                
                Spacer()
                
                Text(item.date, formatter: saleDateFormatter)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ColorTheme.background)
                    .foregroundColor(ColorTheme.secondaryText)
                    .clipShape(Capsule())
            }
            .padding(16)
            
            Divider()
                .background(ColorTheme.background)
            
            // Financials Grid
            HStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                    FinancialColumn(
                        title: metric.title,
                        amount: metric.amount,
                        color: metric.color,
                        isBold: metric.isBold
                    )
                    
                    if index < metrics.count - 1 {
                        Divider()
                            .frame(height: 40)
                    }
                }
            }
            .padding(.vertical, 12)
            .background(ColorTheme.secondaryBackground.opacity(0.5))
        }
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    private var iconName: String {
        switch item.type {
        case .vehicle: return "car.fill"
        case .part: return "wrench.and.screwdriver.fill"
        }
    }
    
    private var saleDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM, h:mm a"
        return formatter
    }
}

struct FinancialColumn: View {
    let title: String
    let amount: Decimal
    let color: Color
    var isBold: Bool = false
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(ColorTheme.secondaryText)
            
            Text(amount.asCurrency())
                .font(.subheadline)
                .fontWeight(isBold ? .bold : .medium)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmptySalesView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 60))
                .foregroundColor(ColorTheme.secondaryText.opacity(0.3))
            
            Text("no_sales_yet".localizedString)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(ColorTheme.primaryText)
            
            Text("record_first_sale".localizedString)
                .font(.subheadline)
                .foregroundColor(ColorTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
    }
}

struct SalesListView_Previews: PreviewProvider {
    static var previews: some View {
        SalesListView()
    }
}

// MARK: - Insights View
struct SalesInsightsView: View {
    let salesCount: Int
    let netProfit: Decimal
    let totalReceivables: Decimal
    let showProfit: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // 1. Sales Count
            CompactInsightCard(
                title: "sold".localizedString.uppercased(),
                value: "\(salesCount)",
                color: ColorTheme.primaryText,
                bgColor: ColorTheme.secondaryBackground
            )
            
            // 2. Net Profit
            if showProfit {
                CompactInsightCard(
                    title: "net_profit".localizedString,
                    value: netProfit.asCurrency(),
                    color: ColorTheme.success,
                    bgColor: ColorTheme.success.opacity(0.1)
                )
            }
            
            // 3. Receivables
            CompactInsightCard(
                title: "receivables".localizedString,
                value: totalReceivables.asCurrency(),
                color: ColorTheme.accent,
                bgColor: ColorTheme.accent.opacity(0.1)
            )
        }
    }
}

fileprivate struct CompactInsightCard: View {
    let title: String
    let value: String
    let color: Color
    let bgColor: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(ColorTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(value)
                .font(.callout)
                .fontWeight(.bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(bgColor)
        .cornerRadius(12)
    }
}
