//
//  DashboardView.swift
//  Ezcar24Business
//
//  Compact expense dashboard aligned with mobile-first layout
//

import SwiftUI
import CoreData
import Charts


extension Notification.Name {
    static let dashboardDidRequestAccount = Notification.Name("dashboardDidRequestAccount")
    static let currencySettingsDidComplete = Notification.Name("currencySettingsDidComplete")
}

enum DashboardDestination: String, Identifiable, Hashable {
    case assets, cashAccounts, bankAccounts, creditAccounts, revenue, profit, sold, allExpenses, analytics
    var id: String { rawValue }
}

struct DashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @StateObject private var viewModel: DashboardViewModel
    @StateObject private var expenseEntryViewModel: ExpenseViewModel
    @ObservedObject private var permissionService = PermissionService.shared

    @State private var selectedRange: DashboardTimeRange = .week
    @State private var showingAddExpense: Bool = false
    @State private var showingSearch: Bool = false
    @State private var selectedExpense: Expense? = nil
    @State private var editingExpense: Expense? = nil
    @State private var navPath: [DashboardDestination] = []
    @State private var offlineQueueCount: Int = 0

    private var canDeleteRecords: Bool {
        if case .signedIn = sessionStore.status {
            return permissionService.can(.deleteRecords)
        }
        return true
    }

    init() {
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: DashboardViewModel(context: context))
        _expenseEntryViewModel = StateObject(wrappedValue: ExpenseViewModel(context: context))
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                topBar
                syncStatusBar
                    .padding(.bottom, 10)
                
                ZStack(alignment: .bottom) {
                    if permissionService.didLoad {
                        dashboardList
                            .transition(.opacity)
                    } else {
                        dashboardLoadingView
                            .background(ColorTheme.background)
                            .transition(.opacity)
                    }

                    bottomFade
                }
            }
            .background(ColorTheme.background.ignoresSafeArea())
            .navigationDestination(for: DashboardDestination.self) { destinationView(for: $0) }
        }
        .id(regionSettings.selectedRegion.rawValue) // Force re-render when currency changes
        .sheet(isPresented: $showingSearch) {
            GlobalSearchView()
        }
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(viewModel: expenseEntryViewModel)
                .environment(\.managedObjectContext, viewContext)
                .presentationDetents([.large])
                .onDisappear {
                    viewModel.fetchFinancialData(range: selectedRange)
                }
        }
        .sheet(item: $selectedExpense) { expense in
            ExpenseDetailSheet(expense: expense)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingExpense) { expense in
            AddExpenseView(viewModel: expenseEntryViewModel, editingExpense: expense)
                .environment(\.managedObjectContext, viewContext)
                .presentationDetents([.large])
                .onDisappear {
                    viewModel.fetchFinancialData(range: selectedRange)
                }
        }
        .onAppear {
            viewModel.fetchFinancialData(range: selectedRange)
        }
        .onChange(of: selectedRange) { _, newValue in
            viewModel.fetchFinancialData(range: newValue)
        }
        .onChange(of: showingAddExpense) { _, isPresented in
            if !isPresented {
                // Force refresh when sheet is dismissed to ensure new item appears
                viewModel.fetchFinancialData(range: selectedRange)
            }
        }
        .onChange(of: cloudSyncManager.lastSyncAt) { _, _ in
            Task { await refreshOfflineQueueCount() }
        }
        .onChange(of: cloudSyncManager.isSyncing) { _, _ in
            Task { await refreshOfflineQueueCount() }
        }
        .task {
            await refreshOfflineQueueCount()
        }
    }

    @ViewBuilder
    private func destinationView(for destination: DashboardDestination) -> some View {
        switch destination {
        case .assets:
            VehicleListView(showNavigation: false)
        case .cashAccounts:
            FinancialAccountsView(filterKind: .cash)
        case .bankAccounts:
            FinancialAccountsView(filterKind: .bank)
        case .creditAccounts:
            FinancialAccountsView(filterKind: .creditCard)
        case .revenue, .profit:
            SalesListView(showNavigation: false)
        case .sold:
            VehicleListView(presetStatus: "sold", showNavigation: false)
        case .allExpenses:
            ExpenseListView()
        case .analytics:
            AnalyticsHubView()
        }
    }
}

// MARK: - Top Navigation

private extension DashboardView {
    var topBar: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                    Text("dashboard_title".localizedString)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(ColorTheme.primaryText)
                    OrganizationSwitcherView()
                        .frame(maxWidth: 220, alignment: .leading)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    if cloudSyncManager.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(ColorTheme.primary)
                    }

                    Button {
                        showingSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundColor(ColorTheme.primary)
                            .frame(width: 40, height: 40)
                            .background(ColorTheme.secondaryBackground)
                            .clipShape(Circle())
                    }

                    Button {
                        NotificationCenter.default.post(name: .dashboardDidRequestAccount, object: nil)
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title2)
                            .foregroundColor(ColorTheme.primary)
                            .frame(width: 40, height: 40)
                            .background(ColorTheme.secondaryBackground)
                            .clipShape(Circle())
                    }
                    
                    Menu {
                        if permissionService.can(.viewExpenses) {
                            Button {
                                showingAddExpense = true
                            } label: {
                                Label("add_expense".localizedString, systemImage: "creditcard")
                            }
                        }
                        
                        if permissionService.can(.viewInventory) {
                            Button {
                                navPath.append(.assets)
                            } label: {
                                Label("view_vehicles".localizedString, systemImage: "car")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(ColorTheme.primary)
                            .clipShape(Circle())
                            .shadow(color: ColorTheme.primary.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
            }
            
            HStack(spacing: 6) {
                ForEach(DashboardTimeRange.allCases) { range in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedRange = range
                        }
                    } label: {
                        Text(range.displayLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule()
                                    .fill(selectedRange == range ? ColorTheme.primary : ColorTheme.secondaryBackground)
                            )
                            .foregroundColor(selectedRange == range ? .white : ColorTheme.primaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    var syncStatusBar: some View {
        HStack(spacing: 8) {
            if cloudSyncManager.isSyncing {
                ProgressView()
                    .controlSize(.mini)
                    .tint(ColorTheme.primary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(ColorTheme.success)
                    .font(.system(size: 14, weight: .semibold))
            }

            Text(syncStatusText)
                .font(.caption)
                .foregroundColor(ColorTheme.primaryText)

            if offlineQueueCount > 0 {
                Text("• \(offlineQueueCount) queued")
                    .font(.caption2)
                    .foregroundColor(ColorTheme.secondaryText)
            }

            Spacer()

            Button {
                Task { await runManualSync() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ColorTheme.primary)
                    .opacity(cloudSyncManager.isSyncing ? 0.3 : 1.0)
            }
            .buttonStyle(.plain)
            .disabled(cloudSyncManager.isSyncing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(ColorTheme.secondaryBackground)
        .overlay(
            Rectangle()
                .fill(ColorTheme.primary.opacity(0.05))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 0..<12: return "good_morning".localizedString
        case 12..<17: return "good_afternoon".localizedString
        default: return "good_evening".localizedString
        }
    }

    private var syncStatusText: String {
        if cloudSyncManager.isSyncing {
            return "syncing".localizedString
        }
        guard let date = cloudSyncManager.lastSyncAt else { return "never_synced".localizedString }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        return String(format: "synced_ago".localizedString, relative)
    }

    private func refreshOfflineQueueCount() async {
        guard case .signedIn(let user) = sessionStore.status else {
            await MainActor.run { offlineQueueCount = 0 }
            return
        }
        let items = await SyncQueueManager.shared.getAllItems()
        let dealerId = CloudSyncEnvironment.currentDealerId ?? user.id
        let count = items.filter { $0.dealerId == dealerId }.count
        await MainActor.run { offlineQueueCount = count }
    }

    @MainActor
    private func runManualSync() async {
        guard case .signedIn(let user) = sessionStore.status else {
            cloudSyncManager.showError("Sign in to sync.")
            return
        }
        await cloudSyncManager.fullSync(user: user)
        await refreshOfflineQueueCount()
    }
}

// MARK: - Sections

private extension DashboardView {
    var financialOverviewSection: some View {
        Section {
            VStack(spacing: 12) {
                if permissionService.can(.viewFinancials) {
                    // 1. Money Accounts (Cash, Bank, Credit)
                    HStack(spacing: 12) {
                        Button {
                            navPath.append(.cashAccounts)
                        } label: {
                            FinancialCard(
                                title: "payment_method_cash".localizedString,
                                amount: viewModel.totalCash,
                                icon: "banknote.fill",
                                color: .green,
                                isHero: true
                            )
                        }
                        .buttonStyle(.hapticScale)
                        
                        Button {
                            navPath.append(.bankAccounts)
                        } label: {
                            FinancialCard(
                                title: "bank".localizedString,
                                amount: viewModel.totalBank,
                                icon: "building.columns.fill",
                                color: .purple,
                                isHero: true
                            )
                        }
                        .buttonStyle(.hapticScale)

                        Button {
                            navPath.append(.creditAccounts)
                        } label: {
                            FinancialCard(
                                title: "Credit Card",
                                amount: viewModel.totalCredit,
                                icon: "creditcard.fill",
                                color: .indigo,
                                isHero: true
                            )
                        }
                        .buttonStyle(.hapticScale)
                    }

                    // 2. Business Performance Grid (Assets, Sold, Revenue, Profit)
                    let columns = [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ]
                    
                    LazyVGrid(columns: columns, spacing: 10) {
                         Button {
                            navPath.append(.assets)
                        } label: {
                            FinancialCard(
                                title: "total_assets".localizedString,
                                amount: viewModel.totalAssets,
                                icon: "car.2.fill",
                                color: Color(red: 0.25, green: 0.35, blue: 0.95),
                                isHero: true
                            )
                        }
                        .buttonStyle(.hapticScale)

                         Button {
                            navPath.append(.sold)
                        } label: {
                            FinancialCard(
                                title: "sold".localizedString,
                                amount: Decimal(viewModel.soldCount),
                                icon: "checkmark.circle.fill",
                                color: .cyan,
                                isCount: true,
                                isHero: true
                            )
                        }
                        .buttonStyle(.hapticScale)

                        Button {
                            navPath.append(.revenue)
                        } label: {
                            FinancialCard(
                                title: "total_revenue".localizedString,
                                amount: viewModel.totalSalesIncome,
                                icon: "chart.line.uptrend.xyaxis",
                                color: .orange,
                                isHero: true
                            )
                        }
                        .buttonStyle(.hapticScale)
                        
                        if permissionService.canViewVehicleProfit() {
                            Button {
                                navPath.append(.profit)
                            } label: {
                                FinancialCard(
                                    title: "net_profit".localizedString,
                                    amount: viewModel.totalSalesProfit,
                                    icon: "dollarsign.circle.fill",
                                    color: viewModel.totalSalesProfit >= 0 ? ColorTheme.success : ColorTheme.danger,
                                    isHero: true
                                )
                            }
                            .buttonStyle(.hapticScale)
                        }
                    }
                } else {
                    // Non-Financial View (Sales Person Mode)
                     HStack(spacing: 12) {
                         Button {
                            navPath.append(.assets)
                        } label: {
                            FinancialCard(
                                title: "vehicles".localizedString.capitalized,
                                amount: Decimal(viewModel.totalAssetsCount),
                                icon: "car.2.fill",
                                color: Color(red: 0.25, green: 0.35, blue: 0.95),
                                isCount: true,
                                isHero: true
                            )
                        }
                        .buttonStyle(.hapticScale)

                         Button {
                            navPath.append(.sold)
                        } label: {
                            FinancialCard(
                                title: "sold".localizedString,
                                amount: Decimal(viewModel.soldCount),
                                icon: "checkmark.circle.fill",
                                color: .cyan,
                                isCount: true,
                                isHero: true
                            )
                        }
                        .buttonStyle(.hapticScale)
                    }
                }
            }
            .padding(.horizontal, 20)
            .listRowInsets(EdgeInsets())
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
    
    var analyticsSection: some View {
        Section {
            Button {
                navPath.append(.analytics)
            } label: {
                AnalyticsEntryCard()
            }
            .buttonStyle(.plain)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    var todaysExpensesSection: some View {
        Group {
            if PermissionService.shared.can(.viewExpenses) && !viewModel.todaysExpenses.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("todays_expenses".localizedString)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(ColorTheme.primaryText)
                            Spacer()
                            Text("\(viewModel.todaysExpenses.count)")
                                .font(.footnote)
                                .foregroundColor(ColorTheme.secondaryText)
                        }

                        LazyVGrid(columns: todaysExpenseColumns, spacing: 16) {
                            ForEach(Array(viewModel.todaysExpenses.enumerated()), id: \.element.objectID) { _, expense in
                                TodayExpenseCard(expense: expense) {
                                    selectedExpense = expense
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 4, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
    }

    var todaysExpenseColumns: [GridItem] {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return [GridItem(.adaptive(minimum: 220), spacing: 16)]
        }
        return [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ]
    }

    var summarySection: some View {
        Section {
            if permissionService.can(.viewFinancials) {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], spacing: 16) {
                        summaryCardsContent
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(spacing: 16) {
                        summaryCardsContent
                    }
                    .padding(.vertical, 4)
                }
            } else {
                // Non-Financial Summary (Sales/Inv Only)
                 // "Active Vehicles" is redundant with the top card, so we remove it to clean up the UI.
                 EmptyView()
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    var recentExpensesSection: some View {
        Group {
            Section {
                 if PermissionService.shared.can(.viewExpenses) {
                    if viewModel.recentExpenses.isEmpty {
                        Text("no_recent_expenses".localizedString)
                            .foregroundColor(ColorTheme.secondaryText)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(Array(viewModel.recentExpenses.enumerated()), id: \.element.objectID) { _, expense in
                            RecentExpenseRow(expense: expense)
                                .onTapGesture {
                                    selectedExpense = expense
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if canDeleteRecords {
                                        Button(role: .destructive) {
                                            do {
                                                let deletedId = try expenseEntryViewModel.deleteExpense(expense)
                                                viewModel.fetchFinancialData(range: selectedRange)
                                                if let id = deletedId, case .signedIn(let user) = sessionStore.status {
                                                    Task {
                                                        let dealerId = CloudSyncEnvironment.currentDealerId ?? user.id
                                                        await cloudSyncManager.deleteExpense(id: id, dealerId: dealerId)
                                                    }
                                                }
                                            } catch {
                                                print("Failed to delete expense: \(error)")
                                            }
                                        } label: {
                                            Label("delete".localizedString, systemImage: "trash")
                                        }
                                    }
    
                                    Button {
                                        editingExpense = expense
                                    } label: {
                                        Label("edit".localizedString, systemImage: "pencil")
                                    }
                                    .tint(ColorTheme.accent)
                                }
                        }
                    }
                 } else {
                     Text("access_restricted".localizedString)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .center)
                 }
            } header: {
                HStack {
                    Text("recent_expenses".localizedString)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(ColorTheme.primaryText)
                    
                    Spacer()
                    
                    Button {
                        navPath.append(.allExpenses)
                    } label: {
                        HStack(spacing: 6) {
                            Text("see_all".localizedString)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .foregroundColor(ColorTheme.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(ColorTheme.secondaryBackground)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(ColorTheme.primary.opacity(0.15), lineWidth: 1)
                        )
                    }
                }
            } footer: {
                if PermissionService.shared.can(.viewExpenses) {
                    HStack(spacing: 8) {
                        Text(recentSummaryText)
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.secondaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                        
                        Spacer()
                        
                        trendBadge
                    }
                    .padding(.top, 6)
                }
            }
            .textCase(nil)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }
}

private extension DashboardView {
    var recentSummaryText: String {
        let label: String
        switch selectedRange {
        case .today:
            label = "today".localizedString
        case .week:
            label = "this_week".localizedString
        case .month:
            label = "this_month".localizedString
        case .all:
            label = "all_time".localizedString
        case .threeMonths:
            label = "last_3_months".localizedString
        case .sixMonths:
            label = "last_6_months".localizedString
        }
        let count = viewModel.periodTransactionCount
        let countLabel = count == 1 ? "expense".localizedString : "expense_plural".localizedString
        return "\(label): \(count) \(countLabel) - \(viewModel.totalExpenses.asCurrency())"
    }

    var trendBadge: some View {
        let percent = viewModel.periodChangePercent
        let value = percent ?? 0
        let isPositive = value >= 0
        let symbol = percent == nil ? "minus" : (isPositive ? "arrow.up.right" : "arrow.down.right")
        let text = percent == nil ? "--" : String(format: "%.1f%%", abs(value))
        let color = percent == nil ? ColorTheme.tertiaryText : (isPositive ? ColorTheme.success : ColorTheme.danger)

        return HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(ColorTheme.secondaryBackground)
        .clipShape(Capsule())
    }

    var bottomFade: some View {
        LinearGradient(
            colors: [
                ColorTheme.background.opacity(0.0),
                ColorTheme.background.opacity(0.85),
                ColorTheme.background
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 80)
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: -2)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    var summaryCardsContent: some View {
        SummaryOverviewCard(
            totalSpent: viewModel.totalExpenses,
            changePercent: viewModel.periodChangePercent,
            trendPoints: viewModel.trendPoints,
            range: selectedRange
        )

        if permissionService.canViewVehicleProfit() {
            ProfitOverviewCard(
                totalProfit: selectedRange == .week ? viewModel.monthlyNetProfit : viewModel.periodSalesProfit,
                trendPoints: selectedRange == .week ? viewModel.monthlyProfitTrendPoints : viewModel.profitTrendPoints,
                range: selectedRange == .week ? .month : selectedRange
            )
        }

        CategoryBreakdownCard(stats: viewModel.categoryStats)
    }
}

// MARK: - Components



private struct FinancialCard: View {
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let amount: Decimal
    let icon: String
    let color: Color
    var isCount: Bool = false
    var isHero: Bool = false
    var trendText: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundColor(isHero ? .white : color)
                    .frame(width: 24, height: 24)
                    .background(isHero ? .white.opacity(0.2) : color.opacity(0.1))
                    .clipShape(Circle())
                
                Spacer()
                
                if let trendText {
                    Text(trendText)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(isHero ? .white.opacity(0.9) : ColorTheme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isHero ? .white.opacity(0.2) : ColorTheme.secondaryBackground.opacity(0.5)) // Subtle bg
                        .clipShape(Capsule())
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(isHero ? .white.opacity(0.9) : ColorTheme.secondaryText)
                    .lineLimit(1)
                
                if isCount {
                    Text("\(NSDecimalNumber(decimal: amount).intValue)")
                        .font(.system(size: isHero ? 22 : 18, weight: .bold, design: .rounded))
                        .foregroundColor(isHero ? .white : ColorTheme.primaryText)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                } else {
                    Text(amount.asCurrencyCompact())
                        .font(.system(size: isHero ? 22 : 18, weight: .bold, design: .rounded))
                        .foregroundColor(isHero ? .white : ColorTheme.primaryText)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if isHero {
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    ColorTheme.cardBackground
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(colorScheme == .dark ? ColorTheme.glossyGlassBorder : LinearGradient(colors: [.black.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )
        .shadow(color: isHero ? color.opacity(0.4) : Color.black.opacity(colorScheme == .dark ? 0.35 : 0.05), radius: isHero ? 12 : 8, x: 0, y: isHero ? 6 : 4)
    }
}

private struct AnalyticsEntryCard: View {
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title3)
                .foregroundColor(ColorTheme.primary)
                .frame(width: 44, height: 44)
                .background(ColorTheme.primary.opacity(0.12))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text("analytics_section_title".localizedString)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)
                
                Text("analytics_section_subtitle".localizedString)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }
            
            Spacer()
            
            Text("view_analytics".localizedString)
                .font(.caption.weight(.semibold))
                .foregroundColor(ColorTheme.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ColorTheme.primary.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(16)
        .cardStyle()
    }
}

// MARK: - Private Dashboard Components

private struct TodayExpenseCard: View {
    @ObservedObject var expense: Expense
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle()
                            .fill(ColorTheme.categoryColor(for: expense.category ?? ""))
                            .opacity(0.1)
                            .frame(width: 32, height: 32)
                        Image(systemName: expense.categoryIcon)
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.categoryColor(for: expense.category ?? ""))
                    }
                    
                    Spacer()
                    
                    Text(expense.timeString)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ColorTheme.background)
                        .foregroundColor(ColorTheme.secondaryText)
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(expense.amountDecimal.asCurrency())
                        .font(.headline.weight(.bold))
                        .foregroundColor(ColorTheme.primaryText)
                    
                    Text(expense.vehicleTitle)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.hapticScale)
    }
}

private struct EmptyTodayCard: View {
    let addAction: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: "list.bullet.clipboard")
                .font(.largeTitle)
                .foregroundColor(ColorTheme.secondaryText.opacity(0.5))
                .padding(.bottom, 4)
            
            Text("no_expenses_today".localizedString)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)
            
            Button(action: addAction) {
                Text("add_expense".localizedString)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(ColorTheme.primary)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(color: ColorTheme.primary.opacity(0.3), radius: 4, x: 0, y: 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

private struct SummaryOverviewCard: View {
    let totalSpent: Decimal
    let changePercent: Double?
    let trendPoints: [TrendPoint]
    let range: DashboardTimeRange
    
    private var hasNonZeroTrend: Bool {
        trendPoints.contains { $0.value != 0 }
    }
    
    private var xDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        switch range {
        case .today:
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return startOfDay...end
        case .week:
            let start = cal.date(byAdding: .day, value: -6, to: startOfDay) ?? startOfDay
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return start...end
        case .month:
            let start = cal.date(byAdding: .day, value: -29, to: startOfDay) ?? startOfDay
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return start...end
        case .threeMonths:
            let start = cal.date(byAdding: .month, value: -3, to: startOfDay) ?? startOfDay
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return start...end
        case .sixMonths:
            let start = cal.date(byAdding: .month, value: -6, to: startOfDay) ?? startOfDay
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return start...end
        case .all:
            let start = cal.date(byAdding: .month, value: -11, to: startOfDay) ?? startOfDay
            let alignedStart = cal.date(from: cal.dateComponents([.year, .month], from: start)) ?? start
            let end = cal.date(byAdding: .month, value: 12, to: alignedStart) ?? alignedStart
            return alignedStart...end
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("total_spend".localizedString + " (\(range.displayLabel))")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(totalSpent.asCurrencyCompact())
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(ColorTheme.primaryText)
                        
                        if let changePercent {
                            HStack(spacing: 6) {
                                HStack(spacing: 4) {
                                    Image(systemName: changePercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    Text("\(abs(changePercent).formatted(.number.precision(.fractionLength(1))))%")
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .fixedSize()
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(changePercent >= 0 ? ColorTheme.danger.opacity(0.1) : ColorTheme.success.opacity(0.1))
                                .foregroundColor(changePercent >= 0 ? ColorTheme.danger : ColorTheme.success)
                                .clipShape(Capsule())
                                
                                Text(range.comparisonLabel)
                                    .font(.caption2)
                                    .foregroundColor(ColorTheme.secondaryText)
                                    .minimumScaleFactor(0.5)
                            }
                        }
                    }
                }
                Spacer()
            }

            if hasNonZeroTrend {
                Chart(trendPoints) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Amount", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ColorTheme.primary.opacity(0.2), ColorTheme.primary.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Amount", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(ColorTheme.primary)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                }
                .frame(height: 160)
                .chartXScale(domain: xDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(ColorTheme.secondaryText.opacity(0.2))
                        AxisTick()
                            .foregroundStyle(ColorTheme.secondaryText.opacity(0.2))
                        AxisValueLabel(format: .dateTime.day().weekday(), centered: true)
                            .foregroundStyle(ColorTheme.secondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(ColorTheme.secondaryText.opacity(0.2))
                        AxisValueLabel()
                            .foregroundStyle(ColorTheme.secondaryText)
                    }
                }
            } else {
                Text("no_spending_data".localizedString)
                    .font(.footnote)
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .padding(16)
        .cardStyle()
    }
}

private struct ProfitOverviewCard: View {
    let totalProfit: Decimal
    let trendPoints: [TrendPoint]
    let range: DashboardTimeRange
    
    private var xDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        switch range {
        case .today:
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return startOfDay...end
        case .week:
            let start = cal.date(byAdding: .day, value: -6, to: startOfDay) ?? startOfDay
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return start...end
        case .month:
            let start = cal.date(byAdding: .day, value: -29, to: startOfDay) ?? startOfDay
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return start...end
        case .threeMonths:
            let start = cal.date(byAdding: .month, value: -3, to: startOfDay) ?? startOfDay
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return start...end
        case .sixMonths:
            let start = cal.date(byAdding: .month, value: -6, to: startOfDay) ?? startOfDay
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return start...end
        case .all:
            let start = cal.date(byAdding: .month, value: -11, to: startOfDay) ?? startOfDay
            let alignedStart = cal.date(from: cal.dateComponents([.year, .month], from: start)) ?? start
            let end = cal.date(byAdding: .month, value: 12, to: alignedStart) ?? alignedStart
            return alignedStart...end
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("net_profit".localizedString + " (\(range.displayLabel))")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                    
                    Text(totalProfit.asCurrencyCompact())
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(ColorTheme.primaryText)
                }
                Spacer()
            }

            if !trendPoints.isEmpty {
                Chart(trendPoints) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Amount", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.green.opacity(0.2), Color.green.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Amount", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                }
                .frame(height: 160)
                .chartXScale(domain: xDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(ColorTheme.secondaryText.opacity(0.2))
                        AxisTick()
                            .foregroundStyle(ColorTheme.secondaryText.opacity(0.2))
                        AxisValueLabel(format: .dateTime.day().weekday(), centered: true)
                            .foregroundStyle(ColorTheme.secondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(ColorTheme.secondaryText.opacity(0.2))
                        AxisValueLabel()
                            .foregroundStyle(ColorTheme.secondaryText)
                    }
                }
            } else {
                Text("no_profit_data".localizedString)
                    .font(.footnote)
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .padding(16)
        .cardStyle()
    }
}

private struct CategoryBreakdownCard: View {
    let stats: [CategoryStat]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("spending_breakdown".localizedString)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(ColorTheme.primaryText)

            if stats.isEmpty {
                Text("no_expenses_period".localizedString)
                    .font(.footnote)
                    .foregroundColor(ColorTheme.secondaryText)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 16) {
                    ForEach(stats) { stat in
                        CategoryBreakdownRow(stat: stat)
                    }
                }
            }
        }
        .padding(16)
        .cardStyle()
    }
}

private struct CategoryBreakdownRow: View {
    let stat: CategoryStat

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 12) {
                    Circle()
                        .fill(ColorTheme.categoryColor(for: stat.key))
                        .frame(width: 12, height: 12)
                    Text(stat.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(ColorTheme.primaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(stat.amount.asCurrency())
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.primaryText)
                    Text("\(stat.percent, format: .number.precision(.fractionLength(1)))%")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }

            GeometryReader { proxy in
                let width = proxy.size.width * CGFloat(max(stat.percent / 100.0, 0))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ColorTheme.background)
                        .frame(height: 6)
                    
                    Capsule()
                        .fill(ColorTheme.categoryColor(for: stat.key))
                        .frame(width: max(width, 6), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

private struct RecentExpenseRow: View {
    @ObservedObject var expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(ColorTheme.categoryColor(for: expense.category ?? "").opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: expense.categoryIcon)
                    .font(.headline)
                    .foregroundColor(ColorTheme.categoryColor(for: expense.category ?? ""))
            }

            VStack(alignment: .leading, spacing: 4) {
                let description = expense.expenseDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
                Text((description?.isEmpty == false ? description : nil) ?? expense.categoryTitle)
                    .font(.body.weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText)
                    .lineLimit(1)

                Text(expense.vehicleSubtitle)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(expense.amountDecimal.asCurrency())
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)
                
                Text(expense.dateString)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }
        }
        .padding(12)
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 2)
    }
}

// MARK: - Extensions & Helpers




private enum DashboardFormatter {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

extension Expense {
    var amountDecimal: Decimal {
        amount?.decimalValue ?? 0
    }

    var categoryTitle: String {
        switch category ?? "" {
        case "vehicle": return "Vehicle"
        case "personal": return "Personal"
        case "employee": return "Employee"
        default: return "Other"
        }
    }

    var categoryIcon: String {
        switch category ?? "" {
        case "vehicle": return "fuelpump"
        case "personal": return "person"
        case "employee": return "briefcase"
        default: return "tag"
        }
    }

    var vehicleTitle: String {
        let make = vehicle?.make ?? ""
        let model = vehicle?.model ?? ""
        let title = [make, model].filter { !$0.isEmpty }.joined(separator: " ")
        
        if !title.isEmpty {
            return title
        }
        
        // Use the user's name if this is a general expense (no vehicle)
        if let userName = user?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !userName.isEmpty {
            return userName
        }
        
        return "Any Vehicle"
    }

    var vehicleSubtitle: String {
        if let vehicle {
            var components: [String] = []
            let name = [vehicle.make, vehicle.model]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !name.isEmpty {
                components.append(name)
            }
            if let vin = vehicle.vin?.trimmingCharacters(in: .whitespacesAndNewlines), !vin.isEmpty {
                components.append(vin)
            }
            if !components.isEmpty {
                return components.joined(separator: " • ")
            }
        }
        // For non-vehicle expenses, show user name if available
        if let userName = user?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !userName.isEmpty {
            return userName
        }
        return "No vehicle linked"
    }

    var timeString: String {
        guard let timestamp = createdAt ?? updatedAt else { return "--" }
        return DashboardFormatter.time.string(from: timestamp)
    }

    var dateString: String {
        guard let date else { return "--" }
        return DashboardFormatter.date.string(from: date)
    }
}

private extension DashboardView {
    var dashboardList: some View {
        List {
            financialOverviewSection
            analyticsSection
            todaysExpensesSection
            summarySection
            recentExpensesSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listSectionSpacing(20)
        .padding(.bottom, 90) // Ensure content clears tab bar
        .background(ColorTheme.background)
        .refreshable {
            if case .signedIn(let user) = sessionStore.status {
                await cloudSyncManager.manualSync(user: user)
                viewModel.fetchFinancialData(range: selectedRange)
            }
        }
    }
}

// MARK: - Detail Sheet



struct OrganizationSwitcherView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var showingCreateSheet = false
    @State private var newOrgName = ""
    @State private var isCreating = false
    @State private var createError: String?

    var body: some View {
        Menu {
            if sessionStore.organizations.isEmpty {
                Text("No organizations yet")
            } else {
                ForEach(sessionStore.organizations) { org in
                    Button {
                        Task { await sessionStore.switchOrganization(to: org.organization_id) }
                    } label: {
                        HStack {
                            Text(org.organization_name)
                            Spacer()
                            Text(org.role.capitalized)
                                .foregroundColor(.secondary)
                            if org.organization_id == sessionStore.activeOrganizationId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Create Business") {
                showingCreateSheet = true
            }
            .disabled(!isSignedIn)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sessionStore.activeOrganizationName ?? "Select Business")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(ColorTheme.primaryText)
                        .lineLimit(1)
                    if let role = sessionStore.activeOrganizationRole {
                        Text(role.capitalized)
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(ColorTheme.cardBackground)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        }
        .sheet(isPresented: $showingCreateSheet) {
            NavigationView {
                Form {
                    Section(header: Text("Business Name")) {
                        TextField("Enter business name", text: $newOrgName)
                            .autocapitalization(.words)
                    }

                    if let createError {
                        Section {
                            Text(createError)
                                .foregroundColor(.red)
                        }
                    }

                    Button(isCreating ? "Creating..." : "Create") {
                        Task {
                            isCreating = true
                            defer { isCreating = false }
                            do {
                                let newId = try await sessionStore.createOrganization(name: newOrgName)
                                await sessionStore.switchOrganization(to: newId)
                                showingCreateSheet = false
                                newOrgName = ""
                                createError = nil
                            } catch {
                                createError = error.localizedDescription
                            }
                        }
                    }
                    .disabled(newOrgName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
                .navigationTitle("Create Business")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingCreateSheet = false
                            newOrgName = ""
                            createError = nil
                        }
                    }
                }
            }
        }
    }

    private var isSignedIn: Bool {
        if case .signedIn = sessionStore.status { return true }
        return false
    }
}



// MARK: - Loading View

private extension DashboardView {
    var dashboardLoadingView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Skeleton cards for financial overview
                HStack(spacing: 12) {
                    skeletonCard
                    skeletonCard
                    skeletonCard
                }
                
                HStack(spacing: 12) {
                    skeletonCard
                    skeletonCard
                    skeletonCard
                }
                
                // Skeleton for summary cards
                VStack(spacing: 16) {
                    skeletonSummaryCard
                    skeletonSummaryCard
                }
                
                // Skeleton for expenses
                VStack(spacing: 12) {
                    ForEach(0..<3) { _ in
                        skeletonExpenseRow
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }
    
    var skeletonCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(ColorTheme.secondaryBackground.opacity(0.5))
                    .frame(width: 28, height: 28)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(ColorTheme.secondaryBackground.opacity(0.5))
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(ColorTheme.secondaryBackground.opacity(0.5))
                    .frame(height: 20)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shimmering()
    }
    
    var skeletonSummaryCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(ColorTheme.secondaryBackground.opacity(0.5))
                    .frame(height: 14)
                    .frame(maxWidth: 120)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(ColorTheme.secondaryBackground.opacity(0.5))
                    .frame(height: 32)
                    .frame(maxWidth: 150)
            }
            
            RoundedRectangle(cornerRadius: 4)
                .fill(ColorTheme.secondaryBackground.opacity(0.3))
                .frame(height: 220)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shimmering()
    }
    
    var skeletonExpenseRow: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 24)
                .fill(ColorTheme.secondaryBackground.opacity(0.5))
                .frame(width: 48, height: 48)
            
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(ColorTheme.secondaryBackground.opacity(0.5))
                    .frame(height: 18)
                    .frame(maxWidth: 150)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(ColorTheme.secondaryBackground.opacity(0.5))
                    .frame(height: 14)
                    .frame(maxWidth: 200)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(ColorTheme.secondaryBackground.opacity(0.5))
                    .frame(height: 20)
                    .frame(maxWidth: 80)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(ColorTheme.secondaryBackground.opacity(0.5))
                    .frame(height: 14)
                    .frame(maxWidth: 60)
            }
        }
        .padding(12)
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shimmering()
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geometry in
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.3),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geometry.size.width * 2)
                .offset(x: phase * geometry.size.width * 2 - geometry.size.width * 2)
            }
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        )
    }
}

extension View {
    func shimmering() -> some View {
        self.modifier(ShimmerModifier())
    }
}

// MARK: - Helpers



#Preview {
    DashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
