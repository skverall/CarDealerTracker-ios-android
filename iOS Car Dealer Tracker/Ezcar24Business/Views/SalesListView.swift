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
    private let showNavigation: Bool
    @State private var selectedSection: SalesSection = .sales

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
                    if showNavigation {
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
                        SalesInsightsView(
                            salesCount: viewModel.saleItems.count,
                            netProfit: totalNetProfit,
                            totalReceivables: totalReceivables
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    switch activeSection {
                    case .sales:
                        if viewModel.saleItems.isEmpty {
                            EmptySalesView()
                        } else {
                            List {
                                ForEach(viewModel.saleItems) { item in
                                    ZStack {
                                        if let vehicle = item.sale.vehicle {
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
                            }
                            .listStyle(.plain)
                            .refreshable {
                                if case .signedIn(let user) = sessionStore.status {
                                    await cloudSyncManager.manualSync(user: user)
                                    viewModel.fetchSales()
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
                            NavigationLink(destination: AddSaleView()) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(ColorTheme.primary)
                            }
                        case .debts:
                            NavigationLink(destination: AddDebtView()) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(ColorTheme.primary)
                            }
                        }
                    }
                }
            }
        }
    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let sale = viewModel.saleItems[index].sale
            viewModel.deleteSale(sale)
        }
    }

    private var activeSection: SalesSection {
        showNavigation ? selectedSection : .sales
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
            return "search_vehicle_or_buyer".localizedString
        case .debts:
            return "search_name_or_notes".localizedString
        }
    }
    private var totalRevenue: Decimal {
        viewModel.saleItems.reduce(Decimal(0)) { $0 + $1.salePrice }
    }
    
    private var totalNetProfit: Decimal {
        viewModel.saleItems.reduce(Decimal(0)) { $0 + $1.netProfit }
    }
    
    private var totalReceivables: Decimal {
        debtViewModel.debts
            .filter { $0.directionEnum == .owedToMe && !$0.isPaid }
            .reduce(Decimal(0)) { $0 + $1.outstandingAmount }
    }
}


struct SaleCard: View {
    let item: SaleItem
    
    var body: some View {
        VStack(spacing: 0) {
            // Header: Vehicle & Date
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.vehicleName)
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption)
                        Text(item.buyerName)
                            .font(.caption)
                    }
                    .foregroundColor(ColorTheme.secondaryText)
                }
                
                Spacer()
                
                Text(item.saleDate, formatter: saleDateFormatter)
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
                // Revenue
                FinancialColumn(
                    title: "revenue".localizedString,
                    amount: item.salePrice,
                    color: ColorTheme.primaryText
                )
                
                Divider()
                    .frame(height: 40)
                
                // Cost
                FinancialColumn(
                    title: "cost".localizedString,
                    amount: item.costPrice,
                    color: ColorTheme.secondaryText
                )
                
                Divider()
                    .frame(height: 40)
                
                // Profit
                FinancialColumn(
                    title: "net_profit".localizedString,
                    amount: item.netProfit,
                    color: item.netProfit >= 0 ? ColorTheme.success : ColorTheme.danger,
                    isBold: true
                )
            }
            .padding(.vertical, 12)
            .background(ColorTheme.secondaryBackground.opacity(0.5))
        }
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
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
            CompactInsightCard(
                title: "net_profit".localizedString,
                value: netProfit.asCurrency(),
                color: ColorTheme.success,
                bgColor: ColorTheme.success.opacity(0.1)
            )
            
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
