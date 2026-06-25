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
                mobileVehicleContent
            }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isPadLayout ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isPadLayout, permissionService.can(.viewInventory), permissionService.canViewVehicleCost() {
                        Button(action: handleAddVehicleTap) {
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

    private func handleAddVehicleTap() {
        if !subscriptionManager.isProAccessActive && !subscriptionManager.isCheckingStatus && viewModel.vehicles.count >= 3 {
            handleUpgradeRequest()
        } else {
            showingAddVehicle = true
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

private struct VehiclePortfolioHeroCard: View {
    @ObservedObject var viewModel: VehicleViewModel
    @ObservedObject private var inventoryStats = InventoryStatsManager.shared
    @ObservedObject private var permissionService = PermissionService.shared

    private var canSeeFinancials: Bool {
        permissionService.canViewVehicleCost()
    }

    private var inventoryValue: Decimal {
        guard canSeeFinancials else { return 0 }
        return inventoryStats.calculateTotalInventoryValue()
    }

    private var avgDays: Int {
        InventoryMetricsCalculator.calculateAverageDaysInInventory(stats: Array(inventoryStats.getAllStats().values))
    }

    private var activeCount: Int {
        viewModel.totalVehiclesCount
    }

    private var trendPoints: [CGFloat] {
        let total = max(1, activeCount)
        let saleRatio = CGFloat(viewModel.onSaleCount) / CGFloat(total)
        let transitRatio = CGFloat(viewModel.inTransitCount) / CGFloat(total)
        let agingPressure = min(0.24, CGFloat(avgDays) / 500)
        return [
            0.26,
            0.38 + saleRatio * 0.08,
            0.33 + transitRatio * 0.08,
            0.46,
            0.50 + agingPressure,
            0.45,
            0.58,
            0.54 + saleRatio * 0.08,
            0.74
        ].map { min(0.88, max(0.12, $0)) }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(canSeeFinancials ? "inventory_value".localizedString : "inventory".localizedString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ColorTheme.secondaryText)
                    .lineLimit(1)

                Text(canSeeFinancials ? inventoryValue.asCurrency() : "\(activeCount)")
                    .font(.system(size: 29, weight: .black, design: .rounded))
                    .foregroundColor(ColorTheme.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.52)

                HStack(spacing: 6) {
                    Image(systemName: avgDays >= 90 ? "exclamationmark.triangle.fill" : "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(avgDays >= 90 ? ColorTheme.danger : ColorTheme.success)

                    Text(String(format: "%lld vehicles in stock".localizedString, Int64(activeCount)))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ColorTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 7) {
                Text(String(format: "%d %@", avgDays, "avg_days".localizedStringFallback))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ColorTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                PortfolioSparklineChart(points: trendPoints, color: ColorTheme.secondary)
                    .frame(width: 130, height: 52)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 9, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }
}

private struct PortfolioSparklineChart: View {
    let points: [CGFloat]
    let color: Color

    private let markerSize: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let markerRadius = markerSize / 2
            let chartSize = CGSize(
                width: max(0, proxy.size.width - markerSize),
                height: max(0, proxy.size.height - markerRadius)
            )
            let chartOrigin = CGPoint(x: markerRadius, y: markerRadius / 2)
            let chartRect = CGRect(origin: chartOrigin, size: chartSize)
            let endPoint = PortfolioSparkline.endpoint(in: chartRect, points: points)

            ZStack {
                PortfolioSparklineArea(points: points)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.18), color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: chartSize.width, height: chartSize.height)
                    .position(x: chartRect.midX, y: chartRect.midY)

                PortfolioSparkline(points: points)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .frame(width: chartSize.width, height: chartSize.height)
                    .position(x: chartRect.midX, y: chartRect.midY)

                if let endPoint {
                    Circle()
                        .fill(color)
                        .frame(width: markerSize, height: markerSize)
                        .shadow(color: color.opacity(0.25), radius: 5, y: 2)
                        .position(endPoint)
                }
            }
        }
    }
}

private struct PortfolioSparkline: Shape {
    let points: [CGFloat]

    static func endpoint(in rect: CGRect, points: [CGFloat]) -> CGPoint? {
        guard let last = points.last else { return nil }
        let yRatio = min(0.95, max(0.05, last))
        return CGPoint(
            x: rect.maxX,
            y: rect.maxY - yRatio * rect.height
        )
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        let step = rect.width / CGFloat(points.count - 1)

        for index in points.indices {
            let x = CGFloat(index) * step
            let y = rect.maxY - points[index] * rect.height
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }
}

private struct PortfolioSparklineArea: Shape {
    let points: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = PortfolioSparkline(points: points).path(in: rect)
        guard points.count > 1 else { return path }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
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
    
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            iPadBody
        } else {
            compactBody
        }
    }

    private var ageAccentColor: Color {
        guard vehicle.status != "sold" else { return ColorTheme.secondary }
        switch daysInInventory {
        case 90...: return Color(red: 0.88, green: 0.27, blue: 0.32)
        case 60..<90: return Color(red: 0.93, green: 0.46, blue: 0.20)
        case 30..<60: return Color(red: 0.93, green: 0.62, blue: 0.14)
        default: return Color(red: 0.17, green: 0.68, blue: 0.23)
        }
    }

    private var compactBody: some View {
        let canSeeCost = permissionService.canViewVehicleCost()
        let canSeeProfit = permissionService.canViewVehicleProfit()

        return HStack(alignment: .top, spacing: 10) {
            if let id = vehicle.id {
                VehicleThumbnailView(vehicleID: id)
                    .frame(width: 110, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.07), radius: 5, y: 3)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 7) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(vehicle.displayNameWithInventory)
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(ColorTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)

                        HStack(spacing: 6) {
                            Text(vehicle.year.asYear())
                                .fontWeight(.bold)
                                .foregroundColor(ColorTheme.secondary)

                            if vehicle.mileage > 0 {
                                Text("•")
                                    .foregroundColor(ColorTheme.secondaryText.opacity(0.55))
                                Text("\(vehicle.mileage) km")
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ColorTheme.secondaryText)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 4) {
                        if vehicle.status != "sold" && daysInInventory > 0 {
                            DaysInInventoryBadge(days: daysInInventory)
                                .scaleEffect(0.88, anchor: .trailing)
                        }
                        StatusBadge(status: vehicle.status ?? "")
                            .scaleEffect(0.92, anchor: .trailing)
                    }
                }

                HStack(spacing: 6) {
                    if let inventoryLabel = vehicle.inventoryOrVINLabel {
                        metadataPill(inventoryLabel)
                    }

                    if permissionService.canViewVehicleCost() {
                        metadataPill(
                            String(format: "%lld exp".localizedString, Int64(viewModel.expenseCount(for: vehicle))),
                            icon: "wrench.and.screwdriver.fill"
                        )
                    }
                }

                if canSeeCost || canSeeProfit {
                    Divider()
                        .padding(.top, 1)

                    HStack(spacing: 0) {
                        if canSeeCost {
                            compactFinancialMetric(
                                title: "purchase_price".localizedString.uppercased(),
                                value: (vehicle.purchasePrice as Decimal? ?? 0).asCurrency(),
                                color: ColorTheme.primaryText,
                                alignment: .leading,
                                frameAlignment: .leading
                            )
                        }

                        if canSeeCost && (holdingCost > 0 || daysInInventory > 0) {
                            verticalDivider
                            compactFinancialMetric(
                                title: "holding_cost".localizedString.uppercased(),
                                value: holdingCost.asCurrency(),
                                color: holdingCost > 0 ? ColorTheme.warning : ColorTheme.primaryText,
                                alignment: .center,
                                frameAlignment: .center
                            )
                        }

                        if canSeeProfit, let p = profitValue() {
                            verticalDivider
                            compactFinancialMetric(
                                title: "profit".localizedString.uppercased(),
                                value: (p - holdingCost).asCurrency(),
                                color: (p - holdingCost) >= 0 ? ColorTheme.success : ColorTheme.danger,
                                alignment: .trailing,
                                frameAlignment: .trailing
                            )
                        } else if canSeeCost {
                            verticalDivider
                            compactFinancialMetric(
                                title: "total_cost".localizedString.uppercased(),
                                value: (viewModel.totalCost(for: vehicle) + holdingCost).asCurrency(),
                                color: ColorTheme.secondary,
                                alignment: .trailing,
                                frameAlignment: .trailing
                            )
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(ColorTheme.cardBackground)
        .overlay(alignment: .leading) {
            if vehicle.status != "sold" {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ageAccentColor)
                    .frame(width: 3)
                    .padding(.vertical, 9)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.08))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 6)
    }

    private func metadataPill(_ text: String, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(ColorTheme.secondaryText)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(ColorTheme.background)
        .clipShape(Capsule())
    }

    private func compactFinancialMetric(title: String, value: String, color: Color, alignment: HorizontalAlignment, frameAlignment: Alignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(title)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(ColorTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.58)

            Text(value)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.54)
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private func financialColumn(
        title: String,
        value: String,
        color: Color,
        weight: Font.Weight,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(ColorTheme.secondaryText)
                .tracking(0.5)

            Text(value)
                .font(.system(size: 15, weight: weight))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
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
        .overlay(alignment: .leading) {
            if vehicle.status != "sold" {
                Rectangle()
                    .fill(ageAccentColor)
                    .frame(width: 4)
                    .padding(.vertical, 10)
            }
        }
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
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(ColorTheme.background)

            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                Image(systemName: "car.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(ColorTheme.secondaryText.opacity(0.5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
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
        case "reserved": return Color(red: 0.55, green: 0.36, blue: 0.92)
        case "on_sale", "available": return Color(red: 0.18, green: 0.32, blue: 0.99)
        case "sold": return Color(red: 0.13, green: 0.62, blue: 0.30)
        case "in_transit": return Color(red: 0.93, green: 0.62, blue: 0.14)
        case "under_service": return Color(red: 0.88, green: 0.27, blue: 0.32)
        default: return Color(red: 0.45, green: 0.47, blue: 0.56)
        }
    }

    var body: some View {
        Text(statusText)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(statusColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
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
    private var mobileVehicleContent: some View {
        ZStack {
            ColorTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    mobileHeader
                        .padding(.horizontal, 14)

                    VehiclePortfolioHeroCard(viewModel: viewModel)
                        .padding(.horizontal, 14)

                    displayModePicker
                        .padding(.horizontal, 14)

                    VehicleStatusDashboard(viewModel: viewModel)
                        .padding(.horizontal, 14)

                    searchAndFilterHeader
                        .padding(.horizontal, 14)

                    if showAgingInventoryFocusBanner {
                        agingInventoryFocusBanner
                            .padding(.horizontal, 14)
                    }

                    vehicleList
                        .padding(.horizontal, 14)
                        .padding(.top, 2)
                }
                .padding(.top, 4)
                .padding(.bottom, listBottomPadding + 14)
            }
            .refreshable {
                if case .signedIn(let user) = sessionStore.status {
                    await cloudSyncManager.manualSync(user: user, force: true)
                    viewModel.fetchVehicles()
                }
            }
        }
    }

    private var mobileHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("vehicles".localizedString)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(ColorTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(String(format: "%lld vehicles in stock".localizedString, Int64(viewModel.totalVehiclesCount)))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ColorTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 12)

            if permissionService.can(.viewInventory), permissionService.canViewVehicleCost() {
                Button(action: handleAddVehicleTap) {
                    Image(systemName: "plus")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                        .background(
                            LinearGradient(
                                colors: [ColorTheme.secondary, ColorTheme.primary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())
                        .shadow(color: ColorTheme.primary.opacity(0.24), radius: 9, x: 0, y: 5)
                }
                .buttonStyle(.hapticScale)
                .accessibilityLabel("add_vehicle".localizedString)
            }
        }
    }

    private var displayModePicker: some View {
        HStack(spacing: 0) {
            ForEach(VehicleViewModel.DisplayMode.allCases) { mode in
                Button {
                    viewModel.displayMode = mode
                } label: {
                    Text(mode.title)
                        .font(.system(size: 14, weight: viewModel.displayMode == mode ? .bold : .medium))
                        .foregroundColor(viewModel.displayMode == mode ? ColorTheme.secondary : ColorTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            Group {
                                if viewModel.displayMode == mode {
                                    Capsule()
                                        .fill(ColorTheme.cardBackground)
                                        .shadow(color: Color.black.opacity(0.06), radius: 7, x: 0, y: 3)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(ColorTheme.secondaryBackground.opacity(0.76))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

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
                            ForEach(viewModel.vehicles, id: \.objectID) { vehicle in
                                iPadVehicleRow(vehicle)
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

    private var searchAndFilterHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(ColorTheme.secondaryText)

                TextField("search_vehicle_placeholder".localizedString, text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(ColorTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )

            Menu {
                Picker("Sort By".localizedString, selection: $viewModel.sortOption) {
                    ForEach(VehicleViewModel.SortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                toolbarChip(icon: "arrow.up.arrow.down", title: "Sort".localizedString, color: ColorTheme.secondary)
                    .frame(width: 76)
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
                    toolbarChip(
                        icon: "slider.horizontal.3",
                        title: "filters".localizedString,
                        color: viewModel.selectedStatus == "all" ? ColorTheme.primary : ColorTheme.secondary,
                        badge: viewModel.selectedStatus == "all" ? nil : "1"
                    )
                    .frame(width: viewModel.selectedStatus == "all" ? 92 : 104)
                }

                Button {
                    viewModel.sortOption = .daysDesc
                    viewModel.selectedStatus = "all"
                    viewModel.fetchVehicles()
                } label: {
                    toolbarIcon(icon: "flame.fill", color: ColorTheme.accent)
                }
                .buttonStyle(.hapticScale)
            }
        }
    }

    private func toolbarChip(icon: String, title: String, color: Color, badge: String? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            if let badge {
                Text(badge)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 19, height: 19)
                    .background(ColorTheme.secondary)
                    .clipShape(Circle())
            }
        }
        .foregroundColor(color)
        .padding(.horizontal, 9)
        .frame(height: 42)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func toolbarIcon(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(color)
            .frame(width: 42, height: 42)
            .background(ColorTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var vehicleList: some View {
        if viewModel.vehicles.isEmpty {
            emptyStateView
                .frame(minHeight: 320)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.vehicles, id: \.objectID) { vehicle in
                    NavigationLink(destination: VehicleDetailView(vehicle: vehicle)) {
                        VehicleCard(vehicle: vehicle, viewModel: viewModel)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        vehicleContextMenu(for: vehicle)
                    }
                }
            }
        }
    }
}

struct VehicleStatusDashboard: View {
    @ObservedObject var viewModel: VehicleViewModel

    var body: some View {
        HStack(spacing: 8) {
            if viewModel.displayMode == .sold {
                statusButton(
                    title: "sold".localizedString,
                    count: viewModel.soldCount,
                    color: ColorTheme.success,
                    icon: "checkmark.seal.fill",
                    isActive: true
                ) {
                    viewModel.displayMode = .sold
                }
            } else {
                statusButton(
                    title: "total".localizedString,
                    count: viewModel.totalVehiclesCount,
                    color: ColorTheme.secondary,
                    icon: "car.2.fill",
                    isActive: viewModel.selectedStatus == "all"
                ) {
                    viewModel.displayMode = .inventory
                    viewModel.selectedStatus = "all"
                }
            }

            statusButton(
                title: "on_sale".localizedString,
                count: viewModel.onSaleCount,
                color: ColorTheme.success,
                icon: "tag.fill",
                isActive: viewModel.displayMode == .inventory && viewModel.selectedStatus == "on_sale"
            ) {
                viewModel.displayMode = .inventory
                viewModel.selectedStatus = "on_sale"
            }

            statusButton(
                title: "reserved".localizedString,
                count: viewModel.inGarageCount,
                color: ColorTheme.accent,
                icon: "lock.fill",
                isActive: viewModel.displayMode == .inventory && viewModel.selectedStatus == "reserved"
            ) {
                viewModel.displayMode = .inventory
                viewModel.selectedStatus = "reserved"
            }

            statusButton(
                title: "in_transit".localizedString,
                count: viewModel.inTransitCount,
                color: ColorTheme.purple,
                icon: "box.truck.fill",
                isActive: viewModel.displayMode == .inventory && viewModel.selectedStatus == "in_transit"
            ) {
                viewModel.displayMode = .inventory
                viewModel.selectedStatus = "in_transit"
            }
        }
    }

    private func statusButton(
        title: String,
        count: Int,
        color: Color,
        icon: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            StatCard(title: title, count: count, color: color, icon: icon, isActive: isActive)
        }
        .buttonStyle(.hapticScale)
    }
}

struct StatCard: View {
    let title: String
    let count: Int
    let color: Color
    let icon: String
    var isActive: Bool = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(isActive ? .white : color)
                .frame(width: 30, height: 30)
                .background(isActive ? Color.white.opacity(0.24) : color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isActive ? .white.opacity(0.9) : ColorTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                Text("\(count)")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundColor(isActive ? .white : ColorTheme.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(
            Group {
                if isActive {
                    LinearGradient(
                        colors: [color, ColorTheme.secondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    ColorTheme.cardBackground
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(isActive ? color.opacity(0.15) : Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: isActive ? color.opacity(0.16) : Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
    }
}
