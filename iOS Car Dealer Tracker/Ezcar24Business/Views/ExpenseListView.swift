import SwiftUI
import UniformTypeIdentifiers

func expenseDisplayDateTime(_ expense: Expense) -> Date {
    let calendar = Calendar.current
    let expenseDate = expense.date ?? expense.createdAt ?? expense.updatedAt ?? .distantPast
    let explicitTime = calendar.dateComponents([.hour, .minute, .second], from: expenseDate)
    if explicitTime.hour != 0 || explicitTime.minute != 0 || explicitTime.second != 0 {
        return expenseDate
    }
    let createdTime = expense.createdAt ?? expense.updatedAt ?? expenseDate

    let dateComponents = calendar.dateComponents([.year, .month, .day], from: expenseDate)
    let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: createdTime)

    var combined = DateComponents()
    combined.year = dateComponents.year
    combined.month = dateComponents.month
    combined.day = dateComponents.day
    combined.hour = timeComponents.hour
    combined.minute = timeComponents.minute
    combined.second = timeComponents.second

    return calendar.date(from: combined) ?? expenseDate
}


struct VehicleFilterMenu: View {
    @ObservedObject var viewModel: ExpenseViewModel
    private var title: String {
        if let v = viewModel.selectedVehicle {
            return v.displayName
        } else {
            return "all".localizedString
        }
    }
    var body: some View {
        Menu {
            Button("all_vehicles".localizedString) {
                viewModel.selectedVehicle = nil
                viewModel.fetchExpenses()
            }
            Divider()
            ForEach(Array(viewModel.vehicles.enumerated()), id: \.element.objectID) { _, vehicle in
                Button {
                    viewModel.selectedVehicle = vehicle
                    viewModel.fetchExpenses()
                } label: {
                    Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "car.fill")
                    .font(.caption)
                Text(title)
                    .font(.footnote)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .opacity(0.6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .foregroundColor(ColorTheme.secondaryText)
            .background(Capsule().fill(Color.gray.opacity(0.1)))
            .contentShape(Capsule())
        }
    }
}

struct UserFilterMenu: View {
    @ObservedObject var viewModel: ExpenseViewModel
    private var title: String {
        viewModel.selectedUser == nil ? "all".localizedString : "\(viewModel.selectedUser?.name ?? "selected".localizedString)"
    }
    var body: some View {
        Menu {
            Button("all_users".localizedString) {
                viewModel.selectedUser = nil
                viewModel.fetchExpenses()
            }
            Divider()
            ForEach(Array(viewModel.users.enumerated()), id: \.element.objectID) { _, user in
                Button {
                    viewModel.selectedUser = user
                    viewModel.fetchExpenses()
                } label: {
                    Text(user.name ?? "")
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.caption)
                Text(title)
                    .font(.footnote)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .opacity(0.6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .foregroundColor(ColorTheme.secondaryText)
            .background(Capsule().fill(Color.gray.opacity(0.1)))
            .contentShape(Capsule())
        }
    }
}

//
//  ExpenseListView.swift
//  Ezcar24Business
//
//  Expense tracking and listing
//

private struct CategoryBar: View {
    let ratio: CGFloat
    let color: Color
    @State private var animatedRatio: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(color.opacity(0.2))
            GeometryReader { gp in
                let fillWidth = gp.size.width * animatedRatio
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color)
                        .frame(width: fillWidth, height: 8)
                    if fillWidth >= 36 { // show % only if width allows
                        Text("\(Int((ratio * 100).rounded()))%")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                    }
                }
            }
        }
        .frame(height: 8)
        .frame(maxWidth: .infinity)
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { animatedRatio = max(0.02, min(1, ratio)) } }
        .onChange(of: ratio) { _, newVal in
            withAnimation(.easeOut(duration: 0.6)) { animatedRatio = max(0.02, min(1, newVal)) }
        }
    }
}


struct ExpenseListView: View {
    private enum GroupMode: String, CaseIterable { case date, category }

    @StateObject private var viewModel: ExpenseViewModel
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @ObservedObject private var permissionService = PermissionService.shared

    private var canDeleteRecords: Bool {
        if case .signedIn = sessionStore.status {
            return permissionService.can(.deleteRecords)
        }
        return true
    }
    
    @State private var showingAddExpense = false
    @State private var showingEdit = false
    @State private var editingExpense: Expense? = nil
    @State private var selectedExpense: Expense? = nil

    @State private var periodFilter: DashboardTimeRange = .all

    @State private var searchText: String = ""
    private let presetStartDate: Date?
    @State private var appliedPreset: Bool = false
    @State private var showShare: Bool = false
    @State private var exportURL: URL? = nil
    @State private var collapsedDateGroups: Set<String> = []
    @State private var groupMode: GroupMode = .date


    @State private var collapsedCategories: Set<String> = []
    @State private var showFilters: Bool = true

    // Quick edit sheets
    @State private var quickEditExpense: Expense? = nil
    @State private var showCategorySheet: Bool = false
    @State private var showVehicleSheet: Bool = false
    @State private var showUserSheet: Bool = false


    // CSV Import
    @State private var showImporter: Bool = false

    init(presetStartDate: Date? = nil) {
        self.presetStartDate = presetStartDate
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: ExpenseViewModel(context: context))
    }
    // Extracted to help the compiler type-check faster




    private var vehicleUserFilters: some View {
        HStack(spacing: 12) {
            VehicleFilterMenu(viewModel: viewModel)
            UserFilterMenu(viewModel: viewModel)
        }
    }

    // Compact filters bar
    private var periodTitle: String {
        switch periodFilter {
        case .all: return "all".localizedString
        case .today: return "today".localizedString
        case .week: return "this_week".localizedString
        case .month: return "this_month".localizedString
        case .threeMonths: return "last_3_months".localizedString
        case .sixMonths: return "last_6_months".localizedString
        }
    }
    private var categoryTitle: String {
        let c = viewModel.selectedCategory
        switch c.lowercased() {
        case "all": return "all".localizedString
        case "vehicle": return "vehicle".localizedString
        case "personal": return "personal".localizedString
        case "employee": return "employee".localizedString
        case "office": return "bills".localizedString
        default: return "category".localizedString
        }
    }
    private var groupTitle: String { groupMode == .date ? "Date" : "Category" }
    private var filtersAreDefault: Bool {
        periodFilter == .all &&
        viewModel.selectedCategory.lowercased() == "all" &&
        viewModel.selectedVehicle == nil &&
        viewModel.selectedUser == nil &&
        groupMode == .date
    }

    private var filtersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Period menu
                Menu {
                    Button("all".localizedString) { periodFilter = .all }
                    Button("today".localizedString) { periodFilter = .today }
                    Button("week".localizedString) { periodFilter = .week }
                    Button("month".localizedString) { periodFilter = .month }
                    Button("last_3_months".localizedString) { periodFilter = .threeMonths }
                    Button("last_6_months".localizedString) { periodFilter = .sixMonths }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.caption)
                        Text(periodTitle)
                            .font(.footnote)
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2).opacity(0.6)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 28)
                    .foregroundColor(ColorTheme.secondaryText)
                    .background(Capsule().fill(Color.gray.opacity(0.1)))
                }

                // Category menu
                Menu {
                    Button("all".localizedString) { viewModel.selectedCategory = "all"; viewModel.fetchExpenses() }
                    Button("vehicle".localizedString) { viewModel.selectedCategory = "vehicle"; viewModel.fetchExpenses() }
                    Button("personal".localizedString) { viewModel.selectedCategory = "personal"; viewModel.fetchExpenses() }
                    Button("employee".localizedString) { viewModel.selectedCategory = "employee"; viewModel.fetchExpenses() }
                    Button("bills".localizedString) { viewModel.selectedCategory = "office"; viewModel.fetchExpenses() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill").font(.caption)
                        Text(categoryTitle)
                            .font(.footnote)
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2).opacity(0.6)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 28)
                    .foregroundColor(ColorTheme.secondaryText)
                    .background(Capsule().fill(Color.gray.opacity(0.1)))
                }

                // Group menu
                Menu {
                    Button("date".localizedString) { groupMode = .date }
                    Button("category".localizedString) { groupMode = .category }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2").font(.caption)
                        Text(groupTitle)
                            .font(.footnote)
                        Image(systemName: "chevron.down").font(.caption2).opacity(0.6)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 28)
                    .foregroundColor(ColorTheme.secondaryText)
                    .background(Capsule().fill(Color.gray.opacity(0.1)))
                }

                Button {
                    resetFilters()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill").font(.caption)
                        Text("clear".localizedString)
                            .font(.footnote)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 28)
                    .foregroundColor(ColorTheme.secondaryText)
                    .background(Capsule().fill(Color.gray.opacity(0.1)))
                }
                .disabled(filtersAreDefault)
                .opacity(filtersAreDefault ? 0.5 : 1)

                // Vehicle & User menus (existing styled pills)
                vehicleUserFilters
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    private func mutateExpense<T>(_ action: () throws -> T) -> T? {
        do {
            return try action()
        } catch {
            print("Expense mutation failed: \(error)")
            return nil
        }
    }
    
    private func deleteExpenseFromCloud(_ id: UUID?, account: FinancialAccount?) {
        guard let id, case .signedIn(let user) = sessionStore.status else { return }
        Task {
            let dealerId = CloudSyncEnvironment.currentDealerId ?? user.id
            await cloudSyncManager.deleteExpense(id: id, dealerId: dealerId)
            if let account {
                await cloudSyncManager.upsertFinancialAccount(account, dealerId: dealerId)
            }
        }
    }

    @ViewBuilder
    private func expenseListRow(_ expense: Expense) -> some View {
        Button {
            selectedExpense = expense
        } label: {
            ExpenseRow(expense: expense)
        }
        .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if canDeleteRecords {
                    Button(role: .destructive) {
                        let account = expense.account
                        if let deletedId = (mutateExpense { try viewModel.deleteExpense(expense) } ?? nil) {
                            deleteExpenseFromCloud(deletedId, account: account)
                        }
                    } label: {
                        Label("delete".localizedString, systemImage: "trash")
                    }
                }

                Button {
                    editingExpense = expense
                    showingEdit = true
                } label: {
                    Label("edit".localizedString, systemImage: "pencil")
                }
                .tint(ColorTheme.primary)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if canDeleteRecords {
                    Button(role: .destructive) {
                        let account = expense.account
                        if let deletedId = (mutateExpense { try viewModel.deleteExpense(expense) } ?? nil) {
                            deleteExpenseFromCloud(deletedId, account: account)
                        }
                    } label: {
                        Label("delete".localizedString, systemImage: "trash")
                    }
                }
                Button("category".localizedString) {
                    quickEditExpense = expense
                    showCategorySheet = true
                }.tint(.blue)
                Button("vehicle".localizedString) {
                    quickEditExpense = expense
                    showVehicleSheet = true
                }.tint(.indigo)
                Button("User".localizedString) {
                    quickEditExpense = expense
                    showUserSheet = true
                }.tint(.teal)
            }
    }

    private func categoryDisplayName(_ category: String) -> String {
        switch category.lowercased() {
        case "vehicle": return "Vehicle"
        case "personal": return "Personal"
        case "employee": return "Employee"
        case "office": return "Bills"
        default: return category.capitalized
        }
    }

    private func resetFilters() {
        periodFilter = .all
        viewModel.selectedCategory = "all"
        viewModel.selectedVehicle = nil
        viewModel.selectedUser = nil
        groupMode = .date
        viewModel.startDate = nil
        viewModel.endDate = nil
        viewModel.fetchExpenses()
    }




    var body: some View {
        let _ = regionSettings.selectedRegion
        let _ = regionSettings.selectedLanguage
        let expensePresentation = viewModel.presentationSnapshot
        NavigationStack {
            VStack(spacing: 0) {
                // Filters bar
                if showFilters {
                    filtersBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .background(ColorTheme.background)
                }

                // Expense List
                List {
                        // Summary analytics (moved here to scroll away)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("category_summary".localizedString)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(ColorTheme.primaryText)

                            ForEach(expensePresentation.categoryGroups) { group in
                                HStack {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(ColorTheme.categoryColor(for: group.key))
                                            .frame(width: 6, height: 6)

                                        Text(categoryDisplayName(group.key))
                                            .font(.caption)
                                            .foregroundColor(ColorTheme.primaryText)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text(group.subtotal.asCurrency())
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(ColorTheme.primaryText)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)


                        if viewModel.expenses.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "dollarsign.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(ColorTheme.secondaryText)
                                Text("no_expenses_found".localizedString)
                                    .font(.headline)
                                    .foregroundColor(ColorTheme.secondaryText)
                                Text("add_first_expense".localizedString)
                                    .font(.subheadline)
                                    .foregroundColor(ColorTheme.tertiaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .listRowBackground(Color.clear)
                        }


                        if groupMode == .date {
                            ForEach(expensePresentation.dateGroups) { group in
                                // Header row for date bucket
                                HStack(spacing: 10) {
                                    Button(action: {
                                        if collapsedDateGroups.contains(group.key) {
                                            collapsedDateGroups.remove(group.key)
                                        } else {
                                            collapsedDateGroups.insert(group.key)
                                        }
                                    }) {
                                        Image(systemName: collapsedDateGroups.contains(group.key) ? "chevron.right" : "chevron.down")
                                            .font(.caption)
                                            .foregroundColor(ColorTheme.secondaryText)
                                    }
                                    Text(group.key)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(ColorTheme.primaryText)
                                    Spacer()
                                    let s = expensePresentation.dateSummaries[group.key] ?? .zero
                                    Text("\(s.count) · \(s.subtotal.asCurrency())")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(ColorTheme.primary)
                                }
                                .padding(.horizontal, 2)
                                .listRowBackground(Color.clear)

                        if !collapsedDateGroups.contains(group.key) {
                            ForEach(group.items, id: \.objectID) { expense in
                                    expenseListRow(expense)
                                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                        .listRowBackground(Color.clear)
                            }
                        }
                    }
                } else {
                    ForEach(expensePresentation.categoryGroups) { group in
                                // Non-sticky header row for the category
                                HStack(spacing: 10) {
                                    Button(action: {
                                        if collapsedCategories.contains(group.key) {
                                            collapsedCategories.remove(group.key)
                                        } else {
                                            collapsedCategories.insert(group.key)
                                        }
                                    }) {
                                        Image(systemName: collapsedCategories.contains(group.key) ? "chevron.right" : "chevron.down")
                                            .font(.caption)
                                            .foregroundColor(ColorTheme.secondaryText)
                                    }
                                    CategoryBadge(category: group.key)
                                    Spacer()

                                    let s = expensePresentation.categorySummaries[group.key] ?? .zero
                                    Text("\(s.count) · \(s.subtotal.asCurrency())")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(ColorTheme.primary)
                                }
                                .padding(.horizontal, 2)
                                .listRowBackground(Color.clear)

                                if !collapsedCategories.contains(group.key) {
                                    ForEach(group.items, id: \.objectID) { expense in
                                        expenseListRow(expense)
                                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                            .listRowBackground(Color.clear)
                                    }
                                }
                            }
                        }
                        // Total at bottom
                        Section {
                            HStack {
                                Text("total".localizedString)
                                    .font(.headline)
                                    .foregroundColor(ColorTheme.primaryText)
                                Spacer()
                                Text(expensePresentation.totalExpenseAmount.asCurrency())
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(ColorTheme.primaryText)
                            }
                            .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 12, trailing: 16))
                            .listRowBackground(Color.clear)
                        }

                    }
                    .listStyle(.plain)
                    .background(ColorTheme.secondaryBackground)
            }
            .background(ColorTheme.secondaryBackground)
            .navigationTitle("expenses".localizedString)
            .onChange(of: periodFilter) { oldValue, newValue in
                let cal = Calendar.current
                switch newValue {
                case .today:
                    viewModel.startDate = cal.startOfDay(for: Date())
                    viewModel.endDate = Date()
                case .week:
                    viewModel.startDate = cal.date(byAdding: .day, value: -7, to: Date())
                    viewModel.endDate = Date()
                case .month:
                    viewModel.startDate = cal.date(byAdding: .day, value: -30, to: Date())
                    viewModel.endDate = Date()
                case .threeMonths:
                    viewModel.startDate = cal.date(byAdding: .month, value: -3, to: Date())
                    viewModel.endDate = Date()
                case .sixMonths:
                    viewModel.startDate = cal.date(byAdding: .month, value: -6, to: Date())
                    viewModel.endDate = Date()
                case .all:
                    viewModel.startDate = nil
                    viewModel.endDate = nil
                }
                viewModel.fetchExpenses()
            }
            .refreshable {
                viewModel.fetchExpenses()
            }
            .sheet(item: $selectedExpense) { expense in
                ExpenseDetailSheet(expense: expense)
                    .presentationDetents([.medium, .large])
            }

            .sheet(isPresented: $showCategorySheet) {
                if let exp = quickEditExpense {
                    NavigationStack {
                        List {
                            Button("vehicle".localizedString) {
                                mutateExpense {
                                    try viewModel.updateExpense(
                                        exp,
                                        amount: exp.amount?.decimalValue ?? 0,
                                        date: exp.date ?? Date(),
                                        description: exp.expenseDescription ?? "",
                                        category: "vehicle",
                                        vehicle: exp.vehicle,
                                        user: exp.user,
                                        account: exp.account
                                    )
                                }
                                showCategorySheet = false
                            }
                            Button("personal".localizedString) {
                                mutateExpense {
                                    try viewModel.updateExpense(
                                        exp,
                                        amount: exp.amount?.decimalValue ?? 0,
                                        date: exp.date ?? Date(),
                                        description: exp.expenseDescription ?? "",
                                        category: "personal",
                                        vehicle: exp.vehicle,
                                        user: exp.user,
                                        account: exp.account
                                    )
                                }
                                showCategorySheet = false
                            }
                            Button("employee".localizedString) {
                                mutateExpense {
                                    try viewModel.updateExpense(
                                        exp,
                                        amount: exp.amount?.decimalValue ?? 0,
                                        date: exp.date ?? Date(),
                                        description: exp.expenseDescription ?? "",
                                        category: "employee",
                                        vehicle: exp.vehicle,
                                        user: exp.user,
                                        account: exp.account
                                    )
                                }
                                showCategorySheet = false
                            }
                        }
                        .navigationTitle("change_category".localizedString)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("close".localizedString) { showCategorySheet = false } } }
                    }
                }
            }
            .sheet(isPresented: $showVehicleSheet) {
                if let exp = quickEditExpense {
                    NavigationStack {
                        List {
                            Button("none".localizedString) {
                                mutateExpense {
                                    try viewModel.updateExpense(
                                        exp,
                                        amount: exp.amount?.decimalValue ?? 0,
                                        date: exp.date ?? Date(),
                                        description: exp.expenseDescription ?? "",
                                        category: exp.category ?? "",
                                        vehicle: nil,
                                        user: exp.user,
                                        account: exp.account
                                    )
                                }
                                showVehicleSheet = false
                            }
                            ForEach(viewModel.vehicles, id: \.objectID) { v in
                                Button("\(v.make ?? "") \(v.model ?? "")") {
                                    mutateExpense {
                                        try viewModel.updateExpense(
                                            exp,
                                            amount: exp.amount?.decimalValue ?? 0,
                                            date: exp.date ?? Date(),
                                            description: exp.expenseDescription ?? "",
                                            category: exp.category ?? "",
                                            vehicle: v,
                                            user: exp.user,
                                            account: exp.account
                                        )
                                    }
                                    showVehicleSheet = false
                                }
                            }
                        }
                        .navigationTitle("Assign Vehicle")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("close".localizedString) { showVehicleSheet = false } } }
                    }
                }
            }
            .sheet(isPresented: $showUserSheet) {
                if let exp = quickEditExpense {
                    NavigationStack {
                        List {
                            Button("none".localizedString) {
                                mutateExpense {
                                    try viewModel.updateExpense(
                                        exp,
                                        amount: exp.amount?.decimalValue ?? 0,
                                        date: exp.date ?? Date(),
                                        description: exp.expenseDescription ?? "",
                                        category: exp.category ?? "",
                                        vehicle: exp.vehicle,
                                        user: nil,
                                        account: exp.account
                                    )
                                }
                                showUserSheet = false
                            }
                            ForEach(viewModel.users, id: \.objectID) { u in
                                Button(u.name ?? "") {
                                    mutateExpense {
                                        try viewModel.updateExpense(
                                            exp,
                                            amount: exp.amount?.decimalValue ?? 0,
                                            date: exp.date ?? Date(),
                                            description: exp.expenseDescription ?? "",
                                            category: exp.category ?? "",
                                            vehicle: exp.vehicle,
                                            user: u,
                                            account: exp.account
                                        )
                                    }
                                    showUserSheet = false
                                }
                            }
                        }
                        .navigationTitle("Assign User")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("close".localizedString) { showUserSheet = false } } }
                    }
                }
            }

            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        let newValue = !showFilters
                        withAnimation(.easeInOut) {
                            showFilters = newValue
                        }
                        if !newValue {
                            resetFilters()
                        }
                    } label: {
                        Label(
                            showFilters ? "Hide Filters" : "Filters",
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button("Date ↓") { viewModel.sortOption = .dateDesc; viewModel.fetchExpenses() }
                        Button("Date ↑") { viewModel.sortOption = .dateAsc; viewModel.fetchExpenses() }
                        Button("Amount ↓") { viewModel.sortOption = .amountDesc; viewModel.fetchExpenses() }
                        Button("Amount ↑") { viewModel.sortOption = .amountAsc; viewModel.fetchExpenses() }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showImporter = true }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("Import CSV")
                    .accessibilityLabel("Import expenses from CSV")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        let csv = viewModel.csvStringForCurrentExpenses()
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("expenses-\(Int(Date().timeIntervalSince1970)).csv")
                        do {
                            try csv.write(to: url, atomically: true, encoding: .utf8)
                            exportURL = url
                            showShare = true
                        } catch {
                            print("Failed to write CSV: \(error)")
                        }
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Export CSV")
                    .accessibilityLabel("Export expenses as CSV")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if permissionService.can(.viewExpenses) {
                        Button(action: { showingAddExpense = true }) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingEdit) {
                AddExpenseView(viewModel: viewModel, editingExpense: editingExpense)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .text]) { result in
                switch result {
                case .success(let url):
                    viewModel.importCSV(from: url)
                case .failure(let error):
                    print("Import failed: \(error)")
                }
            }

            .navigationTitle("expenses".localizedString)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search expenses")
            .onChange(of: searchText) { _, newValue in
                viewModel.updateSearchQuery(newValue)
            }
            .onAppear {
                if !appliedPreset, let d = presetStartDate {
                    let cal = Calendar.current
                    let start = cal.startOfDay(for: d)
                    viewModel.startDate = start
                    // Try to match preset to a period
                    if cal.isDateInToday(start) {
                        periodFilter = .today
                    } else {
                        periodFilter = .all
                    }
                    viewModel.fetchExpenses()
                    appliedPreset = true
                }
            }
            .sheet(isPresented: $showShare) {
                if let url = exportURL {
                    ActivityView(activityItems: [url])
                }
            }

        }
    }
}

struct ExpenseRow: View {
    @ObservedObject var expense: Expense
    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM, h:mm a"
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: description and amount
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(expense.expenseDescription ?? "No description")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(ColorTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text((expense.amount?.decimalValue ?? 0).asCurrency())
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(ColorTheme.primaryText)
            }

            // Metadata row: category, vehicle, user
            HStack(spacing: 6) {
                CategoryBadge(category: expense.category ?? "")

                if let vehicle = expense.vehicle {
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.tertiaryText)
                    Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if let user = expense.user, let name = user.name, !name.isEmpty {
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.tertiaryText)
                    Text(name)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                if expense.receiptPath != nil {
                    Image(systemName: "paperclip")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.tertiaryText)
                }

                // Show date from expense.date combined with time from createdAt
                Text(expenseDisplayDateTime(expense), formatter: Self.shortDateFormatter)
                    .font(.caption2)
                    .foregroundColor(ColorTheme.tertiaryText)
            }
        }
        .padding(.vertical, 10) // Reduced padding
        .padding(.horizontal, 12) // Reduced padding
        .cardStyle()
    }
}

struct CategoryBadge: View {
    let category: String

    var categoryText: String {
        switch category.lowercased() {
        case "vehicle":
            return "Vehicle"
        case "personal":
            return "Personal"
        case "employee":
            return "Employee"
        default:
            return category.capitalized
        }
    }

    var body: some View {
        Text(categoryText)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ColorTheme.categoryColor(for: category))
            .cornerRadius(6)
    }
}

@MainActor struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// Modern, HIG-friendly expenses layout tailored for Dubai dealers.
struct DealerExpenseDashboardView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSessionState: AppSessionState
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @ObservedObject private var permissionService = PermissionService.shared
    @StateObject private var viewModel: ExpenseViewModel
    @State private var showingAddExpense = false
    @State private var editingExpense: Expense? = nil
    @State private var searchText = ""

    private var canDeleteRecords: Bool {
        if case .signedIn = sessionStore.status {
            return permissionService.can(.deleteRecords)
        }
        return true
    }

    private func deleteExpenseFromCloud(_ id: UUID?, account: FinancialAccount?) {
        guard let id, case .signedIn(let user) = sessionStore.status else { return }
        Task {
            let dealerId = CloudSyncEnvironment.currentDealerId ?? user.id
            await cloudSyncManager.deleteExpense(id: id, dealerId: dealerId)
            if let account {
                await cloudSyncManager.upsertFinancialAccount(account, dealerId: dealerId)
            }
        }
    }

    private func mutateExpense<T>(_ action: () throws -> T) -> T? {
        do {
            return try action()
        } catch {
            print("Expense mutation failed: \(error)")
            return nil
        }
    }

    private let chipBackground = ColorTheme.background

    var showNavigation: Bool = true

    init(showNavigation: Bool = true) {
        self.showNavigation = showNavigation
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: ExpenseViewModel(context: context))
    }

    var body: some View {
        let _ = regionSettings.selectedRegion
        let _ = regionSettings.selectedLanguage
        Group {
            if showNavigation {
                NavigationStack {
                    content
                        .toolbar(.hidden, for: .navigationBar)
                }
            } else {
                content
            }
        }
    }

    var content: some View {
        let expensePresentation = viewModel.presentationSnapshot
        return ZStack(alignment: .bottomTrailing) {
                ColorTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    
                    // Filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            vehicleChip
                            userChip
                            categoryChip
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background(ColorTheme.background)

                    List {
                        if expensePresentation.dateGroups.isEmpty {
                            emptyState
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(expensePresentation.dateGroups) { group in
                                Section {
                                    ForEach(group.items, id: \.objectID) { expense in
                                        Button {
                                            editingExpense = expense
                                        } label: {
                                            CompactExpenseRow(expense: expense)
                                        }
                                        .buttonStyle(.plain)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                        .listRowBackground(Color.clear)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            if canDeleteRecords {
                                                Button(role: .destructive) {
                                                    let account = expense.account
                                                    if let deletedId = (mutateExpense { try viewModel.deleteExpense(expense) } ?? nil) {
                                                        deleteExpenseFromCloud(deletedId, account: account)
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
                                            .tint(ColorTheme.primary)
                                        }
                                    }
                                } header: {
                                    HStack {
                                        Text(group.key)
                                            .font(.body)
                                            .fontWeight(.bold)
                                            .foregroundColor(ColorTheme.primaryText)
                                        Spacer()
                                        Text(group.subtotal.asCurrency())
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(ColorTheme.primary)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(ColorTheme.background)
                                    .listRowInsets(EdgeInsets())
                                }
                            }
                            
                            Spacer(minLength: 90)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(ColorTheme.background)
                    .refreshable {
                        if case .signedIn(let user) = sessionStore.status {
                            await cloudSyncManager.manualSync(user: user)
                            viewModel.fetchExpenses()
                        }
                    }
                }

                fab
                    .padding(.trailing, 24)
                    .padding(.bottom, 90)
            }

            .sheet(isPresented: $showingAddExpense) {
                AddExpenseView(viewModel: viewModel)
            }
            .sheet(isPresented: Binding(get: { editingExpense != nil }, set: { if !$0 { editingExpense = nil } })) {
                if let expense = editingExpense {
                    AddExpenseView(viewModel: viewModel, editingExpense: expense)
                }
            }
            .onAppear {
                viewModel.refreshFiltersIfNeeded()
                viewModel.fetchExpenses()
            }
            .searchable(text: $searchText, placement: .automatic, prompt: Text("search_expenses_placeholder".localizedString))
            .onChange(of: searchText) { _, newValue in
                viewModel.updateSearchQuery(newValue)
            }
        }



    private var header: some View {
        let expensePresentation = viewModel.presentationSnapshot
        return VStack(spacing: 20) {
            HStack(alignment: .center) {
                Text("expenses".localizedString)
                    .font(.largeTitle.weight(.bold))
                    .foregroundColor(ColorTheme.primaryText)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            // Premium Hero Card
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("EZCAR24")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .italic()
                            .foregroundColor(.white.opacity(0.9))
                        
                        // Credit Card EMV Chip
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.9, green: 0.8, blue: 0.6), Color(red: 0.7, green: 0.55, blue: 0.35)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                            
                            // Chip circuit lines simulation
                            VStack(spacing: 5) {
                                ForEach(0..<3) { _ in
                                    Divider().background(Color.black.opacity(0.3))
                                }
                            }
                            .padding(.horizontal, 6)
                        }
                        .frame(width: 42, height: 30)
                    }
                    
                    Spacer()
                    
                    if let delta = expensePresentation.weekDeltaPercent {
                        HStack(spacing: 4) {
                            Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                            Text(String(format: "%.0f%%", abs(delta)))
                        }
                        .font(.footnote.weight(.heavy))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    } else {
                        // Visa/Mastercard style overlapping circles
                        HStack(spacing: -12) {
                            Circle().fill(Color.red.opacity(0.8)).frame(width: 28, height: 28)
                            Circle().fill(Color.orange.opacity(0.8)).frame(width: 28, height: 28)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("this_week".localizedString.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .tracking(2)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                    
                    Text(expensePresentation.currentWeekTotal.asCurrencyCompact())
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
            .padding(24)
            .aspectRatio(1.586, contentMode: .fit)
            .background(
                ZStack {
                    // Base deep obsidian/blue gradient
                    LinearGradient(
                        colors: [Color(red: 0.1, green: 0.15, blue: 0.25), Color(red: 0.05, green: 0.08, blue: 0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    // Subtle glowing mesh accents
                    Circle()
                        .fill(Color(red: 0.2, green: 0.5, blue: 1.0).opacity(0.3))
                        .frame(width: 200, height: 200)
                        .blur(radius: 60)
                        .offset(x: 120, y: -80)
                    
                    Circle()
                        .fill(Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.2))
                        .frame(width: 150, height: 150)
                        .blur(radius: 50)
                        .offset(x: -80, y: 80)
                        
                    // Watermark / pattern to look physical
                    Image(systemName: "globe.americas.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white.opacity(0.04))
                        .scaleEffect(1.6)
                        .offset(x: 50, y: 40)
                        .blendMode(.screen)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.25), radius: 15, x: 0, y: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 16)
        .background(ColorTheme.background)
    }

    // MARK: - Chips

    private var vehicleChip: some View {
        Menu {
            Button("all_vehicles".localizedString) {
                viewModel.selectedVehicle = nil
                viewModel.fetchExpenses()
            }
            Divider()
            ForEach(viewModel.vehicles, id: \.objectID) { vehicle in
                Button {
                    viewModel.selectedVehicle = vehicle
                    viewModel.fetchExpenses()
                } label: {
                    Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                }
            }
        } label: {
            filterChip(title: vehicleChipTitle, isActive: viewModel.selectedVehicle != nil)
        }
    }

    private var userChip: some View {
        Menu {
            Button("all_employees".localizedString) {
                viewModel.selectedUser = nil
                viewModel.fetchExpenses()
            }
            Divider()
            ForEach(viewModel.users, id: \.objectID) { user in
                Button {
                    viewModel.selectedUser = user
                    viewModel.fetchExpenses()
                } label: {
                    Text(user.name ?? "")
                }
            }
        } label: {
            filterChip(title: userChipTitle, isActive: viewModel.selectedUser != nil)
        }
    }

    private var categoryChip: some View {
        Menu {
            Button("all_categories".localizedString) {
                viewModel.selectedCategory = "all"
                viewModel.fetchExpenses()
            }
            Button("vehicle".localizedString) {
                viewModel.selectedCategory = "vehicle"
                viewModel.fetchExpenses()
            }
            Button("employee".localizedString) {
                viewModel.selectedCategory = "employee"
                viewModel.fetchExpenses()
            }
            Button("personal".localizedString) {
                viewModel.selectedCategory = "personal"
                viewModel.fetchExpenses()
            }
        } label: {
            filterChip(title: categoryChipTitle, isActive: viewModel.selectedCategory.lowercased() != "all")
        }
    }

    private func filterChip(title: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .opacity(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isActive ? ColorTheme.primary : ColorTheme.cardBackground)
        .foregroundColor(isActive ? .white : ColorTheme.secondaryText)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(isActive ? ColorTheme.primary : Color.gray.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: isActive ? ColorTheme.primary.opacity(0.3) : Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
    }

    // MARK: - Compact Expense Row
    
    private struct CompactExpenseRow: View {
        @ObservedObject var expense: Expense
        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM, h:mm a"
            formatter.locale = Locale(identifier: "en_AE")
            formatter.timeZone = .autoupdatingCurrent
            return formatter
        }()
        
        var body: some View {
            let subtitle = subtitleText(for: expense)
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(ColorTheme.categoryColor(for: expense.category ?? "").opacity(0.12))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: iconName(for: expense))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(ColorTheme.categoryColor(for: expense.category ?? ""))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryText(for: expense))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.primaryText)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(subtitle)
                            .lineLimit(1)
                        if !subtitle.isEmpty {
                            Text("•")
                                .opacity(0.5)
                        }
                        Text(expenseDisplayDateTime(expense), formatter: Self.dateFormatter)
                    }
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text((expense.amount?.decimalValue ?? 0).asCurrency())
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(ColorTheme.primaryText)

                    HStack(spacing: 4) {
                        if expense.receiptPath != nil {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                                .foregroundColor(ColorTheme.secondaryText)
                        }
                        CategoryBadge(category: expense.category ?? "")
                            .scaleEffect(0.8, anchor: .trailing)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(ColorTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.gray.opacity(0.08), lineWidth: 1)
            )
        }
        
        private func iconName(for expense: Expense) -> String {
            let category = expense.category?.lowercased() ?? ""
            switch category {
            case "vehicle": return "car.fill"
            case "employee": return "person.fill"
            case "personal": return "bag.fill"
            default: return expense.vehicle == nil ? "doc.text.fill" : "car.fill"
            }
        }
        
        private func primaryText(for expense: Expense) -> String {
            let desc = (expense.expenseDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !desc.isEmpty { return desc }
            return expense.category?.capitalized ?? "expense_fallback".localizedString
        }
        
        private func subtitleText(for expense: Expense) -> String {
            var parts: [String] = []
            if let v = expense.vehicle {
                let make = v.make ?? ""
                let model = v.model ?? ""
                let combined = "\(make) \(model)".trimmingCharacters(in: .whitespaces)
                if !combined.isEmpty { parts.append(combined) }
            }
            if let user = expense.user?.name, !user.isEmpty {
                parts.append(user)
            }
            return parts.isEmpty ? "no_details".localizedString : parts.joined(separator: " • ")
        }
    }

    private var fab: some View {
        Button {
            showingAddExpense = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(ColorTheme.primary))
                .shadow(color: ColorTheme.primary.opacity(0.4), radius: 10, y: 5)
        }
        .accessibilityLabel("add_expense".localizedString)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(ColorTheme.tertiaryText.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("no_expenses_found".localizedString)
                    .font(.headline)
                    .foregroundColor(ColorTheme.secondaryText)
                
                Text("no_expenses_help_text".localizedString)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.tertiaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
    }

    private var vehicleChipTitle: String {
        guard let v = viewModel.selectedVehicle else { return "vehicle".localizedString }
        let make = v.make ?? ""
        let model = v.model ?? ""
        let combined = "\(make) \(model)".trimmingCharacters(in: .whitespaces)
        return combined.isEmpty ? "selected".localizedString : combined
    }

    private var userChipTitle: String {
        viewModel.selectedUser?.name ?? "employee".localizedString
    }


    private var categoryChipTitle: String {
        let title = viewModel.selectedCategory
        if title.lowercased() == "all" { return "category".localizedString }
        return title.capitalized
    }

    private func iconName(for expense: Expense) -> String {
        let category = expense.category?.lowercased() ?? ""
        switch category {
        case "vehicle":
            return "car.fill"
        case "employee":
            return "person.fill"
        case "personal":
            return "bag.fill"
        default:
            return expense.vehicle == nil ? "doc.text.fill" : "car.fill"
        }
    }

    private func primaryText(for expense: Expense) -> String {
        let desc = (expense.expenseDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !desc.isEmpty { return desc }
        return expense.category?.capitalized ?? "Expense"
    }

    private func subtitleText(for expense: Expense) -> String {
        var parts: [String] = []
        
        // Vehicle Make/Model
        if let v = expense.vehicle {
            let make = v.make ?? ""
            let model = v.model ?? ""
            let combined = "\(make) \(model)".trimmingCharacters(in: .whitespaces)
            if !combined.isEmpty { parts.append(combined) }
        }
        
        // User
        if let user = expense.user?.name, !user.isEmpty {
            parts.append(user)
        }
        
        // VIN
        if let vin = expense.vehicle?.vin, !vin.isEmpty {
            parts.append(vin)
        }
        
        return parts.isEmpty ? "No details" : parts.joined(separator: " • ")
    }
}


#Preview {
    ExpenseListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

#Preview("Dealer expense dashboard") {
    DealerExpenseDashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
