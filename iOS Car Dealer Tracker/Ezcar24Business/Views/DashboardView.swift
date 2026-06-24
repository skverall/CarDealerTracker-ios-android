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
    static let dashboardDidRequestExpensesTab = Notification.Name("dashboardDidRequestExpensesTab")
    static let currencySettingsDidComplete = Notification.Name("currencySettingsDidComplete")
}

enum DashboardDestination: String, Identifiable, Hashable {
    case assets, priorityInventory, cashAccounts, bankAccounts, creditAccounts, revenue, profit, sold, analytics, dataHealth
    var id: String { rawValue }
}

private enum DashboardSheetDestination: String, Identifiable {
    case inventoryRadar
    var id: String { rawValue }
}

private enum DashboardPalette {
    static let cash = Color(red: 0.20, green: 0.75, blue: 0.55)
    static let bank = Color(red: 0.25, green: 0.45, blue: 0.90)
    static let credit = Color(red: 0.95, green: 0.55, blue: 0.25)
    static let assets = Color(red: 0.12, green: 0.24, blue: 0.39)
    static let sold = Color(red: 0.25, green: 0.42, blue: 0.55)
    static let revenue = Color(red: 0.15, green: 0.25, blue: 0.40)
    static let profit = Color(red: 0.18, green: 0.48, blue: 0.34)
    static let loss = Color(red: 0.64, green: 0.28, blue: 0.30)
}

struct DashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @StateObject private var viewModel: DashboardViewModel
    @StateObject private var expenseEntryViewModel: ExpenseViewModel
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var permissionService = PermissionService.shared

    @State private var selectedRange: DashboardTimeRange = .week
    @State private var showingAddExpense: Bool = false
    @State private var showingSearch: Bool = false
    @State private var selectedExpense: Expense? = nil
    @State private var editingExpense: Expense? = nil
    @State private var presentedSheet: DashboardSheetDestination? = nil
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
        _viewModel = StateObject(wrappedValue: DashboardViewModel(context: context, initialRange: .week))
        _expenseEntryViewModel = StateObject(wrappedValue: ExpenseViewModel(context: context))
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                topBar
                if cloudSyncManager.isSyncing || offlineQueueCount > 0 {
                    syncStatusBar
                        .padding(.bottom, 10)
                }
                
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
        .sheet(isPresented: $showingSearch) {
            GlobalSearchView()
        }
        .adaptiveFormPresentation(isPresented: $showingAddExpense) {
            AddExpenseView(viewModel: expenseEntryViewModel)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(item: $selectedExpense) { expense in
            ExpenseDetailSheet(expense: expense)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .inventoryRadar:
                InventoryRadarSheet(
                    snapshot: viewModel.cockpitSnapshot,
                    canViewInventory: permissionService.can(.viewInventory),
                    canViewFinancials: permissionService.can(.viewFinancials),
                    onReviewAll: {
                        presentedSheet = nil
                        DispatchQueue.main.async {
                            navPath.append(.priorityInventory)
                        }
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .adaptiveFormPresentation(item: $editingExpense) { expense in
            AddExpenseView(viewModel: expenseEntryViewModel, editingExpense: expense)
                .environment(\.managedObjectContext, viewContext)
        }
        .onChange(of: selectedRange) { _, newValue in
            viewModel.fetchFinancialData(range: newValue)
        }
        .onChange(of: regionSettings.selectedRegion) { _, _ in
            if !navPath.isEmpty {
                navPath.removeAll()
            }
            viewModel.fetchFinancialData(range: selectedRange)
        }
        .onChange(of: regionSettings.selectedLanguage) { _, _ in
            viewModel.fetchFinancialData(range: selectedRange)
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
        case .priorityInventory:
            VehicleListView(focusAgingInventory: true, showNavigation: false)
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
        case .analytics:
            AnalyticsHubView()
        case .dataHealth:
            DataHealthView()
        }
    }
}

// MARK: - Top Navigation

private extension DashboardView {
    var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                OrganizationSwitcherView()
                
                Text("dashboard_title".localizedString)
                    .font(.title.weight(.heavy))
                    .foregroundColor(ColorTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if cloudSyncManager.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(ColorTheme.primary)
                }

                Button {
                    showingSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 36, height: 36)
                        .background(ColorTheme.cardBackground)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(colorScheme == .dark ? Color.clear : Color.white, lineWidth: colorScheme == .dark ? 0 : 1.5))
                        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                }

                Button {
                    NotificationCenter.default.post(name: .dashboardDidRequestAccount, object: nil)
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 36, height: 36)
                        .background(ColorTheme.cardBackground)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(colorScheme == .dark ? Color.clear : Color.white, lineWidth: colorScheme == .dark ? 0 : 1.5))
                        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
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
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            LinearGradient(
                                colors: [ColorTheme.primary.opacity(0.8), ColorTheme.primary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())
                        .shadow(color: ColorTheme.primary.opacity(0.4), radius: 4, x: 0, y: 2)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
    }

    var timeFiltersSection: some View {
        HStack(spacing: 6) {
            ForEach(DashboardTimeRange.allCases) { range in
                Button {
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0.03)) {
                        selectedRange = range
                    }
                } label: {
                    Text(range.displayLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .allowsTightening(true)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            Group {
                                if selectedRange == range {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [ColorTheme.primary.opacity(0.8), ColorTheme.primary],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                } else {
                                    Capsule()
                                        .fill(ColorTheme.secondaryBackground)
                                        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                                }
                            }
                        )
                        .foregroundColor(selectedRange == range ? .white : ColorTheme.primaryText.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
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
                Text(String(format: "• %lld queued".localizedString, Int64(offlineQueueCount)))
                    .font(.caption2)
                    .foregroundColor(ColorTheme.secondaryText)
            }

            Spacer()

            HStack(spacing: 14) {
                Button {
                    navPath.append(.dataHealth)
                } label: {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(offlineQueueCount > 0 ? ColorTheme.warning : ColorTheme.primary)
                }
                .buttonStyle(.plain)

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
            cloudSyncManager.showError("sign_in_to_sync".localizedString)
            return
        }
        await cloudSyncManager.fullSync(user: user)
        await refreshOfflineQueueCount()
    }
}

// MARK: - Sections

private extension DashboardView {
    var dealerCockpitSection: some View {
        Group {
            if permissionService.can(.viewInventory) || permissionService.can(.viewFinancials) {
                Section {
                    InventoryPulseCard(
                        snapshot: viewModel.cockpitSnapshot,
                        canViewInventory: permissionService.can(.viewInventory),
                        canViewFinancials: permissionService.can(.viewFinancials),
                        onTap: { presentedSheet = .inventoryRadar }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
    }

    var financialOverviewSection: some View {
        VStack(spacing: 24) {
            if permissionService.can(.viewFinancials) {
                    // 1. Account Balances
                    VStack(spacing: 12) {
                        Text("Account Balances".localizedString)
                            .font(.title3.weight(.bold))
                            .foregroundColor(ColorTheme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(spacing: 8) {
                            Button {
                                navPath.append(.cashAccounts)
                            } label: {
                                AccountBalanceCard(
                                    title: "payment_method_cash".localizedString,
                                    amount: viewModel.totalCash,
                                    icon: "banknote.fill",
                                    color: DashboardPalette.cash
                                )
                            }
                            .buttonStyle(.hapticScale)
                            
                            Button {
                                navPath.append(.bankAccounts)
                            } label: {
                                AccountBalanceCard(
                                    title: "bank".localizedString,
                                    amount: viewModel.totalBank,
                                    icon: "building.columns.fill",
                                    color: DashboardPalette.bank
                                )
                            }
                            .buttonStyle(.hapticScale)

                            Button {
                                navPath.append(.creditAccounts)
                            } label: {
                                AccountBalanceCard(
                                    title: "credit_card".localizedString,
                                    amount: viewModel.totalCredit,
                                    icon: "creditcard.fill",
                                    color: DashboardPalette.credit
                                )
                            }
                            .buttonStyle(.hapticScale)
                        }
                    }

                    // 2. Performance & Profit
                    VStack(spacing: 12) {
                        Text("Performance & Profit".localizedString)
                            .font(.title3.weight(.bold))
                            .foregroundColor(ColorTheme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(spacing: 12) {
                            Button {
                                navPath.append(.revenue)
                            } label: {
                                PerformanceCard(
                                    title: "total_revenue".localizedString,
                                    amount: viewModel.totalSalesIncome,
                                    icon: "arrow.up.right",
                                    color: Color(red: 0.2, green: 0.7, blue: 0.9),
                                    trendPoints: [] // Placeholder
                                )
                            }
                            .buttonStyle(.hapticScale)
                            
                            if permissionService.canViewVehicleProfit() {
                                Button {
                                    navPath.append(.profit)
                                } label: {
                                    PerformanceCard(
                                        title: "net_profit".localizedString,
                                        amount: viewModel.totalSalesProfit,
                                        icon: "dollarsign",
                                        color: viewModel.totalSalesProfit >= 0 ? DashboardPalette.cash : DashboardPalette.loss,
                                        trendPoints: selectedRange == .week ? viewModel.monthlyProfitTrendPoints : viewModel.profitTrendPoints
                                    )
                                }
                                .buttonStyle(.hapticScale)
                            }
                        }
                    }

                    // 3. Operations
                    VStack(spacing: 12) {
                        Text("Operations".localizedString)
                            .font(.title3.weight(.bold))
                            .foregroundColor(ColorTheme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(spacing: 12) {
                            Button {
                                navPath.append(.assets)
                            } label: {
                                OperationCard(
                                    title: "inventory".localizedString,
                                    amount: viewModel.inventoryOperationValue.asCurrencyCompact(),
                                    icon: "car.2.fill",
                                    color: DashboardPalette.assets
                                )
                            }
                            .buttonStyle(.hapticScale)

                            Button {
                                navPath.append(.sold)
                            } label: {
                                OperationCard(
                                    title: "vehicles_sold".localizedString,
                                    amount: "\(viewModel.soldCount)",
                                    icon: "checkmark.circle.fill",
                                    color: DashboardPalette.sold
                                )
                            }
                            .buttonStyle(.hapticScale)
                        }
                    }
                } else {
                    // Non-Financial View (Sales Person Mode)
                    VStack(spacing: 12) {
                        Text("Operations".localizedString)
                            .font(.title3.weight(.bold))
                            .foregroundColor(ColorTheme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                        HStack(spacing: 10) {
                             Button {
                                navPath.append(.assets)
                            } label: {
                                OperationCard(
                                    title: "vehicles".localizedString.capitalized,
                                    amount: "\(viewModel.totalAssetsCount)",
                                    icon: "car.2.fill",
                                    color: DashboardPalette.assets
                                )
                            }
                            .buttonStyle(.hapticScale)

                             Button {
                                navPath.append(.sold)
                            } label: {
                                OperationCard(
                                    title: "sold".localizedString,
                                    amount: "\(viewModel.soldCount)",
                                    icon: "checkmark.circle.fill",
                                    color: DashboardPalette.sold
                                )
                            }
                            .buttonStyle(.hapticScale)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    var analyticsSection: some View {
        Section {
            Button {
                navPath.append(.analytics)
            } label: {
                AnalyticsEntryCard(isProAccessActive: subscriptionManager.isProAccessActive)
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
                        NotificationCenter.default.post(name: .dashboardDidRequestExpensesTab, object: nil)
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

private struct InventoryPulseArc: View {
    let fraction: Double
    let strokeColor: Color
    let centerValue: String
    let centerLabel: String
    var showsCompletionRing: Bool = false

    @State private var displayedFraction: Double = 0
    @State private var showCompletion = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(showsCompletionRing ? 0.16 : 0.22), lineWidth: 7)

            if showsCompletionRing {
                Circle()
                    .stroke(Color.white.opacity(showCompletion ? 0.85 : 0.0), lineWidth: 7)
            }

            Circle()
                .trim(from: 0, to: showsCompletionRing ? 1.0 : displayedFraction)
                .stroke(
                    strokeColor,
                    style: StrokeStyle(lineWidth: showsCompletionRing ? 0 : 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text(centerValue)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text(centerLabel)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.72))
                    .textCase(.uppercase)
            }
        }
        .frame(width: 76, height: 76)
        .onAppear {
            animate(to: fraction)
            animateCompletion()
        }
        .onChange(of: fraction) { _, newValue in animate(to: newValue) }
    }

    private func animateCompletion() {
        guard showsCompletionRing else { return }
        if reduceMotion {
            showCompletion = true
        } else {
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                showCompletion = true
            }
        }
    }

    private func animate(to value: Double) {
        if reduceMotion {
            displayedFraction = value
        } else {
            withAnimation(.snappy(duration: 0.5, extraBounce: 0.04)) {
                displayedFraction = value
            }
        }
    }
}

private struct InventoryPulseCard: View {
    let snapshot: DashboardCockpitSnapshot
    let canViewInventory: Bool
    let canViewFinancials: Bool
    let onTap: () -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mood: PulseMood { snapshot.pulseMood }

    private func count(for bucket: String) -> Int {
        snapshot.ageBuckets.first(where: { $0.id == bucket })?.count ?? 0
    }

    private var headline: String {
        switch mood {
        case .calm:
            return "pulse_headline_calm".localizedString
        case .watch:
            return String(format: "pulse_headline_watch".localizedString, count(for: "aging") + count(for: "stale"))
        case .urgent:
            return String(format: "pulse_headline_urgent".localizedString, count(for: "critical"))
        }
    }

    private var subline: String {
        String(format: "pulse_subline".localizedString, snapshot.activeVehicleCount, snapshot.averageDaysInInventory)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("pulse_eyebrow".localizedString)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white.opacity(0.72))
                            .textCase(.uppercase)
                            .tracking(1.2)

                        Text(headline)
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .minimumScaleFactor(0.7)

                        Text(subline)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    InventoryPulseArc(
                        fraction: snapshot.pulseArcFraction,
                        strokeColor: mood.arcColor,
                        centerValue: "\(snapshot.averageDaysInInventory)",
                        centerLabel: "pulse_avg_days".localizedString,
                        showsCompletionRing: mood == .calm
                    )
                }

                compositionBar
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    mood.gradient
                    RadialGradient(
                        colors: [.white.opacity(0.16), .clear],
                        center: .topTrailing,
                        startRadius: 10,
                        endRadius: 220
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 10)
        }
        .buttonStyle(.hapticScale)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(.snappy(duration: 0.42, extraBounce: 0.06)) { appeared = true } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline). \(subline)")
        .accessibilityAddTraits(.isButton)
    }

    private var compositionBar: some View {
        GeometryReader { proxy in
            let fresh = count(for: "fresh")
            let aging = count(for: "aging")
            let stale = count(for: "stale") + count(for: "critical")
            let segments: [(Color, Int, String)] = [
                (ColorTheme.ageFresh, fresh, "pulse_fresh"),
                (ColorTheme.ageAging, aging, "pulse_aging"),
                (ColorTheme.ageStale, stale, "pulse_stale")
            ].filter { $0.1 > 0 }
            let total = max(1, segments.reduce(0) { $0 + $1.1 })
            let visibleCount = segments.count
            let spacing: CGFloat = visibleCount > 1 ? 4 : 0
            let usable = max(0, proxy.size.width - spacing * CGFloat(max(0, visibleCount - 1)))
            HStack(spacing: spacing) {
                ForEach(segments.indices, id: \.self) { index in
                    let (color, count, labelKey) = segments[index]
                    segment(color, count, total, usable, labelKey)
                }
            }
        }
        .frame(height: 30)
        .animation(reduceMotion ? nil : .snappy(duration: 0.38, extraBounce: 0.04), value: snapshot.ageBuckets.map(\.count))
    }

    private func segment(_ color: Color, _ count: Int, _ total: Int, _ width: CGFloat, _ labelKey: String) -> some View {
        let w = max(0, width * CGFloat(count) / CGFloat(total))
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color)
            .frame(width: w)
            .overlay(
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
            )
            .accessibilityLabel(String(format: "pulse_segment_accessibility".localizedString, labelKey.localizedString, count))
    }
}

private struct InventoryRadarSheet: View {
    let snapshot: DashboardCockpitSnapshot
    let canViewInventory: Bool
    let canViewFinancials: Bool
    let onReviewAll: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var freshCount: Int { snapshot.ageBuckets.first(where: { $0.id == "fresh" })?.count ?? 0 }
    private var agingCount: Int { snapshot.ageBuckets.first(where: { $0.id == "aging" })?.count ?? 0 }
    private var staleTotal: Int {
        (snapshot.ageBuckets.first(where: { $0.id == "stale" })?.count ?? 0)
            + (snapshot.ageBuckets.first(where: { $0.id == "critical" })?.count ?? 0)
    }

    private var storyTitle: String {
        String(format: staleTotal > 0
               ? "radar_story_title_stale".localizedString
               : "radar_story_title_ok".localizedString,
               staleTotal, snapshot.averageDaysInInventory)
    }

    private var totalTiedUp: Decimal {
        snapshot.riskVehicles.prefix(3).reduce(0) { $0 + $1.capital }
    }

    private var storyDetail: String {
        guard let oldest = snapshot.riskVehicles.first else {
            return String(format: "radar_story_detail_empty".localizedString, snapshot.averageDaysInInventory)
        }
        return String(format: "radar_story_detail".localizedString,
                      canViewFinancials ? totalTiedUp.asCurrencyCompact() : "",
                      oldest.daysInInventory)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                storyHeader
                ageDiagram
                oldestCarsSection
                if canViewInventory { reviewAllButton }
            }
            .padding(20)
        }
        .background(ColorTheme.background.ignoresSafeArea())
        .onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(.snappy(duration: 0.4, extraBounce: 0.05)) { appeared = true } }
        }
    }

    private var storyHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("radar_eyebrow".localizedString)
                .font(.caption.weight(.bold))
                .foregroundColor(ColorTheme.secondaryText)
                .textCase(.uppercase)
                .tracking(0.8)
            Text(storyTitle)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(ColorTheme.primaryText)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            Text(storyDetail)
                .font(.subheadline)
                .foregroundColor(ColorTheme.secondaryText)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
    }

    private var ageDiagram: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("radar_age_label".localizedString)
                .font(.caption.weight(.bold))
                .foregroundColor(ColorTheme.secondaryText)
                .textCase(.uppercase)

            GeometryReader { proxy in
                let total = max(1, freshCount + agingCount + staleTotal)
                let spacing: CGFloat = 4
                let usable = max(0, proxy.size.width - spacing * 2)
                HStack(spacing: spacing) {
                    ageBar(ColorTheme.ageFresh, freshCount, total, usable, spacing)
                    ageBar(ColorTheme.ageAging, agingCount, total, usable, spacing)
                    ageBar(ColorTheme.ageStale, staleTotal, total, usable, spacing)
                }
            }
            .frame(height: 36)

            HStack {
                axisLabel("0d"); Spacer(); axisLabel("30d"); Spacer(); axisLabel("60d"); Spacer(); axisLabel("90d+")
            }
        }
        .padding(14)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.gray.opacity(0.06), lineWidth: 1)
        )
    }

    private func ageBar(_ color: Color, _ count: Int, _ total: Int, _ width: CGFloat, _ spacing: CGFloat) -> some View {
        let w = max(0, width * CGFloat(count) / CGFloat(total))
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color)
            .frame(width: count > 0 ? w : 0)
            .overlay(count > 0 ? Text("\(count)").font(.caption.weight(.bold)).foregroundColor(.white) : nil)
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundColor(ColorTheme.tertiaryText)
    }

    private var oldestCarsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !snapshot.riskVehicles.isEmpty {
                Text("radar_oldest_label".localizedString)
                    .font(.caption.weight(.bold))
                    .foregroundColor(ColorTheme.secondaryText)
                    .textCase(.uppercase)
            }
            ForEach(Array(snapshot.riskVehicles.prefix(3).enumerated()), id: \.element.id) { index, vehicle in
                HStack(spacing: 12) {
                    Circle().fill(ColorTheme.ageStale).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(vehicle.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(ColorTheme.primaryText)
                            .lineLimit(1)
                        Text(String(format: "radar_car_detail".localizedString, vehicle.daysInInventory,
                                    canViewFinancials ? vehicle.capital.asCurrencyCompact() : ""))
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(ColorTheme.tertiaryText)
                }
                .padding(14)
                .background(ColorTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.gray.opacity(0.06), lineWidth: 1)
                )
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(Double(index) * 0.05), value: appeared)
            }
        }
    }

    private var reviewAllButton: some View {
        Button(action: onReviewAll) {
            HStack {
                Text("radar_review_all".localizedString)
                Image(systemName: "arrow.right")
            }
            .font(.subheadline.weight(.bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(ColorTheme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.hapticScale)
    }
}


extension DashboardCockpitTone {
    var color: Color {
        switch self {
        case .calm:
            return ColorTheme.success
        case .warning:
            return ColorTheme.warning
        case .urgent:
            return ColorTheme.danger
        case .opportunity:
            return ColorTheme.accent
        }
    }
}

private struct AccountBalanceCard: View {
    let title: String
    let amount: Decimal
    let icon: String
    let color: Color
    
    var body: some View {
        let amountParts = amountDisplayParts

        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                 Circle()
                     .fill(
                         LinearGradient(
                             colors: [color.opacity(0.8), color],
                             startPoint: .topLeading,
                             endPoint: .bottomTrailing
                         )
                     )
                     .frame(width: 34, height: 34)
                     .shadow(color: color.opacity(0.32), radius: 5, x: 0, y: 2)
                 Image(systemName: icon)
                     .font(.system(size: 15, weight: .bold))
                     .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ColorTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    if let prefix = amountParts.prefix {
                        Text(prefix)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(ColorTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }

                    Text(amountParts.value)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(ColorTheme.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                        .allowsTightening(true)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .shadow(color: Color.black.opacity(0.035), radius: 7, x: 0, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.gray.opacity(0.06), lineWidth: 1)
        )
    }

    private var amountDisplayParts: (prefix: String?, value: String) {
        let formatted = amount.asCurrencyCompact().replacingOccurrences(of: "\u{00a0}", with: " ")
        let parts = formatted.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            return (nil, formatted)
        }
        return (String(parts[0]), String(parts[1]))
    }
}

private struct PerformanceCard: View {
    let title: String
    let amount: Decimal
    let icon: String
    let color: Color
    var trendPoints: [TrendPoint] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundColor(Color.white.opacity(0.7))
                        .lineLimit(1)
                    
                    Text(amount.asCurrencyCompact())
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if !icon.isEmpty {
                    ZStack {
                        Circle()
                            .stroke(color.opacity(0.5), lineWidth: 2)
                            .background(Circle().fill(color.opacity(0.2)))
                            .frame(width: 28, height: 28)
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(color)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            
            if !trendPoints.isEmpty {
                Chart(trendPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Amount", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Amount", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.3), color.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .frame(height: 50)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .padding(.top, 10)
                .padding(.horizontal, 10)
            } else {
                Spacer().frame(height: 30) // placeholder if no trend
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.15, blue: 0.25), Color(red: 0.05, green: 0.08, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

private struct OperationCard: View {
    let title: String
    let amount: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(ColorTheme.secondaryText)
                    .lineLimit(1)
                
                Text(amount)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(ColorTheme.primaryText)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundColor(color)
                .padding(.trailing, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.gray.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct AnalyticsEntryCard: View {
    let isProAccessActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(
                     LinearGradient(
                         colors: [ColorTheme.purple, ColorTheme.primary],
                         startPoint: .topLeading,
                         endPoint: .bottomTrailing
                     )
                )
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(isProAccessActive ? "AI" : "Pro".localizedString)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(isProAccessActive ? ColorTheme.primary : ColorTheme.purple)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((isProAccessActive ? ColorTheme.primary : ColorTheme.purple).opacity(0.11), in: Capsule())

                    if !isProAccessActive {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(ColorTheme.purple)
                    }
                }

                Text("Your Insights Center".localizedString)
                    .font(.headline.weight(.heavy))
                    .foregroundColor(ColorTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                
                Text("Deep dive into your business performance.".localizedString)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            
            Spacer()
            
            Text((isProAccessActive ? "dashboard_ai_cta_open" : "dashboard_ai_cta_upgrade").localizedString)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                     LinearGradient(
                         colors: [ColorTheme.purple, ColorTheme.primary],
                         startPoint: .leading,
                         endPoint: .trailing
                     )
                )
                .clipShape(Capsule())
                .shadow(color: ColorTheme.purple.opacity(0.22), radius: 6, x: 0, y: 3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.gray.opacity(0.06), lineWidth: 1)
        )
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
        case "vehicle": return "vehicle".localizedStringFallback
        case "personal": return "personal".localizedStringFallback
        case "employee": return "employee".localizedStringFallback
        case "office": return "bills".localizedStringFallback
        case "marketing": return "marketing".localizedStringFallback
        default: return "other".localizedStringFallback
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
        
        return "any_vehicle".localizedStringFallback
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
        return "no_vehicle_linked".localizedStringFallback
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
    var dashboardIntroSection: some View {
        VStack(spacing: 6) {
            timeFiltersSection
            DrivingCarLane(laneHeight: 20)
        }
    }

    var dashboardList: some View {
        List {
            dashboardIntroSection
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .environment(\.defaultMinListRowHeight, 0)

            dealerCockpitSection
            financialOverviewSection
            analyticsSection
            todaysExpensesSection
            summarySection
            recentExpensesSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listSectionSpacing(20)
        .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? 24 : 90) // Ensure content clears tab bar (mobile)
        .background(ColorTheme.background)
        .refreshable {
            if case .signedIn(let user) = sessionStore.status {
                await cloudSyncManager.manualSync(user: user)
            }
        }
    }
}

// MARK: - Driving Car Lane

let dashboardCarEnabledKey = "dashboard_car_enabled"

private struct DrivingCarLane: View {
    var laneHeight: CGFloat = 20
    var duration: Double = 6.5

    @AppStorage(dashboardCarEnabledKey) private var enabled = true
    @AppStorage("dashboard_car_moving") private var moving = true
    @AppStorage("dashboard_car_progress") private var pausedProgress = 0.5

    @State private var runStart = Date()
    @State private var didStart = false
    @State private var showingParkingDialog = false

    var body: some View {
        Group {
            if enabled {
                lane
            } else {
                Color.clear.frame(height: 6)
            }
        }
        .confirmationDialog(
            "dashboard_car_parking_title".localizedString,
            isPresented: $showingParkingDialog,
            titleVisibility: .visible
        ) {
            Button("dashboard_car_parking_confirm".localizedString, role: .destructive) {
                parkCar()
            }

            Button("dashboard_car_parking_keep".localizedString, role: .cancel) {}
        } message: {
            Text("dashboard_car_parking_message".localizedString)
        }
    }

    private var lane: some View {
        let carHeight = max(laneHeight - 2, 10)
        let carWidth = carHeight * (112.0 / 72.0)
        let baseY = (laneHeight - carHeight) / 2
        return TimelineView(.animation) { timeline in
            GeometryReader { geo in
                let now = timeline.date
                let t = now.timeIntervalSinceReferenceDate
                let laneWidth = geo.size.width
                let travel = laneWidth + carWidth * 2
                let progress = moving
                    ? (now.timeIntervalSince(runStart) / duration).truncatingRemainder(dividingBy: 1)
                    : pausedProgress
                let x = -carWidth + CGFloat(progress) * travel
                let bob = moving ? CGFloat(sin(t * 7)) * 1.0 : CGFloat(sin(t * 3)) * 0.5
                let wheelAngle = progress * 44

                CartoonCar(wheelAngle: wheelAngle, moving: moving, time: t)
                    .frame(width: carWidth, height: carHeight)
                    .contentShape(Rectangle())
                    .offset(x: x, y: baseY + bob)
                    .onTapGesture { toggleMoving(at: progress) }
                    .onLongPressGesture(minimumDuration: 0.45) { requestParking() }
            }
        }
        .frame(height: laneHeight)
        .accessibilityHidden(true)
        .onAppear {
            guard !didStart else { return }
            didStart = true
            runStart = Date().addingTimeInterval(-pausedProgress * duration)
        }
    }

    private func toggleMoving(at progress: Double) {
        if moving {
            pausedProgress = progress
            moving = false
        } else {
            runStart = Date().addingTimeInterval(-pausedProgress * duration)
            moving = true
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func requestParking() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showingParkingDialog = true
    }

    private func parkCar() {
        enabled = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

private struct CartoonCar: View {
    var wheelAngle: Double = 0
    var moving: Bool = true
    var time: Double = 0

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 112
            let sy = size.height / 72
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
            func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rad: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy),
                     cornerSize: CGSize(width: rad * sx, height: rad * sy))
            }
            func ell(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: (cx - rx) * sx, y: (cy - ry) * sy, width: 2 * rx * sx, height: 2 * ry * sy))
            }

            let blue = Color(red: 0.15, green: 0.48, blue: 0.97)
            let blueDark = Color(red: 0.07, green: 0.30, blue: 0.82)
            let outline = Color(red: 0.07, green: 0.12, blue: 0.23)
            let glass = Color(red: 0.82, green: 0.92, blue: 1.0)
            let tire = Color(red: 0.15, green: 0.15, blue: 0.17)
            let hub = Color(red: 0.87, green: 0.89, blue: 0.93)
            let lw = 2.2 * min(sx, sy)

            // ground shadow
            ctx.fill(ell(56, 69, 42, 4), with: .color(.black.opacity(0.10)))

            if moving {
                // speed lines while driving
                for yy in [26.0, 40.0, 52.0] {
                    ctx.fill(rrect(0, yy - 1.2, 12, 2.4, 1.2), with: .color(blue.opacity(0.40)))
                }
            } else {
                // exhaust puffs while idling
                for i in 0..<3 {
                    let phase = (time * 0.5 + Double(i) * 0.34).truncatingRemainder(dividingBy: 1)
                    let px = max(1.0, 12 - phase * 11)
                    let py = 52 - phase * 7
                    let r = 1.6 + phase * 2.4
                    ctx.fill(ell(px, py, r, r), with: .color(.gray.opacity((1 - phase) * 0.35)))
                }
            }

            // body silhouette (facing right)
            var car = Path()
            car.move(to: pt(16, 57))
            car.addLine(to: pt(16, 42))
            car.addQuadCurve(to: pt(40, 18), control: pt(16, 24))
            car.addQuadCurve(to: pt(74, 18), control: pt(57, 11))
            car.addQuadCurve(to: pt(98, 40), control: pt(99, 21))
            car.addLine(to: pt(98, 50))
            car.addQuadCurve(to: pt(90, 57), control: pt(98, 56))
            car.closeSubpath()
            ctx.fill(car, with: .linearGradient(
                Gradient(colors: [blue, blueDark]),
                startPoint: pt(0, 16), endPoint: pt(0, 58)))
            ctx.stroke(car, with: .color(outline), lineWidth: lw)

            // roof gloss
            ctx.fill(ell(56, 21, 15, 3), with: .color(.white.opacity(0.22)))

            // windows
            let rearWindow = rrect(38, 24, 17, 12, 5)
            let frontWindow = rrect(60, 24, 15, 12, 5)
            ctx.fill(rearWindow, with: .color(glass))
            ctx.stroke(rearWindow, with: .color(outline), lineWidth: lw * 0.7)
            ctx.fill(frontWindow, with: .color(glass))
            ctx.stroke(frontWindow, with: .color(outline), lineWidth: lw * 0.7)

            // headlight (friendly round eye)
            let light = ell(92, 44, 4, 4.8)
            ctx.fill(light, with: .color(Color(red: 1.0, green: 0.95, blue: 0.70)))
            ctx.stroke(light, with: .color(outline), lineWidth: lw * 0.6)
            ctx.fill(ell(90.6, 42.6, 1.2, 1.2), with: .color(.white.opacity(0.9)))

            // door seam
            var door = Path()
            door.move(to: pt(57, 36))
            door.addLine(to: pt(57, 56))
            ctx.stroke(door, with: .color(blueDark.opacity(0.85)), lineWidth: lw * 0.7)

            // wheels
            for cx in [32.0, 84.0] {
                ctx.fill(ell(cx, 56, 11, 11), with: .color(tire))
                ctx.stroke(ell(cx, 56, 11, 11), with: .color(outline), lineWidth: lw)
                ctx.fill(ell(cx, 56, 5.5, 5.5), with: .color(hub))

                var spokes = Path()
                let center = pt(cx, 56)
                for k in 0..<4 {
                    let a = wheelAngle + Double(k) * .pi / 2
                    spokes.move(to: center)
                    spokes.addLine(to: CGPoint(x: center.x + CGFloat(cos(a)) * 5.5 * sx,
                                               y: center.y + CGFloat(sin(a)) * 5.5 * sy))
                }
                ctx.stroke(spokes, with: .color(Color(red: 0.55, green: 0.58, blue: 0.63)), lineWidth: lw * 0.7)
                ctx.fill(ell(cx, 56, 1.8, 1.8), with: .color(outline))
            }
        }
    }
}

// MARK: - Detail Sheet



struct OrganizationSwitcherView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var showingOrgSheet = false
    @State private var showingCreateSheet = false
    @State private var newOrgName = ""
    @State private var newOrgBusinessRegion: DealDeskBusinessRegionCode = .generic
    @State private var isCreating = false
    @State private var createError: String?

    var body: some View {
        Button {
            showingOrgSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "building.2.crop.circle.fill")
                    .foregroundColor(ColorTheme.primary)
                
                Text(sessionStore.activeOrganizationName ?? "Business")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(ColorTheme.secondaryText)
                    .lineLimit(1)
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundColor(ColorTheme.secondaryText.opacity(0.6))
            }
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showingOrgSheet) {
            NavigationStack {
                List {
                    Section {
                        if sessionStore.organizations.isEmpty {
                            Text("No organizations yet".localizedString)
                                .foregroundColor(ColorTheme.secondaryText)
                        } else {
                            ForEach(sessionStore.organizations) { org in
                                Button {
                                    showingOrgSheet = false
                                    // slight delay to allow sheet to close before switching org (avoids UI glitches)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        Task { await sessionStore.switchOrganization(to: org.organization_id) }
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(org.organization_name)
                                                .font(.body.weight(org.organization_id == sessionStore.activeOrganizationId ? .semibold : .regular))
                                                .foregroundColor(ColorTheme.primaryText)
                                            Text(org.role.capitalized)
                                                .font(.caption)
                                                .foregroundColor(ColorTheme.secondaryText)
                                        }
                                        Spacer()
                                        if org.organization_id == sessionStore.activeOrganizationId {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(ColorTheme.primary)
                                                .font(.title3)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    
                    Section {
                        Button {
                            showingOrgSheet = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showingCreateSheet = true
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                Text("Create Business".localizedString)
                            }
                            .foregroundColor(ColorTheme.primary)
                            .font(.body.weight(.medium))
                            .padding(.vertical, 2)
                        }
                        .disabled(!isSignedIn)
                    }
                }
                .navigationTitle("Select Business".localizedString)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close".localizedString) {
                            showingOrgSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.fraction(0.4), .medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingCreateSheet) {
            NavigationView {
                Form {
                    Section(header: Text("Business Name".localizedString)) {
                        TextField("Enter business name".localizedString, text: $newOrgName)
                            .autocapitalization(.words)
                    }

                    Section(header: Text("Business Region".localizedString)) {
                        Picker("Business Region".localizedString, selection: $newOrgBusinessRegion) {
                            ForEach(DealDeskBusinessRegionCode.allCases) { region in
                                Text(region.displayName).tag(region)
                            }
                        }
                        .pickerStyle(.menu)
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
                                let newId = try await sessionStore.createOrganization(
                                    name: newOrgName,
                                    businessRegionCode: newOrgBusinessRegion
                                )
                                await sessionStore.switchOrganization(to: newId)
                                showingCreateSheet = false
                                newOrgName = ""
                                newOrgBusinessRegion = .generic
                                createError = nil
                            } catch {
                                createError = error.localizedDescription
                            }
                        }
                    }
                    .disabled(newOrgName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
                .navigationTitle("Create Business".localizedString)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel".localizedString) {
                            showingCreateSheet = false
                            newOrgName = ""
                            newOrgBusinessRegion = .generic
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
