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
    case assets, cashAccounts, bankAccounts, revenue, profit, sold, allExpenses
    var id: String { rawValue }
}

struct DashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @StateObject private var viewModel: DashboardViewModel
    @StateObject private var expenseEntryViewModel: ExpenseViewModel

    @State private var selectedRange: DashboardTimeRange = .week
    @State private var showingAddExpense: Bool = false
    @State private var showingSearch: Bool = false
    @State private var selectedExpense: Expense? = nil
    @State private var editingExpense: Expense? = nil
    @State private var navPath: [DashboardDestination] = []
    @State private var offlineQueueCount: Int = 0

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
                    List {
                        financialOverviewSection
                        todaysExpensesSection
                        summarySection
                        recentExpensesSection
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .listSectionSpacing(20)
                    .listSectionSpacing(20)
                    .background(ColorTheme.background)
                    .refreshable {
                        if case .signedIn(let user) = sessionStore.status {
                            await cloudSyncManager.manualSync(user: user)
                            viewModel.fetchFinancialData(range: selectedRange)
                        }
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
        case .cashAccounts, .bankAccounts:
            FinancialAccountsView()
        case .revenue, .profit:
            SalesListView(showNavigation: false)
        case .sold:
            VehicleListView(presetStatus: "sold", showNavigation: false)
        case .allExpenses:
            ExpenseListView()
        }
    }
}

// MARK: - Top Navigation

private extension DashboardView {
    var topBar: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                    Text("dashboard_title".localizedString)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(ColorTheme.primaryText)
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
                        Button {
                            showingAddExpense = true
                        } label: {
                            Label("add_expense".localizedString, systemImage: "creditcard")
                        }
                        
                        Button {
                            navPath.append(.assets)
                        } label: {
                            Label("view_vehicles".localizedString, systemImage: "car")
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
        let count = items.filter { $0.dealerId == user.id }.count
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
                // First row: Assets, Cash, Bank
                HStack(spacing: 12) {
                    Button {
                        navPath.append(.assets)
                    } label: {
                        FinancialCard(
                            title: "total_assets".localizedString,
                            amount: viewModel.totalAssets,
                            icon: "building.columns.fill",
                            color: .blue,
                            isHero: true
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        navPath.append(.cashAccounts)
                    } label: {
                        FinancialCard(
                            title: "payment_method_cash".localizedString,
                            amount: viewModel.totalCash,
                            icon: "banknote.fill",
                            color: .green
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        navPath.append(.bankAccounts)
                    } label: {
                        FinancialCard(
                            title: "bank".localizedString,
                            amount: viewModel.totalBank,
                            icon: "creditcard.fill",
                            color: .purple
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                // Second row: Income and Profit from Sales
                HStack(spacing: 12) {
                    Button {
                        navPath.append(.revenue)
                    } label: {
                        FinancialCard(
                            title: "total_revenue".localizedString,
                            amount: viewModel.totalSalesIncome,
                            icon: "chart.line.uptrend.xyaxis",
                            color: .orange
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        navPath.append(.profit)
                    } label: {
                        FinancialCard(
                            title: "net_profit".localizedString,
                            amount: viewModel.totalSalesProfit,
                            icon: "dollarsign.circle.fill",
                            color: viewModel.totalSalesProfit >= 0 ? .green : .red,
                            isHero: true
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        navPath.append(.sold)
                    } label: {
                        FinancialCard(
                            title: "sold".localizedString,
                            amount: Decimal(viewModel.soldCount), // Match the Sold list count to avoid Sales-vs-Status mismatch
                            icon: "checkmark.circle.fill",
                            color: .cyan,
                            isCount: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .listRowInsets(EdgeInsets())
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
    var todaysExpensesSection: some View {
        Group {
            if !viewModel.todaysExpenses.isEmpty {
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
        [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ]
    }

    var summarySection: some View {
        Section {
            VStack(spacing: 16) {
                SummaryOverviewCard(
                    totalSpent: viewModel.totalExpenses,
                    changePercent: viewModel.periodChangePercent,
                    trendPoints: viewModel.trendPoints,
                    range: selectedRange
                )

                ProfitOverviewCard(
                    totalProfit: selectedRange == .week ? viewModel.monthlyNetProfit : viewModel.periodSalesProfit,
                    trendPoints: selectedRange == .week ? viewModel.monthlyProfitTrendPoints : viewModel.profitTrendPoints,
                    range: selectedRange == .week ? .month : selectedRange
                )

                CategoryBreakdownCard(stats: viewModel.categoryStats)
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    var recentExpensesSection: some View {
        Group {
            Section {
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
                                Button(role: .destructive) {
                                    do {
                                        let deletedId = try expenseEntryViewModel.deleteExpense(expense)
                                        viewModel.fetchFinancialData(range: selectedRange)
                                        if let id = deletedId, case .signedIn(let user) = sessionStore.status {
                                            Task {
                                                await cloudSyncManager.deleteExpense(id: id, dealerId: user.id)
                                            }
                                        }
                                    } catch {
                                        print("Failed to delete expense: \(error)")
                                    }
                                } label: {
                                    Label("delete".localizedString, systemImage: "trash")
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
            .textCase(nil)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            
            // Bottom Spacer for Tab Bar
            Section {
                Color.clear.frame(height: 100)
                    .listRowBackground(Color.clear)
            }
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
}

// MARK: - Components

struct GlobalSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var searchText = ""
    @State private var vehicleResults: [Vehicle] = []
    @State private var clientResults: [Client] = []
    @State private var expenseResults: [Expense] = []
    
    var body: some View {
        NavigationStack {
            List {
                if !vehicleResults.isEmpty {
                    Section("Vehicles") {
                        ForEach(vehicleResults) { vehicle in
                            VehicleRow(vehicle: vehicle)
                        }
                    }
                }
                
                if !clientResults.isEmpty {
                    Section("Clients") {
                        ForEach(clientResults) { client in
                            ClientRow(client: client)
                        }
                    }
                }
                
                if !expenseResults.isEmpty {
                    Section("Expenses") {
                        ForEach(expenseResults) { expense in
                            RecentExpenseRow(expense: expense)
                        }
                    }
                }
                
                if !searchText.isEmpty && vehicleResults.isEmpty && clientResults.isEmpty && expenseResults.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .searchable(text: $searchText, prompt: "Search vehicles, clients, expenses...")
            .onChange(of: searchText) { _, newValue in
                performSearch(query: newValue)
            }
            .navigationTitle("search".localizedString)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("done".localizedString) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func performSearch(query: String) {
        guard !query.isEmpty else {
            vehicleResults = []
            clientResults = []
            expenseResults = []
            return
        }
        
        
        // Search Vehicles
        let vehicleReq: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
        vehicleReq.predicate = NSPredicate(format: "make CONTAINS[cd] %@ OR model CONTAINS[cd] %@ OR vin CONTAINS[cd] %@", query, query, query)
        vehicleReq.fetchLimit = 5
        
        // Search Clients
        let clientReq: NSFetchRequest<Client> = Client.fetchRequest()
        clientReq.predicate = NSPredicate(format: "name CONTAINS[cd] %@ OR phone CONTAINS[cd] %@", query, query)
        clientReq.fetchLimit = 5
        
        // Search Expenses
        let expenseReq: NSFetchRequest<Expense> = Expense.fetchRequest()
        expenseReq.predicate = NSPredicate(format: "expenseDescription CONTAINS[cd] %@ OR category CONTAINS[cd] %@", query, query)
        expenseReq.fetchLimit = 5
        
        do {
            vehicleResults = try viewContext.fetch(vehicleReq)
            clientResults = try viewContext.fetch(clientReq)
            expenseResults = try viewContext.fetch(expenseReq)
        } catch {
            print("Search failed: \(error)")
        }
    }
}

private struct VehicleRow: View {
    let vehicle: Vehicle
    var body: some View {
        VStack(alignment: .leading) {
            Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                .font(.headline)
            Text(vehicle.vin ?? "")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct ClientRow: View {
    let client: Client
    var body: some View {
        VStack(alignment: .leading) {
            Text(client.name ?? "")
                .font(.headline)
            Text(client.phone ?? "")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct FinancialCard: View {
    let title: String
    let amount: Decimal
    let icon: String
    let color: Color
    var isCount: Bool = false
    var isHero: Bool = false
    var trendText: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundColor(isHero ? .white : color)
                    .frame(width: 28, height: 28)
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
                        .font(isHero ? .headline.weight(.bold) : .subheadline.weight(.bold))
                        .foregroundColor(isHero ? .white : ColorTheme.primaryText)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                } else {
                    Text(amount.asCurrency())
                        .font(isHero ? .headline.weight(.bold) : .subheadline.weight(.bold))
                        .foregroundColor(isHero ? .white : ColorTheme.primaryText)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if isHero {
                    LinearGradient(
                        colors: [color, color.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    ColorTheme.secondaryBackground
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: isHero ? color.opacity(0.3) : Color.black.opacity(0.03), radius: isHero ? 8 : 4, x: 0, y: isHero ? 4 : 2)
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
                            .frame(width: 36, height: 36)
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
                        .font(.title3.weight(.bold))
                        .foregroundColor(ColorTheme.primaryText)
                    
                    Text(expense.vehicleTitle)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            .background(ColorTheme.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyTodayCard: View {
    let addAction: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
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
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
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
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("total_spend".localizedString + " (\(range.displayLabel))")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(totalSpent.asCurrency())
                            .font(.system(size: 32, weight: .bold, design: .rounded))
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
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.9)
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
                .frame(height: 220)
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
        .padding(24)
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
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
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("net_profit".localizedString + " (\(range.displayLabel))")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                    
                    Text(totalProfit.asCurrency())
                        .font(.system(size: 32, weight: .bold, design: .rounded))
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
                .frame(height: 220)
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
        .padding(24)
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
    }
}

private struct CategoryBreakdownCard: View {
    let stats: [CategoryStat]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
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
        .padding(24)
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
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
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(ColorTheme.categoryColor(for: expense.category ?? "").opacity(0.1))
                    .frame(width: 48, height: 48)
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
        .padding(16)
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
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

private extension Expense {
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
        return title.isEmpty ? "Any Vehicle" : title
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

// MARK: - Detail Sheet

private struct ExpenseDetailSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    let expense: Expense
    @State private var commentDraft: String
    @State private var isSaving: Bool = false
    @State private var saveError: String? = nil
    @State private var showSavedToast: Bool = false

    init(expense: Expense) {
        self.expense = expense
        _commentDraft = State(initialValue: expense.expenseDescription ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        let description = expense.expenseDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
                        Text((description?.isEmpty == false ? description : nil) ?? expense.categoryTitle)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(expense.amountDecimal.asCurrency())
                            .font(.largeTitle.weight(.bold))
                            .foregroundColor(ColorTheme.primaryText)
                    }
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 10) {
                        DetailRow(title: "Category", value: expense.categoryTitle, icon: "tag")
                        DetailRow(title: "Vehicle", value: expense.vehicleSubtitle, icon: "car.fill")
                        DetailRow(title: "Date", value: expense.dateString, icon: "calendar")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Comment")
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)

                        ZStack(alignment: .topLeading) {
                            if commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Add a note (what was this expense for?)")
                                    .font(.body)
                                    .foregroundColor(ColorTheme.secondaryText.opacity(0.6))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            }

                            TextEditor(text: $commentDraft)
                                .frame(minHeight: 90)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                        }
                        .background(ColorTheme.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if let saveError {
                        Text(saveError)
                            .font(.caption)
                            .foregroundColor(ColorTheme.danger)
                    } else if showSavedToast {
                        Text("Saved")
                            .font(.caption)
                            .foregroundColor(ColorTheme.success)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            
            // Sticky Footer
            VStack {
                Button {
                    saveComment()
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save Comment")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(ColorTheme.primary)
                .disabled(isSaving)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .background(ColorTheme.background)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: -4)
        }
        .background(ColorTheme.background)
        .onDisappear {
            let trimmed = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let current = (expense.expenseDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !isSaving, trimmed != current {
                // Background save if dismissed without clicking button
                saveComment(shouldDismiss: false)
            }
        }
    }

    private func saveComment(shouldDismiss: Bool = true) {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        showSavedToast = false

        let trimmed = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        expense.expenseDescription = trimmed.isEmpty ? nil : trimmed
        expense.updatedAt = Date()

        do {
            try viewContext.save()
            showSavedToast = true

            if let dealerId = CloudSyncEnvironment.currentDealerId {
                Task {
                    await CloudSyncManager.shared?.upsertExpense(expense, dealerId: dealerId)
                }
            }

            if shouldDismiss {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    dismiss()
                }
            }
        } catch {
            viewContext.rollback()
            saveError = "Failed to save"
            print("Failed to save expense comment: \(error)")
        }

        isSaving = false
    }
}

private struct DetailRow: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(ColorTheme.primary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
                Text(value)
                    .font(.body)
                    .foregroundColor(ColorTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}



// MARK: - Helpers



#Preview {
    DashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
