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
        let _ = regionSettings.selectedRegion
        if showNavigation {
            NavigationStack {
                content
            }
        } else {
            content
        }
    }
    
    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(ColorTheme.secondaryText)
            
            TextField(searchPlaceholder, text: activeSearchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.subheadline)
                .foregroundColor(ColorTheme.primaryText)
            
            if !activeSearchText.wrappedValue.isEmpty {
                Button {
                    activeSearchText.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
        }
        .padding(10)
        .background(ColorTheme.cardBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ColorTheme.primary.opacity(0.1), lineWidth: 1)
        )
    }

    var content: some View {
        ZStack {
            ColorTheme.background.ignoresSafeArea()
            
            List {
                // Header section containing all controls to ensure scroll unity and pull-to-refresh flow
                Section {
                    VStack(spacing: 12) {
                        if showNavigation, canViewFinancials {
                            Picker("Section".localizedString, selection: $selectedSection) {
                                ForEach(SalesSection.allCases) { section in
                                    Text(section.title).tag(section)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        searchField

                        if activeSection == .debts {
                            Picker("Debt Filter".localizedString, selection: $debtViewModel.filter) {
                                ForEach(DebtViewModel.DebtFilter.allCases) { filter in
                                    Text(filter.title).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        if activeSection == .sales {
                            Picker("Sales Filter".localizedString, selection: $viewModel.filter) {
                                Text("all_filter".localizedString).tag(SalesViewModel.SaleTypeFilter.all)
                                Text("vehicles".localizedString).tag(SalesViewModel.SaleTypeFilter.vehicles)
                                Text("parts_filter".localizedString).tag(SalesViewModel.SaleTypeFilter.parts)
                            }
                            .pickerStyle(.segmented)
                            
                            SalesInsightsView(
                                salesCount: viewModel.unifiedSales.count,
                                netProfit: totalNetProfitVisible,
                                totalReceivables: totalReceivables,
                                showProfit: canShowProfitSummary
                            )
                            .padding(.top, 4)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                
                // Data Rows
                Section {
                    switch activeSection {
                    case .sales:
                        if viewModel.unifiedSales.isEmpty {
                            EmptySalesView()
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(viewModel.unifiedSales) { item in
                                ZStack {
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
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                            .onDelete(perform: deleteItems)
                            .deleteDisabled(!canDeleteRecords)
                        }
                    case .debts:
                        if debtViewModel.debtItems.isEmpty {
                            EmptyDebtsView()
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(debtViewModel.debtItems) { item in
                                ZStack {
                                    NavigationLink(destination: DebtDetailView(debt: item.debt, viewModel: debtViewModel)) {
                                        EmptyView()
                                    }
                                    .opacity(0)

                                    DebtCard(item: item)
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                            .onDelete(perform: deleteDebts)
                            .deleteDisabled(!canDeleteRecords)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .padding(.bottom, 90)
            .refreshable {
                if case .signedIn(let user) = sessionStore.status {
                    await cloudSyncManager.manualSync(user: user)
                    viewModel.fetchAll()
                    debtViewModel.fetchDebts()
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

    private func deleteDebts(at offsets: IndexSet) {
        guard canDeleteRecords else { return }
        for index in offsets {
            let debt = debtViewModel.debtItems[index].debt
            debtViewModel.deleteDebt(debt)
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
    
    private func canViewProfit(for item: UnifiedSaleItem) -> Bool {
        switch item.type {
        case .vehicle:
            return permissionService.canViewVehicleProfit()
        case .part:
            return permissionService.canViewPartProfit()
        }
    }

    private func canViewCost(for item: UnifiedSaleItem) -> Bool {
        switch item.type {
        case .vehicle:
            return permissionService.canViewVehicleCost()
        case .part:
            return permissionService.canViewPartCost()
        }
    }

    private var visibleProfitItems: [UnifiedSaleItem] {
        viewModel.unifiedSales.filter { canViewProfit(for: $0) }
    }

    private var totalNetProfitVisible: Decimal {
        visibleProfitItems.reduce(Decimal(0)) { $0 + $1.profit }
    }

    private var canShowProfitSummary: Bool {
        switch viewModel.filter {
        case .vehicles:
            return permissionService.canViewVehicleProfit()
        case .parts:
            return permissionService.canViewPartProfit()
        case .all:
            return permissionService.canViewVehicleProfit() || permissionService.canViewPartProfit()
        }
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

        if canViewCost {
            items.append(
                Metric(
                    title: "cost".localizedString,
                    amount: item.cost,
                    color: ColorTheme.secondaryText,
                    isBold: false
                )
            )
        }

        if canViewProfit {
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

    private var canViewCost: Bool {
        switch item.type {
        case .vehicle:
            return permissionService.canViewVehicleCost()
        case .part:
            return permissionService.canViewPartCost()
        }
    }

    private var canViewProfit: Bool {
        switch item.type {
        case .vehicle:
            return permissionService.canViewVehicleProfit()
        case .part:
            return permissionService.canViewPartProfit()
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        // Icon based on type with premium gradient background
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [ColorTheme.primary, ColorTheme.secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 28, height: 28)
                            
                            Image(systemName: iconName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        Text(item.title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(ColorTheme.primaryText)
                    }
                    
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(ColorTheme.secondaryText)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                        Text(item.buyerName)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(ColorTheme.secondaryText.opacity(0.8))
                }
                
                Spacer()
                
                Text(item.date, formatter: saleDateFormatter)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(ColorTheme.primary.opacity(0.08))
                    .foregroundColor(ColorTheme.primary)
                    .clipShape(Capsule())
            }
            
            // Financials Grid
            HStack(spacing: 8) {
                ForEach(metrics) { metric in
                    FinancialColumn(
                        title: metric.title,
                        amount: metric.amount,
                        color: metric.color,
                        isBold: metric.isBold
                    )
                }
            }
        }
        .padding(14)
        .cardStyle()
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
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(ColorTheme.secondaryText.opacity(0.8))
            
            Text(amount.asCurrency())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(color)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(isBold ? color.opacity(0.08) : ColorTheme.background.opacity(0.4))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isBold ? color.opacity(0.15) : ColorTheme.primary.opacity(0.05), lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
    }
}

struct EmptySalesView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)
            
            ZStack {
                Circle()
                    .fill(ColorTheme.primary.opacity(0.06))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(ColorTheme.primary.opacity(0.6))
            }
            
            VStack(spacing: 8) {
                Text("no_sales_yet".localizedString)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(ColorTheme.primaryText)
                
                Text("record_first_sale".localizedString)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(ColorTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            Spacer(minLength: 40)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(ColorTheme.cardBackground)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(ColorTheme.primary.opacity(0.06), lineWidth: 1)
        )
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
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // 1. Sales Count
                CompactInsightCard(
                    title: "sold".localizedString.uppercased(),
                    value: "\(salesCount)",
                    color: ColorTheme.primary,
                    iconName: "car.fill",
                    accentGradient: LinearGradient(colors: [ColorTheme.primary, ColorTheme.secondary], startPoint: .top, endPoint: .bottom)
                )
                
                // 2. Receivables
                CompactInsightCard(
                    title: "receivables".localizedString.uppercased(),
                    value: totalReceivables.asCurrency(),
                    color: ColorTheme.accent,
                    iconName: "clock.fill",
                    accentGradient: LinearGradient(colors: [ColorTheme.accent, ColorTheme.accent.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                )
            }
            
            if showProfit {
                // 3. Grand Net Profit (Full Width)
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(ColorTheme.success.opacity(0.15))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(ColorTheme.success)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("net_profit".localizedString.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(ColorTheme.secondaryText.opacity(0.8))
                        
                        Text(netProfit.asCurrency())
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(netProfit >= 0 ? ColorTheme.success : ColorTheme.danger)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(ColorTheme.cardBackground)
                .cornerRadius(18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(LinearGradient(colors: [ColorTheme.success.opacity(0.3), ColorTheme.success.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
                .shadow(color: ColorTheme.success.opacity(0.06), radius: 8, x: 0, y: 4)
            }
        }
    }
}

fileprivate struct CompactInsightCard: View {
    let title: String
    let value: String
    let color: Color
    let iconName: String
    let accentGradient: LinearGradient
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentGradient.opacity(0.15))
                    .frame(width: 38, height: 38)
                
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(ColorTheme.secondaryText.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(LinearGradient(colors: [color.opacity(0.3), color.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .shadow(color: color.opacity(0.05), radius: 6, x: 0, y: 3)
    }
}
