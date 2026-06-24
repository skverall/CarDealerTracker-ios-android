//
//  VehicleListView.swift
//  Ezcar24Business
//
//  Vehicle inventory list with filtering
//

import SwiftUI
import CoreData

struct VehicleListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel: VehicleViewModel
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSessionState: AppSessionState
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @ObservedObject private var permissionService = PermissionService.shared
    
    @State private var showingAddVehicle = false
    @State private var showingPaywall = false
    @State private var paywallVehicleCount = 0
    private let presetStatus: String?
    private let focusAgingInventory: Bool
    private let showNavigation: Bool
    @State private var presetApplied: Bool = false
    @State private var showAgingInventoryFocusBanner: Bool = false
    @State private var editingVehicle: Vehicle?
    @State private var vehicleToDelete: Vehicle?
    @State private var showDeleteAlert: Bool = false
    @State private var sellingVehicle: Vehicle?
    @State private var sellPriceText: String = ""
    @State private var sellDate: Date = Date()
    @State private var buyerName: String = ""
    @State private var buyerPhone: String = ""
    @State private var paymentMethod: String = "Cash"

    private var isPadLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var listBottomPadding: CGFloat {
        isPadLayout ? 0 : 90
    }

    private var agedInventoryCount: Int {
        viewModel.vehicles.filter { vehicle in
            vehicle.status != "sold" && HoldingCostCalculator.calculateDaysInInventory(vehicle: vehicle) >= 120
        }.count
    }

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FinancialAccount.accountType, ascending: true)],
        predicate: NSPredicate(format: "deletedAt == nil"),
        animation: .default
    )
    private var accounts: FetchedResults<FinancialAccount>
    @State private var sellAccount: FinancialAccount? = nil
    
    let paymentMethods = ["Cash", "Bank Transfer", "Cheque", "Finance", "Other"]
    
    private var isSignedIn: Bool {
        if case .signedIn = sessionStore.status { return true }
        return false
    }

    private var canDeleteRecords: Bool {
        if case .signedIn = sessionStore.status {
            return permissionService.can(.deleteRecords)
        }
        return true
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



    init(presetStatus: String? = nil, focusAgingInventory: Bool = false, showNavigation: Bool = true) {
        self.presetStatus = presetStatus
        self.focusAgingInventory = focusAgingInventory
        self.showNavigation = showNavigation
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: VehicleViewModel(context: context))
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
    
    var content: some View {
        ZStack {
            if isPadLayout {
                iPadVehicleContent
            } else {
                ColorTheme.secondaryBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    displayModePicker
                    VehicleStatusDashboard(viewModel: viewModel)
                    searchAndFilterHeader
                    if showAgingInventoryFocusBanner {
                        agingInventoryFocusBanner
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    vehicleList
                }
            }
            }
            .navigationTitle(isPadLayout ? "" : "vehicles".localizedString)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if permissionService.can(.viewInventory), permissionService.canViewVehicleCost() {
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
            }
            .adaptiveFormPresentation(isPresented: $showingAddVehicle) {
                AddVehicleView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(source: .vehicleLimit, vehicleCount: paywallVehicleCount, freeLimit: 3)
            }
            .sheet(item: $editingVehicle) { v in
                VehicleDetailView(vehicle: v, startEditing: true)
            }
            .alert(Text("delete".localizedString) + Text("".localizedString) + Text("vehicle_section_title".localizedString) + Text("?"), isPresented: $showDeleteAlert, presenting: vehicleToDelete) { v in
                Button("delete".localizedString, role: .destructive) {
                    guard canDeleteRecords else { return }
                    // Soft delete via CloudSyncManager
                    if case .signedIn(let user) = sessionStore.status {
                        Task {
                            // Soft delete: sets deletedAt, updates UI via observation
                            let dealerId = CloudSyncEnvironment.currentDealerId ?? user.id
                            await cloudSyncManager.deleteVehicle(v, dealerId: dealerId)
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
                                    Text(account.displayTitle).tag(account as FinancialAccount?)
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
                applyLaunchPresetIfNeeded()
            }
        }

    private func applyLaunchPresetIfNeeded() {
        guard !presetApplied else { return }

        if let s = presetStatus {
            if s == "sold" {
                viewModel.displayMode = .sold
            } else {
                viewModel.displayMode = .inventory
                viewModel.selectedStatus = s
            }
            viewModel.fetchVehicles()
            presetApplied = true
            return
        }

        if focusAgingInventory {
            viewModel.displayMode = .inventory
            viewModel.selectedStatus = "all"
            viewModel.sortOption = .daysDesc
            showAgingInventoryFocusBanner = true
            viewModel.fetchVehicles()
        }

        presetApplied = true
    }

    private var agingInventoryFocusBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "scope")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(ColorTheme.warning)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(ColorTheme.warning.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("inventory_radar_focus_title".localizedString)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(ColorTheme.primaryText)
                    .lineLimit(1)

                Text("inventory_radar_focus_detail".localizedString)
                    .font(.caption.weight(.medium))
                    .foregroundColor(ColorTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button {
                showAgingInventoryFocusBanner = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(ColorTheme.background)
                    .clipShape(Circle())
            }
            .accessibilityLabel("close".localizedString)
        }
        .padding(12)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ColorTheme.warning.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.035), radius: 8, y: 3)
    }
    
    private func handleUpgradeRequest() {
        if isSignedIn {
            paywallVehicleCount = viewModel.vehicles.count
            PaywallAnalytics.logVehicleLimitGate(vehicleCount: viewModel.vehicles.count, freeLimit: 3, entryPoint: "vehicle_list")
            showingPaywall = true
        } else {
            appSessionState.exitGuestModeForLogin()
        }
    }

    private func applyDefaultSellAccountIfNeeded() {
        guard sellAccount == nil, !accounts.isEmpty else { return }
        sellAccount = accounts.first(where: { $0.kind == .cash }) ?? accounts.first
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
            
            if viewModel.displayMode == .inventory && permissionService.can(.viewInventory) {
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

private struct iPadVehicleCanvas: View {
    var body: some View {
        ZStack {
            ColorTheme.background

            LinearGradient(
                colors: [
                    ColorTheme.primary.opacity(0.12),
                    ColorTheme.secondary.opacity(0.07),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )

            LinearGradient(
                colors: [
                    ColorTheme.accent.opacity(0.08),
                    Color.clear
                ],
                startPoint: .bottomTrailing,
                endPoint: .center
            )
        }
    }
}

struct VehicleCard: View {
    @ObservedObject private var permissionService = PermissionService.shared
    @ObservedObject private var inventoryStats = InventoryStatsManager.shared

    @ObservedObject var vehicle: Vehicle
    let viewModel: VehicleViewModel

    private var daysInInventory: Int {
        HoldingCostCalculator.calculateDaysInInventory(vehicle: vehicle)
    }

    private var holdingCost: Decimal {
        guard let vehicleId = vehicle.id else { return 0 }
        let stats = InventoryStatsManager.shared.getStats(for: vehicleId)
        return stats?.holdingCostAccumulated?.decimalValue ?? 0
    }
    
    private var dailyHoldingCost: Decimal {
        guard daysInInventory > 0 else { return 0 }
        return holdingCost / Decimal(daysInInventory)
    }

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            iPadBody
        } else {
            compactBody
        }
    }

    private var compactBody: some View {
        VStack(spacing: 0) {
            // Main Content Row
            HStack(alignment: .top, spacing: 10) { // Reduced spacing
                // Leading: Thumbnail
                if let id = vehicle.id {
                    VehicleThumbnailView(vehicleID: id)
                        .frame(width: 70, height: 70) // Reduced thumbnail size
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)) // Reduced radius
                        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
                }
                
                // Center/Right: Details
                VStack(alignment: .leading, spacing: 4) { // Reduced spacing
                    
                    // Top Row: Title + Status
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vehicle.displayNameWithInventory)
                                .font(.system(size: 15, weight: .bold)) // Reduced font
                                .foregroundColor(ColorTheme.primaryText)
                                .lineLimit(1)
                            
                            HStack(spacing: 8) {
                                Text(vehicle.year.asYear())
                                    .fontWeight(.medium)
                                if vehicle.mileage > 0 {
                                    Text("•")
                                        .foregroundColor(ColorTheme.secondaryText.opacity(0.5))
                                    Text("\(vehicle.mileage) km")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondary)
                        }
                        
                        Spacer()
                        
                        if vehicle.status != "sold" && daysInInventory > 0 {
                            DaysInInventoryBadge(days: daysInInventory)
                        }
                        
                        StatusBadge(status: vehicle.status ?? "")
                            .scaleEffect(0.9) // Slightly smaller badge
                    }
                    
                    // Second Row: VIN + Expenses Count
                    HStack(spacing: 8) { // Reduced spacing
                        if let inventoryLabel = vehicle.inventoryOrVINLabel {
                            Text(inventoryLabel)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundColor(ColorTheme.tertiaryText)
                        }

                        if vehicle.inventoryIDValue != nil, let vin = vehicle.vinValue {
                            Text("VIN: \(vin)")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundColor(ColorTheme.tertiaryText)
                        }
                        
                        if permissionService.canViewVehicleCost() {
                            Label(String(format: "%lld exp".localizedString, Int64(viewModel.expenseCount(for: vehicle))), systemImage: "wrench.and.screwdriver.fill")
                                .font(.caption2)
                                .foregroundColor(ColorTheme.tertiaryText)
                        }
                    }
                    
                    // Third Row: Days Since Purchase Badge (Inventory) or Added Date (Sold)
                    if vehicle.status != "sold", vehicle.purchaseDate != nil {
                        if holdingCost > 0 {
                            // Holding cost is now in the footer
                        }
                    } else if let date = vehicle.purchaseDate {
                         Text(String(format: "Added: %@".localizedString, dateFormatter.string(from: date)))
                            .font(.caption2)
                            .foregroundColor(ColorTheme.tertiaryText)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(12) // Reduced padding
            
            Divider()
                .padding(.horizontal, 12)
            
            // Footer: Cost & Financials
            // Footer: Cost & Financials
            let canSeeCost = permissionService.canViewVehicleCost()
            let canSeeProfit = permissionService.canViewVehicleProfit()
            
            if canSeeCost || canSeeProfit {
                HStack(alignment: .firstTextBaseline) {
                    if canSeeCost {
                        VStack(alignment: .leading, spacing: 0) { // Reduced spacing
                            Text("purchase_price".localizedString.uppercased())
                                .font(.system(size: 9, weight: .bold)) // Reduced font
                                .foregroundColor(ColorTheme.secondaryText)
                                .tracking(0.5)
                            
                            Text((vehicle.purchasePrice as Decimal? ?? 0).asCurrency())
                                .font(.system(size: 13, weight: .semibold)) // Reduced font
                                .foregroundColor(ColorTheme.primaryText)
                        }
                    }
                    
                    if canSeeCost && (holdingCost > 0 || daysInInventory > 0) {
                        Spacer()
                        VStack(alignment: .center, spacing: 0) { // Reduced spacing
                            Text("holding_cost".localizedString.uppercased())
                                .font(.system(size: 9, weight: .bold)) // Reduced font
                                .foregroundColor(holdingCost > 0 ? ColorTheme.warning : ColorTheme.secondaryText)
                                .tracking(0.5)
                            
                            Text(holdingCost.asCurrency())
                                .font(.system(size: 13, weight: .medium)) // Reduced font
                                .foregroundColor(holdingCost > 0 ? ColorTheme.warning : ColorTheme.secondaryText)
                        }
                    }
                    
                    Spacer()
                    
                    if canSeeCost {
                        VStack(alignment: .trailing, spacing: 0) { // Reduced spacing
                            Text("total_cost".localizedString.uppercased())
                                .font(.system(size: 9, weight: .bold)) // Reduced font
                                .foregroundColor(ColorTheme.secondaryText)
                                .tracking(0.5)
                            
                            let totalCost = viewModel.totalCost(for: vehicle) + holdingCost
                            Text(totalCost.asCurrency())
                                .font(.system(size: 13, weight: .bold)) // Reduced font
                                .foregroundColor(ColorTheme.primary)
                        }
                    }
                    
                    if canSeeProfit, let p = profitValue() {
                        // Adjust profit calculation to include holding cost
                        let adjustedProfit = p - holdingCost
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) { // Reduced spacing
                            Text("profit".localizedString.uppercased())
                                .font(.system(size: 9, weight: .bold)) // Reduced font
                                .foregroundColor(ColorTheme.secondaryText)
                                .tracking(0.5)
                            
                            Text(adjustedProfit.asCurrency())
                                .font(.system(size: 13, weight: .black)) // Reduced font
                                .foregroundColor(adjustedProfit >= 0 ? ColorTheme.success : ColorTheme.danger)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8) // Reduced padding
                .background(ColorTheme.secondaryBackground.opacity(0.3))
            }
        }
        .background(ColorTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)) // Reduced radius
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2) // Subtler shadow
    }

    private var iPadBody: some View {
        let canSeeCost = permissionService.canViewVehicleCost()
        let canSeeProfit = permissionService.canViewVehicleProfit()

        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                if let id = vehicle.id {
                    iPadVehicleThumbnailView(vehicleID: id)
                        .frame(width: 122, height: 92)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(.white.opacity(0.7), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Color.black.opacity(0.1), radius: 12, y: 7)
                }

                VStack(alignment: .leading, spacing: 9) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vehicle.displayNameWithInventory)
                            .font(.system(size: 21, weight: .black, design: .rounded))
                            .foregroundColor(ColorTheme.primaryText)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Text(vehicle.year.asYear())
                                .fontWeight(.bold)

                            if vehicle.mileage > 0 {
                                Text("•")
                                    .foregroundColor(ColorTheme.secondaryText.opacity(0.55))
                                Text("\(vehicle.mileage) km")
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondary)
                    }

                    HStack(spacing: 8) {
                        if let inventoryLabel = vehicle.inventoryOrVINLabel {
                            iPadMetadataPill(text: inventoryLabel, icon: "number")
                        }

                        if permissionService.canViewVehicleCost() {
                            iPadMetadataPill(
                                text: String(format: "%lld exp".localizedString, Int64(viewModel.expenseCount(for: vehicle))),
                                icon: "wrench.and.screwdriver.fill"
                            )
                        }

                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 8) {
                        if vehicle.status != "sold" && daysInInventory > 0 {
                            DaysInInventoryBadge(days: daysInInventory)
                        }

                        StatusBadge(status: vehicle.status ?? "")
                    }

                    if canSeeCost {
                        let totalCost = viewModel.totalCost(for: vehicle) + holdingCost
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("total_cost".localizedString.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundColor(ColorTheme.secondaryText)
                                .tracking(0.7)

                            Text(totalCost.asCurrency())
                                .font(.system(size: 19, weight: .black, design: .rounded))
                                .foregroundColor(ColorTheme.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }
                }
            }
            .padding(18)

            if canSeeCost || canSeeProfit {
                Divider()
                    .padding(.horizontal, 18)

                HStack(spacing: 12) {
                    if canSeeCost {
                        iPadFinancialCell(
                            title: "purchase_price".localizedString.uppercased(),
                            value: (vehicle.purchasePrice as Decimal? ?? 0).asCurrency(),
                            color: ColorTheme.primaryText,
                            textAlignment: .leading,
                            frameAlignment: .leading
                        )
                    }

                    if canSeeCost && (holdingCost > 0 || daysInInventory > 0) {
                        iPadFinancialCell(
                            title: "holding_cost".localizedString.uppercased(),
                            value: holdingCost.asCurrency(),
                            color: holdingCost > 0 ? ColorTheme.warning : ColorTheme.secondaryText,
                            textAlignment: .center,
                            frameAlignment: .center
                        )
                    }

                    if canSeeProfit, let p = profitValue() {
                        let adjustedProfit = p - holdingCost
                        iPadFinancialCell(
                            title: "profit".localizedString.uppercased(),
                            value: adjustedProfit.asCurrency(),
                            color: adjustedProfit >= 0 ? ColorTheme.success : ColorTheme.danger,
                            textAlignment: .trailing,
                            frameAlignment: .trailing
                        )
                    }
                }
                .padding(14)
                .background(ColorTheme.primary.opacity(0.035))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(ColorTheme.cardBackground.opacity(0.72))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.8), ColorTheme.primary.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: ColorTheme.primary.opacity(0.08), radius: 18, y: 10)
    }

    private func iPadMetadataPill(text: String, icon: String, tint: Color = ColorTheme.secondaryText) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.bold))
            .foregroundColor(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tint.opacity(0.1))
            .clipShape(Capsule())
            .lineLimit(1)
    }

    private func iPadFinancialCell(title: String, value: String, color: Color, textAlignment: HorizontalAlignment, frameAlignment: Alignment) -> some View {
        VStack(alignment: textAlignment, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .black))
                .foregroundColor(ColorTheme.secondaryText)
                .tracking(0.7)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    private func profitValue() -> Decimal? {
        // Use vehicle.salePrice directly as confirmed in VehicleViewModel
        guard vehicle.status == "sold",
              let salePrice = vehicle.salePrice as Decimal?
        else { return nil }
        
        let totalCost = viewModel.totalCost(for: vehicle)
        return salePrice - totalCost
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
        let dealerId = CloudSyncEnvironment.currentDealerId
        ImageStore.shared.swiftUIImage(id: vehicleID, dealerId: dealerId) { loaded in
            self.image = loaded
        }
    }
}

private struct iPadVehicleThumbnailView: View {
    let vehicleID: UUID
    @State private var image: Image? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.gray.opacity(0.1))

            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                Image(systemName: "car.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(ColorTheme.secondaryText.opacity(0.5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        let dealerId = CloudSyncEnvironment.currentDealerId
        ImageStore.shared.swiftUIImage(id: vehicleID, dealerId: dealerId) { loaded in
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
    private var iPadVehicleContent: some View {
        ZStack {
            iPadVehicleCanvas()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    iPadVehicleHero
                    iPadSearchAndFilterHeader
                    if showAgingInventoryFocusBanner {
                        agingInventoryFocusBanner
                    }
                    iPadStatusFilters

                    if viewModel.vehicles.isEmpty {
                        emptyStateView
                            .frame(minHeight: 360)
                            .padding(.top, 12)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 460), spacing: 14)],
                            spacing: 14
                        ) {
                            ForEach(Array(viewModel.vehicles.enumerated()), id: \.element.id) { index, vehicle in
                                iPadVehicleRow(vehicle)
                                    .staggeredAppear(index: index)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .refreshable {
                if case .signedIn(let user) = sessionStore.status {
                    await cloudSyncManager.manualSync(user: user, force: true)
                    viewModel.fetchVehicles()
                }
            }
        }
    }

    private var iPadVehicleHero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "car.2.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(ColorTheme.primary)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Text("vehicles".localizedString)
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }

                    Text("Car Dealer Tracker")
                        .font(.callout.weight(.semibold))
                        .foregroundColor(.white.opacity(0.78))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Picker("Display Mode".localizedString, selection: $viewModel.displayMode) {
                    ForEach(VehicleViewModel.DisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 310)
                .padding(4)
                .background(.white.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(spacing: 12) {
                iPadHeroMetric(
                    title: "inventory".localizedString,
                    value: "\(viewModel.totalVehiclesCount)",
                    icon: "rectangle.stack.fill",
                    color: ColorTheme.primary
                )

                iPadHeroMetric(
                    title: "on_sale".localizedString,
                    value: "\(viewModel.onSaleCount)",
                    icon: "tag.fill",
                    color: ColorTheme.success
                )

                iPadHeroMetric(
                    title: "reserved".localizedString,
                    value: "\(viewModel.inGarageCount)",
                    icon: "house.fill",
                    color: ColorTheme.accent
                )

                iPadHeroMetric(
                    title: "120d+",
                    value: "\(agedInventoryCount)",
                    icon: "flame.fill",
                    color: ColorTheme.danger
                )

                iPadHeroMetric(
                    title: "sold".localizedString,
                    value: "\(viewModel.soldCount)",
                    icon: "checkmark.seal.fill",
                    color: ColorTheme.secondary
                )
            }
        }
        .padding(22)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                ColorTheme.primary,
                                Color(red: 0.16, green: 0.36, blue: 0.75),
                                ColorTheme.purple
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .rotationEffect(.degrees(-8))
                    .offset(x: 230, y: -70)
                    .scaleEffect(1.25)
                    .allowsHitTesting(false)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: ColorTheme.primary.opacity(0.24), radius: 24, y: 14)
    }

    private var iPadSearchAndFilterHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(ColorTheme.secondaryText)

                TextField("search_vehicle_placeholder".localizedString, text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.5), lineWidth: 1)
            )

            Menu {
                Picker("Sort By".localizedString, selection: $viewModel.sortOption) {
                    ForEach(VehicleViewModel.SortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                iPadToolbarButton(icon: "arrow.up.arrow.down", title: viewModel.sortOption.title, color: ColorTheme.primary)
            }

            if viewModel.displayMode == .inventory {
                Menu {
                    Picker("Filter By".localizedString, selection: $viewModel.selectedStatus) {
                        Text("all_inventory".localizedString).tag("all")
                        Divider()
                        Text("reserved".localizedString).tag("reserved")
                        Text("on_sale".localizedString).tag("on_sale")
                        Text("in_transit".localizedString).tag("in_transit")
                        Text("under_service".localizedString).tag("under_service")
                    }
                } label: {
                    iPadToolbarButton(
                        icon: viewModel.selectedStatus == "all" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill",
                        title: selectedStatusTitle,
                        color: viewModel.selectedStatus == "all" ? ColorTheme.primary : ColorTheme.secondary
                    )
                }
            }

            Button {
                viewModel.sortOption = .daysDesc
                viewModel.selectedStatus = "all"
                viewModel.fetchVehicles()
            } label: {
                iPadToolbarButton(icon: "flame.fill", title: "burning_inventory".localizedString, color: ColorTheme.warning)
            }
            .buttonStyle(.hapticScale)
        }
    }

    private var iPadStatusFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                iPadStatusFilterButton(
                    title: "total".localizedString,
                    count: viewModel.totalVehiclesCount,
                    icon: "car.2.fill",
                    color: ColorTheme.primary,
                    isActive: viewModel.displayMode == .inventory && viewModel.selectedStatus == "all"
                ) {
                    viewModel.displayMode = .inventory
                    viewModel.selectedStatus = "all"
                }

                iPadStatusFilterButton(
                    title: "on_sale".localizedString,
                    count: viewModel.onSaleCount,
                    icon: "tag.fill",
                    color: ColorTheme.success,
                    isActive: viewModel.displayMode == .inventory && viewModel.selectedStatus == "on_sale"
                ) {
                    viewModel.displayMode = .inventory
                    viewModel.selectedStatus = "on_sale"
                }

                iPadStatusFilterButton(
                    title: "reserved".localizedString,
                    count: viewModel.inGarageCount,
                    icon: "house.fill",
                    color: ColorTheme.accent,
                    isActive: viewModel.displayMode == .inventory && viewModel.selectedStatus == "reserved"
                ) {
                    viewModel.displayMode = .inventory
                    viewModel.selectedStatus = "reserved"
                }

                iPadStatusFilterButton(
                    title: "in_transit".localizedString,
                    count: viewModel.inTransitCount,
                    icon: "airplane",
                    color: ColorTheme.purple,
                    isActive: viewModel.displayMode == .inventory && viewModel.selectedStatus == "in_transit"
                ) {
                    viewModel.displayMode = .inventory
                    viewModel.selectedStatus = "in_transit"
                }

                iPadStatusFilterButton(
                    title: "sold".localizedString,
                    count: viewModel.soldCount,
                    icon: "checkmark.circle.fill",
                    color: ColorTheme.secondary,
                    isActive: viewModel.displayMode == .sold
                ) {
                    viewModel.displayMode = .sold
                }
            }
        }
    }

    private func iPadVehicleRow(_ vehicle: Vehicle) -> some View {
        NavigationLink(destination: VehicleDetailView(vehicle: vehicle)) {
            VehicleCard(vehicle: vehicle, viewModel: viewModel)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .contextMenu {
            vehicleContextMenu(for: vehicle)
        }
        .overlay(alignment: .topTrailing) {
            Menu {
                vehicleContextMenu(for: vehicle)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(ColorTheme.primary)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.06), radius: 6, y: 3)
            }
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
    }

    @ViewBuilder
    private func vehicleContextMenu(for vehicle: Vehicle) -> some View {
        if permissionService.can(.viewInventory) {
            Button { editingVehicle = vehicle } label: { Label("edit".localizedString, systemImage: "pencil") }
            Button { viewModel.duplicateVehicle(vehicle) } label: { Label("duplicate".localizedString, systemImage: "doc.on.doc") }
            if vehicle.status != "sold", permissionService.can(.createSale) {
                Button {
                    prepareQuickSale(for: vehicle)
                } label: {
                    Label("sold".localizedString, systemImage: "checkmark.circle")
                }
            }
            if canDeleteRecords {
                Divider()
                Button(role: .destructive) {
                    vehicleToDelete = vehicle
                    showDeleteAlert = true
                } label: {
                    Label("delete".localizedString, systemImage: "trash")
                }
            }
        }
    }

    private func prepareQuickSale(for vehicle: Vehicle) {
        sellingVehicle = vehicle
        sellPriceText = ""
        sellDate = Date()
        buyerName = ""
        buyerPhone = ""
        paymentMethod = "Cash"
        sellAccount = nil
    }

    private var selectedStatusTitle: String {
        switch viewModel.selectedStatus {
        case "reserved":
            return "reserved".localizedString
        case "on_sale":
            return "on_sale".localizedString
        case "in_transit":
            return "in_transit".localizedString
        case "under_service":
            return "under_service".localizedString
        default:
            return "all_inventory".localizedString
        }
    }

    private func iPadHeroMetric(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(color)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)

                Text(title)
                    .font(.caption.weight(.heavy))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(.white.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        )
    }

    private func iPadToolbarButton(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))

            Text(title)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.5), lineWidth: 1)
        )
    }

    private func iPadStatusFilterButton(
        title: String,
        count: Int,
        icon: String,
        color: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isActive ? .white : color)
                    .frame(width: 34, height: 34)
                    .background(isActive ? .white.opacity(0.24) : color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(isActive ? .white : ColorTheme.primaryText)
                        .lineLimit(1)

                    Text("\(count)")
                        .font(.title3.weight(.black))
                        .foregroundColor(isActive ? .white : color)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Group {
                    if isActive {
                        LinearGradient(
                            colors: [color, ColorTheme.primary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        LinearGradient(
                            colors: [.white.opacity(0.82), .white.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isActive ? .white.opacity(0.2) : color.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: isActive ? color.opacity(0.28) : Color.black.opacity(0.05), radius: 12, y: 6)
        }
        .buttonStyle(.hapticScale)
    }

    private var displayModePicker: some View {
        Picker("Display Mode".localizedString, selection: $viewModel.displayMode) {
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
                Picker("Sort By".localizedString, selection: $viewModel.sortOption) {
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
                    Picker("Filter By".localizedString, selection: $viewModel.selectedStatus) {
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
                
                // Burning Inventory Quick Filter
                Menu {
                    Button(action: {
                        viewModel.sortOption = .daysDesc
                        viewModel.selectedStatus = "all"
                        viewModel.fetchVehicles()
                    }) {
                        Label("all_vehicles".localizedString, systemImage: "car.fill")
                    }
                    
                    Button(action: {
                        viewModel.sortOption = .daysDesc
                        viewModel.selectedStatus = "all"
                        viewModel.fetchVehicles()
                    }) {
                        Label("burning_inventory".localizedString, systemImage: "flame.fill")
                    }
                } label: {
                    Image(systemName: "flame")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ColorTheme.warning)
                        .padding(10)
                        .background(ColorTheme.background)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
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
                ForEach(Array(viewModel.vehicles.enumerated()), id: \.element.id) { index, vehicle in
                    ZStack {
                        VehicleCard(vehicle: vehicle, viewModel: viewModel)
                        NavigationLink(destination: VehicleDetailView(vehicle: vehicle)) {
                            EmptyView()
                        }
                        .opacity(0)
                        .buttonStyle(PlainButtonStyle()) // Important to keep interaction working correctly
                    }
                    .staggeredAppear(index: index)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .contextMenu {
                        if permissionService.can(.viewInventory) {
                            Button { editingVehicle = vehicle } label: { Label("edit".localizedString, systemImage: "pencil") }
                            Button { viewModel.duplicateVehicle(vehicle) } label: { Label("duplicate".localizedString, systemImage: "doc.on.doc") }
                            if canDeleteRecords {
                                Divider()
                                Button(role: .destructive) { vehicleToDelete = vehicle; showDeleteAlert = true } label: { Label("delete".localizedString, systemImage: "trash") }
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if permissionService.can(.viewInventory) {
                            if canDeleteRecords {
                                Button(role: .destructive) {
                                    vehicleToDelete = vehicle; showDeleteAlert = true
                                } label: { Label("delete".localizedString, systemImage: "trash") }
                            }
                            
                            Button { editingVehicle = vehicle } label: { Label("edit".localizedString, systemImage: "pencil") }
                                .tint(ColorTheme.primary)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if vehicle.status != "sold", permissionService.can(.createSale) {
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
            .padding(.bottom, listBottomPadding)
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
