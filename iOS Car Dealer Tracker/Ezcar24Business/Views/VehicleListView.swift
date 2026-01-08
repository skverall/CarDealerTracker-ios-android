//
//  VehicleListView.swift
//  Ezcar24Business
//
//  Vehicle inventory list with filtering
//

import SwiftUI

struct VehicleListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel: VehicleViewModel
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSessionState: AppSessionState
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    
    @State private var showingAddVehicle = false
    @State private var showingPaywall = false
    private let presetStatus: String?
    private let showNavigation: Bool
    @State private var presetApplied: Bool = false
    @State private var editingVehicle: Vehicle?
    @State private var vehicleToDelete: Vehicle?
    @State private var showDeleteAlert: Bool = false
    @State private var sellingVehicle: Vehicle?
    @State private var sellPriceText: String = ""
    @State private var sellDate: Date = Date()
    @State private var buyerName: String = ""
    @State private var buyerPhone: String = ""
    @State private var paymentMethod: String = "Cash"

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FinancialAccount.accountType, ascending: true)],
        animation: .default
    )
    private var accounts: FetchedResults<FinancialAccount>
    @State private var sellAccount: FinancialAccount? = nil
    
    let paymentMethods = ["Cash", "Bank Transfer", "Cheque", "Finance", "Other"]
    
    private var isSignedIn: Bool {
        if case .signedIn = sessionStore.status { return true }
        return false
    }

    private var canSaveQuickSale: Bool {
        guard
            sellAccount != nil,
            !buyerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let sp = Decimal(string: sellPriceText),
            sp > 0
        else { return false }
        return true
    }



    init(presetStatus: String? = nil, showNavigation: Bool = true) {
        self.presetStatus = presetStatus
        self.showNavigation = showNavigation
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: VehicleViewModel(context: context))
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
                ColorTheme.secondaryBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    displayModePicker
                    VehicleStatusDashboard(viewModel: viewModel)
                    searchAndFilterHeader
                    vehicleList
                }
            }
            .navigationTitle("vehicles".localizedString)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if !subscriptionManager.isProAccessActive && !subscriptionManager.isCheckingStatus && viewModel.vehicles.count >= 3 {
                            handleUpgradeRequest()
                        } else {
                            showingAddVehicle = true
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(ColorTheme.primary)
                    }
                }
            }
            .sheet(isPresented: $showingAddVehicle) {
                AddVehicleView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(item: $editingVehicle) { v in
                VehicleDetailView(vehicle: v, startEditing: true)
            }
            .alert(Text("delete".localizedString) + Text("".localizedString) + Text("vehicle_section_title".localizedString) + Text("?"), isPresented: $showDeleteAlert, presenting: vehicleToDelete) { v in
                Button("delete".localizedString, role: .destructive) {
                    // Soft delete via CloudSyncManager
                    if case .signedIn(let user) = sessionStore.status {
                        Task {
                            // Soft delete: sets deletedAt, updates UI via observation
                            await cloudSyncManager.deleteVehicle(v, dealerId: user.id)
                        }
                    } else {
                        // Fallback for guest mode (local delete)
                         viewModel.deleteVehicle(v)
                    }
                }
                Button("cancel".localizedString, role: .cancel) {}
            } message: { _ in
                Text("this_action_cannot_be_undone".localizedString)
            }
            .sheet(item: $sellingVehicle) { v in
                NavigationStack {
                    Form {
                        Section("sale_price".localizedString) {
                            TextField("sale_price".localizedString, text: $sellPriceText)
                                .keyboardType(.decimalPad)
                                .onChange(of: sellPriceText) { _, newValue in
                                    let filtered = newValue.filter { "0123456789.".contains($0) }
                                    if filtered != newValue { sellPriceText = filtered }
                                }
                            DatePicker("date".localizedString, selection: $sellDate, displayedComponents: .date)
                        }
                        
                        Section("buyer_details".localizedString) {
                            TextField("buyer_name".localizedString, text: $buyerName)
                            TextField("phone_number".localizedString, text: $buyerPhone)
                                .keyboardType(.phonePad)
                        }
                        
                        Section("payment_method".localizedString) {
                            Picker("payment_method".localizedString, selection: $paymentMethod) {
                                ForEach(paymentMethods, id: \.self) { method in
                                    Text(method.localizedString).tag(method)
                                }
                            }
                        }

                        Section("deposit_to_section".localizedString) {
                            Picker("account_label".localizedString, selection: $sellAccount) {
                                Text("select_account".localizedString).tag(nil as FinancialAccount?)
                                ForEach(accounts) { account in
                                    Text(account.accountType ?? "Unknown").tag(account as FinancialAccount?)
                                }
                            }
                        }
                    }
                    .navigationTitle("mark_as_sold".localizedString)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("cancel".localizedString) { sellingVehicle = nil } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("save".localizedString) {
                                guard let sp = Decimal(string: sellPriceText), sp > 0, let account = sellAccount else { return }

                                // 1) Create Sale record (same as New Sale flow)
                                let newSale = Sale(context: viewContext)
                                newSale.id = UUID()
                                newSale.vehicle = v
                                newSale.amount = NSDecimalNumber(decimal: sp)
                                newSale.date = sellDate
                                newSale.buyerName = buyerName
                                newSale.buyerPhone = buyerPhone
                                newSale.paymentMethod = paymentMethod
                                newSale.account = account
                                newSale.createdAt = Date()
                                newSale.updatedAt = newSale.createdAt

                                // 2) Update Vehicle
                                v.status = "sold"
                                v.salePrice = NSDecimalNumber(decimal: sp)
                                v.saleDate = sellDate
                                v.buyerName = buyerName
                                v.buyerPhone = buyerPhone
                                v.paymentMethod = paymentMethod
                                v.updatedAt = Date()

                                // 3) Credit the selected account
                                let currentBalance = account.balance?.decimalValue ?? 0
                                account.balance = NSDecimalNumber(decimal: currentBalance + sp)
                                account.updatedAt = Date()

                                do {
                                    try viewContext.save()
                                } catch {
                                    print("Failed to save sold: \(error)")
                                    return
                                }

                                viewModel.fetchVehicles()

                                if let dealerId = CloudSyncEnvironment.currentDealerId {
                                    Task {
                                        await cloudSyncManager.upsertSale(newSale, dealerId: dealerId)
                                        await cloudSyncManager.upsertVehicle(v, dealerId: dealerId)
                                        await cloudSyncManager.upsertFinancialAccount(account, dealerId: dealerId)
                                    }
                                }

                                sellingVehicle = nil
                            }
                            .disabled(!canSaveQuickSale)
                        }
                    }
                }
                .onAppear {
                    createDefaultAccountsIfNeeded()
                    applyDefaultSellAccountIfNeeded()
                }
                .onChange(of: accounts.count) { _, _ in
                    applyDefaultSellAccountIfNeeded()
                }
            }
            .onAppear {
                if !presetApplied, let s = presetStatus {
                    if s == "sold" {
                        viewModel.displayMode = .sold
                    } else {
                        viewModel.displayMode = .inventory
                        viewModel.selectedStatus = s
                    }
                    viewModel.fetchVehicles()
                    presetApplied = true
                }
            }
        }
    
    private func handleUpgradeRequest() {
        if isSignedIn {
            showingPaywall = true
        } else {
            appSessionState.exitGuestModeForLogin()
        }
    }

    private func applyDefaultSellAccountIfNeeded() {
        guard sellAccount == nil, !accounts.isEmpty else { return }
        sellAccount = accounts.first(where: { ($0.accountType ?? "").lowercased() == "cash" }) ?? accounts.first
    }

    private func createDefaultAccountsIfNeeded() {
        guard accounts.isEmpty else { return }

        let cash = FinancialAccount(context: viewContext)
        cash.id = UUID()
        cash.accountType = "Cash"
        cash.balance = NSDecimalNumber(value: 0)
        cash.updatedAt = Date()

        let bank = FinancialAccount(context: viewContext)
        bank.id = UUID()
        bank.accountType = "Bank"
        bank.balance = NSDecimalNumber(value: 0)
        bank.updatedAt = Date()

        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            print("Failed to create default accounts: \(error)")
        }
    }
    
    var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "car.2.fill")
                .font(.system(size: 80))
                .foregroundColor(ColorTheme.primary.opacity(0.3))
            
            VStack(spacing: 8) {
                Text(viewModel.displayMode == .sold ? "no_sold_vehicles".localizedString : "no_vehicles_found_title".localizedString)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(ColorTheme.primaryText)
                
                Text(viewModel.displayMode == .sold ? "no_sold_vehicles_msg".localizedString : "no_vehicles_found_msg".localizedString)
                    .font(.body)
                    .foregroundColor(ColorTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            if viewModel.displayMode == .inventory {
                Button(action: {
                    if !subscriptionManager.isProAccessActive && !subscriptionManager.isCheckingStatus && viewModel.vehicles.count >= 3 {
                        handleUpgradeRequest()
                    } else {
                        showingAddVehicle = true
                    }
                }) {
                    Text("add_vehicle".localizedString)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(ColorTheme.primary)
                        .cornerRadius(24)
                }
                .padding(.top, 20)
            }
            
            Spacer()
        }
    }
}

struct VehicleCard: View {
    @ObservedObject var vehicle: Vehicle
    let viewModel: VehicleViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header with Image and Basic Info
            HStack(alignment: .top, spacing: 12) {
                if let id = vehicle.id {
                    VehicleThumbnailView(vehicleID: id)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                            .font(.headline)
                            .foregroundColor(ColorTheme.primaryText)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        StatusBadge(status: vehicle.status ?? "")
                    }
                    
                    Text("VIN: \(vehicle.vin ?? "")")
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                        .monospacedDigit()
                    
                    HStack(spacing: 12) {
                        Label(vehicle.year.asYear(), systemImage: "calendar")
                        Label("\(viewModel.expenseCount(for: vehicle)) exp", systemImage: "wrench.and.screwdriver")
                    }
                    .font(.caption2)
                    .foregroundColor(ColorTheme.tertiaryText)
                    .padding(.top, 2)
                    
                    Text("Added: \(vehicle.purchaseDate ?? Date(), formatter: dateFormatter)")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.tertiaryText)
                }
            }
            .padding(12)
            
            Divider()
                .padding(.horizontal, 12)
            
            // Financial Footer
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("purchase_price".localizedString)
                        .font(.caption2)
                        .foregroundColor(ColorTheme.secondaryText)
                    Text((vehicle.purchasePrice as Decimal? ?? 0).asCurrency())
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(ColorTheme.primaryText)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("total_cost".localizedString)
                        .font(.caption2)
                        .foregroundColor(ColorTheme.secondaryText)
                    Text(viewModel.totalCost(for: vehicle).asCurrency())
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(ColorTheme.primary)
                }
                
                if let p = profitValue() {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("profit".localizedString)
                            .font(.caption2)
                            .foregroundColor(ColorTheme.secondaryText)
                        Text(p.asCurrency())
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(p >= 0 ? ColorTheme.success : ColorTheme.danger)
                    }
                }
            }
            .padding(12)
            .background(ColorTheme.background.opacity(0.5))
        }
        .background(ColorTheme.background)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private func profitValue() -> Decimal? {
        guard (vehicle.status ?? "") == "sold", let sp = vehicle.salePrice as Decimal? else { return nil }
        return sp - viewModel.totalCost(for: vehicle)
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM, h:mm a"
        return formatter
    }
}


struct VehicleThumbnailView: View {
    let vehicleID: UUID
    @State private var image: Image? = nil

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.1))
                .frame(width: 80, height: 60)
                .cornerRadius(10)

            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 60)
                    .clipped()
                    .cornerRadius(10)
            } else {
                Image(systemName: "car.fill")
                    .font(.system(size: 24))
                    .foregroundColor(ColorTheme.secondaryText.opacity(0.5))
            }
        }
        .onAppear {
            loadImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vehicleImageUpdated)) { notification in
            if let updatedID = notification.object as? UUID, updatedID == vehicleID {
                loadImage()
            }
        }
    }

    private func loadImage() {
        ImageStore.shared.swiftUIImage(id: vehicleID) { loaded in
            self.image = loaded
        }
    }
}

struct StatusBadge: View {
    let status: String

    var statusText: String {
        switch status {
        case "reserved": return "reserved".localizedString.capitalized
        case "on_sale": return "on_sale".localizedString.capitalized
        case "available": return "on_sale".localizedString.capitalized
        case "sold": return "sold".localizedString.capitalized
        case "in_transit": return "in_transit".localizedString.capitalized
        case "under_service": return "under_service".localizedString.capitalized
        default: return status.capitalized
        }
    }
    
    var statusColor: Color {
        switch status {
        case "reserved": return Color.blue
        case "on_sale", "available": return Color.green
        case "sold": return Color.green
        case "in_transit": return Color.purple
        case "under_service": return Color.red
        default: return Color.gray
        }
    }

    var body: some View {
        Text(statusText)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.15))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(statusColor.opacity(0.3), lineWidth: 1)
            )
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .medium)
                .foregroundColor(isSelected ? .white : ColorTheme.secondaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? ColorTheme.primary : ColorTheme.background)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? Color.clear : Color.gray.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: isSelected ? ColorTheme.primary.opacity(0.3) : Color.clear, radius: 4, y: 2)
        }
    }
}

#Preview {
    VehicleListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

extension VehicleListView {
    private var displayModePicker: some View {
        Picker("Display Mode", selection: $viewModel.displayMode) {
            ForEach(VehicleViewModel.DisplayMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var searchAndFilterHeader: some View {
        HStack(spacing: 12) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("search_vehicle_placeholder".localizedString, text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(ColorTheme.background)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            
            // Sort Menu
            Menu {
                Picker("Sort By", selection: $viewModel.sortOption) {
                    ForEach(VehicleViewModel.SortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ColorTheme.primary)
                    .padding(10)
                    .background(ColorTheme.background)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
            
            // Filter Menu (Only visible in Inventory mode)
            if viewModel.displayMode == .inventory {
                Menu {
                    Picker("Filter By", selection: $viewModel.selectedStatus) {
                        Text("all_inventory".localizedString).tag("all")
                        Divider()
                        Text("reserved".localizedString).tag("reserved")
                        Text("on_sale".localizedString).tag("on_sale")
                        Text("in_transit".localizedString).tag("in_transit")
                        Text("under_service".localizedString).tag("under_service")
                    }
                } label: {
                    Image(systemName: viewModel.selectedStatus == "all" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(viewModel.selectedStatus == "all" ? ColorTheme.primary : .blue)
                        .padding(10)
                        .background(ColorTheme.background)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(viewModel.selectedStatus == "all" ? Color.gray.opacity(0.2) : Color.blue.opacity(0.5), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var vehicleList: some View {
        if viewModel.vehicles.isEmpty {
            ScrollView {
                emptyStateView
                    .frame(minHeight: UIScreen.main.bounds.height - 200) // Ensure it fills screen to be scrollable
            }
            .refreshable {
                if case .signedIn(let user) = sessionStore.status {
                    await cloudSyncManager.manualSync(user: user, force: true)
                    viewModel.fetchVehicles()
                }
            }
        } else {
            List {
                ForEach(viewModel.vehicles, id: \.id) { vehicle in
                    VehicleCard(vehicle: vehicle, viewModel: viewModel)
                        .background(
                            NavigationLink(destination: VehicleDetailView(vehicle: vehicle)) {
                                EmptyView()
                            }
                            .opacity(0)
                        )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .contextMenu {
                        Button { editingVehicle = vehicle } label: { Label("edit".localizedString, systemImage: "pencil") }
                        Button { viewModel.duplicateVehicle(vehicle) } label: { Label("duplicate".localizedString, systemImage: "doc.on.doc") }
                        Divider()
                        Button(role: .destructive) { vehicleToDelete = vehicle; showDeleteAlert = true } label: { Label("delete".localizedString, systemImage: "trash") }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            vehicleToDelete = vehicle; showDeleteAlert = true
                        } label: { Label("delete".localizedString, systemImage: "trash") }
                        
                        Button { editingVehicle = vehicle } label: { Label("edit".localizedString, systemImage: "pencil") }
                            .tint(ColorTheme.primary)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if vehicle.status != "sold" {
                            Button {
                                sellingVehicle = vehicle
                                sellPriceText = ""
                                sellDate = Date()
                                buyerName = ""
                                buyerPhone = ""
                                paymentMethod = "Cash"
                                sellAccount = nil
                            } label: {
                                Label("sold".localizedString, systemImage: "checkmark.circle")
                            }
                            .tint(.green)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable {
                if case .signedIn(let user) = sessionStore.status {
                    await cloudSyncManager.manualSync(user: user, force: true)
                    viewModel.fetchVehicles()
                }
            }
        }
    }
}

struct VehicleStatusDashboard: View {
    @ObservedObject var viewModel: VehicleViewModel
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                // Total -> Inventory Mode, All Status
                Button {
                    viewModel.displayMode = .inventory
                    viewModel.selectedStatus = "all"
                } label: {
                    StatCard(
                        title: "total".localizedString,
                        count: viewModel.totalVehiclesCount,
                        color: ColorTheme.primary,
                        icon: "car.2.fill",
                        isActive: viewModel.displayMode == .inventory && viewModel.selectedStatus == "all"
                    )
                }
                
                // On Sale -> Inventory Mode, On Sale Status
                Button {
                    viewModel.displayMode = .inventory
                    viewModel.selectedStatus = "on_sale"
                } label: {
                    StatCard(
                        title: "on_sale".localizedString,
                        count: viewModel.onSaleCount,
                        color: .green,
                        icon: "tag.fill",
                        isActive: viewModel.displayMode == .inventory && viewModel.selectedStatus == "on_sale"
                    )
                }

                // In Garage -> Inventory Mode, Reserved Status
                Button {
                    viewModel.displayMode = .inventory
                    viewModel.selectedStatus = "reserved"
                } label: {
                    StatCard(
                        title: "reserved".localizedString,
                        count: viewModel.inGarageCount,
                        color: .orange,
                        icon: "house.fill",
                        isActive: viewModel.displayMode == .inventory && viewModel.selectedStatus == "reserved"
                    )
                }
                
                // In Transit
                Button {
                    viewModel.displayMode = .inventory
                    viewModel.selectedStatus = "in_transit"
                } label: {
                    StatCard(
                        title: "in_transit".localizedString,
                        count: viewModel.inTransitCount,
                        color: .purple,
                        icon: "airplane",
                        isActive: viewModel.displayMode == .inventory && viewModel.selectedStatus == "in_transit"
                    )
                }

                // Sold -> Sold Mode
                Button {
                    viewModel.displayMode = .sold
                } label: {
                    StatCard(
                        title: "sold".localizedString,
                        count: viewModel.soldCount,
                        color: .blue,
                        icon: "checkmark.circle.fill",
                        isActive: viewModel.displayMode == .sold
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}

struct StatCard: View {
    let title: String
    let count: Int
    let color: Color
    let icon: String
    var isActive: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(isActive ? .white : color)
                .frame(width: 24, height: 24)
                .background(isActive ? .white.opacity(0.2) : color.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(isActive ? .white.opacity(0.9) : ColorTheme.secondaryText)
                    .fixedSize()
                
                Text("\(count)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(isActive ? .white : ColorTheme.primaryText)
            }
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isActive ? color : ColorTheme.background)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isActive ? Color.clear : Color.gray.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: isActive ? color.opacity(0.3) : Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
    }
}
