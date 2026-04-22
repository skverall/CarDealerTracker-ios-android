//
//  AddSaleView.swift
//  Ezcar24Business
//
//  Created by Shokhabbos Makhmudov on 20/11/2025.
//

import SwiftUI
import CoreData

struct AddSaleView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var saleType: SaleType = .vehicle
    
    enum SaleType: String, CaseIterable {
        case vehicle, parts
        
        @MainActor
        var title: String {
             switch self {
             case .vehicle: return "vehicle".localizedString
             case .parts: return "parts_tab_title".localizedString
             }
        }
    }

    var body: some View {
        ZStack {
            ColorTheme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                 // Header
                 headerView
                 
                 // Picker
                 Picker("Sale Type", selection: $saleType) {
                     ForEach(SaleType.allCases, id: \.self) { type in
                         Text(type.title).tag(type)
                     }
                 }
                 .pickerStyle(.segmented)
                 .padding(.horizontal, 20)
                 .padding(.bottom, 10)
                 
                 // Form
                 switch saleType {
                 case .vehicle:
                     VehicleSaleForm(showHeader: false)
                 case .parts:
                     AddPartSaleView(showHeader: false)
                 }
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(width: 36, height: 36)
                    .background(ColorTheme.secondaryBackground)
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Text("new_sale".localizedString)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)
            
            Spacer()
            
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }
}

private struct VehicleSaleForm: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject private var permissionService = PermissionService.shared
    var showHeader: Bool = true
    
    // Form State
    @State private var selectedVehicle: Vehicle?
    @State private var amount: String = ""
    @State private var date: Date = Date()
    @State private var buyerName: String = ""
    @State private var buyerPhone: String = ""
    @State private var paymentMethod: String = "payment_method_cash".localizedString
    @State private var notes: String = ""
    @State private var vatRefundPercent: String = ""
    
    // UI State
    @State private var showVehicleSheet: Bool = false
    @State private var isSaving: Bool = false
    @State private var showSavedToast: Bool = false
    @State private var saveError: String? = nil
    
    @State private var showDatePicker: Bool = false
    @State private var vehicleSearchText: String = ""
    @State private var dealDeskSettings: DealDeskSettings?
    @State private var showDealDesk: Bool = false
    @State private var isLoadingDealDeskSettings: Bool = false
    @State private var dealDeskLoadError: String?
    @State private var lastDealDeskVehicleObjectID: NSManagedObjectID?
    
    private var paymentMethods: [String] {
        ["payment_method_cash".localizedString, 
         "payment_method_bank_transfer".localizedString, 
         "payment_method_cheque".localizedString, 
         "payment_method_finance".localizedString, 
         "payment_method_other".localizedString]
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Vehicle.make, ascending: true)],
        predicate: NSPredicate(format: "status != 'sold'"),
        animation: .default)
    private var vehicles: FetchedResults<Vehicle>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FinancialAccount.accountType, ascending: true)],
        animation: .default)
    private var accounts: FetchedResults<FinancialAccount>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Client.updatedAt, ascending: false)],
        animation: .default)
    private var clients: FetchedResults<Client>

    @State private var selectedAccount: FinancialAccount?
    
    // Client CRM Integration
    @State private var showClientPicker: Bool = false
    @State private var selectedClient: Client?
    
    // Computed Properties for Financial Preview
    var purchasePrice: Decimal {
        selectedVehicle?.purchasePrice?.decimalValue ?? 0
    }
    
    var totalExpenses: Decimal {
        guard let v = selectedVehicle, let expenses = v.expenses as? Set<Expense> else { return 0 }
        return expenses.reduce(0) { $0 + ($1.amount?.decimalValue ?? 0) }
    }
    
    var totalCost: Decimal {
        purchasePrice + totalExpenses
    }
    
    var salePrice: Decimal {
        Decimal(string: amount.filter { "0123456789.".contains($0) }) ?? 0
    }
    
    var estimatedProfit: Decimal {
        salePrice - totalCost
    }

    private var canViewFinancials: Bool {
        permissionService.can(.viewFinancials)
    }
    
    var isFormValid: Bool {
        selectedVehicle != nil && salePrice > 0 && !buyerName.isEmpty
    }

    private var selectedVehicleObjectID: NSManagedObjectID? {
        selectedVehicle?.objectID
    }

    private var dealDeskEnabledForCurrentOrg: Bool {
        dealDeskSettings?.isEnabled == true
    }

    private var shouldShowLegacySaleFields: Bool {
        guard selectedVehicle != nil else { return true }
        if isLoadingDealDeskSettings {
            return false
        }
        return !dealDeskEnabledForCurrentOrg
    }

    private var shouldShowDealDeskLauncher: Bool {
        selectedVehicle != nil && !isLoadingDealDeskSettings && dealDeskEnabledForCurrentOrg
    }

    private var primaryButtonTitle: String {
        if shouldShowDealDeskLauncher {
            return "Open Deal Desk"
        }
        return isSaving ? "saving".localizedString : "complete_sale".localizedString
    }

    private var isPrimaryButtonEnabled: Bool {
        if shouldShowDealDeskLauncher {
            return selectedVehicle != nil
        }
        return isFormValid
    }
    
    var body: some View {
        ZStack {
            if showHeader {
                ColorTheme.background.ignoresSafeArea()
                    .onTapToDismissKeyboard()
            }
            
            VStack(spacing: 0) {
                // Header
                if showHeader {
                    headerView
                }
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Vehicle Selection
                        vehicleSelectionSection
                        
                        if isLoadingDealDeskSettings, selectedVehicle != nil {
                            dealDeskStatusCard(
                                title: "Checking Deal Desk settings",
                                subtitle: "Loading dealer defaults for this sale."
                            ) {
                                ProgressView()
                                    .tint(ColorTheme.primary)
                            }
                        }

                        if shouldShowDealDeskLauncher {
                            dealDeskLaunchSection
                        }

                        // Financial Preview Card (legacy flow only)
                        if selectedVehicle != nil && shouldShowLegacySaleFields {
                            financialPreviewCard
                        }
                        
                        if shouldShowLegacySaleFields {
                            saleDetailsSection
                            accountSelectionSection
                            buyerDetailsSection
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.vertical, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            
            // Floating Save Button
            VStack {
                Spacer()
                saveButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
            
            // Toast Overlay
            if showSavedToast {
                savedToast
            }
        }
        .sheet(isPresented: $showVehicleSheet) {
            vehicleSelectionSheet
        }
        .sheet(isPresented: $showClientPicker) {
            clientSelectionSheet
        }
        .sheet(isPresented: $showDealDesk) {
            if let selectedVehicle, let dealDeskSettings {
                DealDeskSaleView(
                    vehicle: selectedVehicle,
                    settings: dealDeskSettings,
                    initialBuyerName: buyerName,
                    initialBuyerPhone: buyerPhone,
                    initialNotes: notes,
                    initialDate: date,
                    initialAccount: selectedAccount
                ) { request in
                    buyerName = request.buyerName
                    buyerPhone = request.buyerPhone
                    notes = request.notes
                    date = request.date
                    selectedAccount = request.account
                    saveVehicleSale(request)
                }
            }
        }
        .sheet(isPresented: $showDatePicker) {
            VStack {
                DatePicker("Select Date", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .onChange(of: date) { old, new in
                        showDatePicker = false
                    }
                
                Button("done".localizedString) {
                    showDatePicker = false
                }
                .padding()
                .foregroundColor(ColorTheme.primary)
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            if accounts.isEmpty {
                createDefaultAccounts()
            }
        }
        .onChange(of: selectedVehicleObjectID) { _, _ in
            Task {
                await refreshDealDeskStateForSelection()
            }
        }
    }
    
    // MARK: - UI Components
    
    private var headerView: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(width: 36, height: 36)
                    .background(ColorTheme.secondaryBackground)
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Text("new_sale".localizedString)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)
            
            Spacer()
            
            // Placeholder for balance
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(ColorTheme.background)
    }
    
    private var vehicleSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("vehicle_section_title".localizedString)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(ColorTheme.secondaryText)
                .tracking(1)
                .padding(.horizontal, 20)
            
            Button {
                showVehicleSheet = true
            } label: {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(selectedVehicle != nil ? ColorTheme.primary.opacity(0.1) : ColorTheme.secondaryBackground)
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "car.fill")
                            .font(.system(size: 20))
                            .foregroundColor(selectedVehicle != nil ? ColorTheme.primary : ColorTheme.secondaryText)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if let vehicle = selectedVehicle {
                            Text(vehicle.displayNameWithInventory)
                                .font(.headline)
                                .foregroundColor(ColorTheme.primaryText)
                            Text(vehicle.inventoryOrVINLabel ?? "No ID")
                                .font(.caption)
                                .foregroundColor(ColorTheme.secondaryText)
                        } else {
                            Text("select_vehicle".localizedString)
                                .font(.headline)
                                .foregroundColor(ColorTheme.primaryText)
                            Text("tap_to_choose_vehicle".localizedString)
                                .font(.caption)
                                .foregroundColor(ColorTheme.secondaryText)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(ColorTheme.tertiaryText)
                }
                .padding(16)
                .background(ColorTheme.cardBackground)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var financialPreviewCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("financial_preview".localizedString)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(ColorTheme.secondaryText)
                Spacer()
            }
            
            HStack(spacing: 20) {
                if canViewFinancials {
                    financialMetric(title: "total_cost".localizedString, amount: totalCost, color: ColorTheme.primaryText)
                    Divider()
                }

                financialMetric(title: "sale_price".localizedString, amount: salePrice, color: ColorTheme.primary)

                if canViewFinancials {
                    Divider()
                    financialMetric(
                        title: "estimated_profit".localizedString,
                        amount: estimatedProfit,
                        color: estimatedProfit >= 0 ? ColorTheme.success : ColorTheme.danger
                    )
                }
            }
        }
        .padding(16)
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .padding(.horizontal, 20)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
    }

    private var dealDeskLaunchSection: some View {
        dealDeskStatusCard(
            title: "Deal Desk ready",
            subtitle: "Use the new sale calculator for taxes, fees, due today, and finance."
        ) {
            Button {
                showDealDesk = true
            } label: {
                Label("Open Deal Desk", systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(ColorTheme.primary)
                    .clipShape(Capsule())
            }
        }
    }

    private func dealDeskStatusCard<Accessory: View>(
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                }
                Spacer()
                accessory()
            }

            if let dealDeskLoadError {
                Text(dealDeskLoadError)
                    .font(.caption)
                    .foregroundColor(ColorTheme.danger)
            }
        }
        .padding(16)
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .padding(.horizontal, 20)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
    }
    
    private func financialMetric(title: String, amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(ColorTheme.secondaryText)
            Text(amount.asCurrency())
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var saleDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("sale_details".localizedString)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(ColorTheme.secondaryText)
                .tracking(1)
                .padding(.horizontal, 20)
            
            VStack(spacing: 0) {
                // Amount Input
                HStack(spacing: 12) {
                    Text(regionSettings.selectedRegion.currencySymbol)
                        .font(.headline)
                        .foregroundColor(ColorTheme.tertiaryText)
                        .frame(width: 40)
                    
                    TextField("sale_amount".localizedString, text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.headline)
                        .onChange(of: amount) { old, new in
                            let filtered = new.filter { "0123456789.".contains($0) }
                            if filtered != new { amount = filtered }
                        }
                }
                .padding(16)
                
                Divider().padding(.leading, 20)
                
                // Date Picker
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                    
                    Text("sale_date".localizedString)
                        .font(.body)
                        .foregroundColor(ColorTheme.primaryText)
                    
                    Spacer()
                    
                    Button {
                        showDatePicker = true
                    } label: {
                        Text(date, formatter: dateFormatter)
                            .foregroundColor(ColorTheme.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(ColorTheme.primary.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding(16)
                
                Divider().padding(.leading, 20)
                
                // Payment Method
                HStack(spacing: 12) {
                    Image(systemName: "creditcard")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                    
                    Text("payment_method".localizedString)
                        .font(.body)
                        .foregroundColor(ColorTheme.primaryText)
                    
                    Spacer()
                    
                    Picker("Payment", selection: $paymentMethod) {
                        ForEach(paymentMethods, id: \.self) { method in
                            Text(String(localized: String.LocalizationValue(method))).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .accentColor(ColorTheme.primary)
                }
                .padding(16)
                
                Divider().padding(.leading, 20)
                
                // VAT Refund Percentage
                HStack(spacing: 12) {
                    Image(systemName: "percent")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                    
                    Text("vat_refund_percent".localizedString)
                        .font(.body)
                        .foregroundColor(ColorTheme.primaryText)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        TextField("0", text: $vatRefundPercent)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .onChange(of: vatRefundPercent) { old, new in
                                let filtered = new.filter { "0123456789.".contains($0) }
                                if filtered != new { vatRefundPercent = filtered }
                            }
                        
                        Text("%")
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(ColorTheme.secondaryBackground)
                    .cornerRadius(8)
                }
                .padding(16)
                
                // Show calculated VAT refund amount if percentage is entered
                if let percent = Decimal(string: vatRefundPercent), percent > 0,
                   let saleAmount = Decimal(string: amount), saleAmount > 0 {
                    let refundAmount = saleAmount * percent / 100
                    HStack {
                        Spacer()
                        Text("vat_refund_amount".localizedString + ": ")
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                        Text(refundAmount.asCurrency())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(ColorTheme.success)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .padding(.horizontal, 20)
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
        }
    }

    private var accountSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("deposit_to".localizedString)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(ColorTheme.secondaryText)
                .tracking(1)
                .padding(.horizontal, 20)
            
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "building.columns.fill")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                    
                    Text("account_label".localizedString)
                        .font(.body)
                        .foregroundColor(ColorTheme.primaryText)
                    
                    Spacer()
                    
                    Picker("Account", selection: $selectedAccount) {
                        Text("none".localizedString).tag(nil as FinancialAccount?)
                        ForEach(accounts) { account in
                            Text(account.displayTitle).tag(account as FinancialAccount?)
                        }
                    }
                    .pickerStyle(.menu)
                    .accentColor(ColorTheme.primary)
                }
                .padding(16)
            }
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .padding(.horizontal, 20)
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
        }
    }
    
    private var buyerDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("buyer_info".localizedString)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(ColorTheme.secondaryText)
                    .tracking(1)
                
                Spacer()
                
                Button {
                    showClientPicker = true
                } label: {
                    Label(selectedClient == nil ? "select_client".localizedString : "change_client".localizedString, systemImage: "person.crop.circle.badge.plus")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(ColorTheme.primary)
                }
            }
            .padding(.horizontal, 20)
            
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "person.fill")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                    
                    TextField("buyer_name".localizedString, text: $buyerName)
                }
                .padding(16)
                
                Divider().padding(.leading, 52)
                
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                    
                    TextField("phone_number".localizedString, text: $buyerPhone)
                        .keyboardType(.phonePad)
                }
                .padding(16)
                
                Divider().padding(.leading, 52)
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "note.text")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                        .padding(.top, 4)
                    
                    TextField("notes_optional".localizedString, text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                .padding(16)
            }
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .padding(.horizontal, 20)
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
        }
    }
    
    private var saveButton: some View {
        Button(action: handlePrimaryAction) {
            HStack {
                if isSaving && !shouldShowDealDeskLauncher {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 8)
                }
                Text(primaryButtonTitle)
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isPrimaryButtonEnabled ? ColorTheme.primary : ColorTheme.secondaryText.opacity(0.3))
            .cornerRadius(20)
            .shadow(color: isPrimaryButtonEnabled ? ColorTheme.primary.opacity(0.3) : Color.clear, radius: 10, y: 5)
        }
        .disabled(!isPrimaryButtonEnabled || isSaving || isLoadingDealDeskSettings)
    }
    
    private var savedToast: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                Text("sale_recorded".localizedString)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(ColorTheme.cardBackground)
            .cornerRadius(30)
            .shadow(color: Color.black.opacity(0.1), radius: 20, y: 10)
            .padding(.bottom, 40)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .zIndex(100)
    }
    
    private var vehicleSelectionSheet: some View {
        VehicleSelectionSheet(
            isPresented: $showVehicleSheet,
            searchText: $vehicleSearchText,
            selectedVehicle: $selectedVehicle,
            vehicles: Array(vehicles)
        )
    }
    
    // MARK: - Client Selection Sheet
    
    private var clientSelectionSheet: some View {
        NavigationStack {
            List {
                if clients.isEmpty {
                    Text("No clients found in CRM.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(clients) { client in
                        Button {
                            selectedClient = client
                            buyerName = client.name ?? ""
                            buyerPhone = client.phone ?? ""
                            // Pre-fill notes if helpful? Maybe not.
                            showClientPicker = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(client.name ?? "unknown".localizedString)
                                        .font(.headline)
                                    if let phone = client.phone {
                                        Text(phone)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedClient == client {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(ColorTheme.primary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("select_client".localizedString)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localizedString) { showClientPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Logic

    private func handlePrimaryAction() {
        if shouldShowDealDeskLauncher {
            showDealDesk = true
            return
        }
        saveSale()
    }

    @MainActor
    private func refreshDealDeskStateForSelection() async {
        guard let selectedVehicle else {
            dealDeskSettings = nil
            dealDeskLoadError = nil
            lastDealDeskVehicleObjectID = nil
            return
        }

        guard let organizationId = sessionStore.activeOrganizationId ?? CloudSyncEnvironment.currentDealerId else {
            dealDeskSettings = nil
            dealDeskLoadError = nil
            return
        }

        isLoadingDealDeskSettings = true
        dealDeskLoadError = nil
        let loadedSettings = await sessionStore.loadDealDeskSettings(for: organizationId)
        isLoadingDealDeskSettings = false
        dealDeskSettings = loadedSettings

        guard let loadedSettings else {
            dealDeskLoadError = "Deal Desk settings unavailable. Using classic sale form."
            return
        }

        guard loadedSettings.isEnabled else {
            lastDealDeskVehicleObjectID = nil
            return
        }

        guard lastDealDeskVehicleObjectID != selectedVehicle.objectID else { return }
        lastDealDeskVehicleObjectID = selectedVehicle.objectID
        showDealDesk = true
    }
    
    private func saveSale() {
        guard let vehicle = selectedVehicle else { return }
        let vatPercent = Decimal(string: sanitizedDecimalInput(vatRefundPercent))
        let request = VehicleSaleSaveRequest(
            vehicle: vehicle,
            saleAmount: salePrice,
            date: date,
            buyerName: buyerName,
            buyerPhone: buyerPhone,
            paymentMethod: paymentMethod,
            account: selectedAccount,
            notes: notes,
            vatRefundPercent: vatPercent,
            dealDeskSnapshot: nil
        )
        saveVehicleSale(request)
    }

    private func saveVehicleSale(_ request: VehicleSaleSaveRequest) {
        isSaving = true
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        
        // Simulate delay for UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            do {
                // 1. Create Sale Record
                let newSale = Sale(context: viewContext)
                newSale.id = UUID()
                newSale.vehicle = request.vehicle
                newSale.amount = NSDecimalNumber(decimal: request.saleAmount)
                newSale.date = request.date
                newSale.buyerName = request.buyerName
                newSale.buyerPhone = request.buyerPhone
                newSale.paymentMethod = request.paymentMethod
                newSale.account = request.account
                newSale.createdAt = Date()
                newSale.updatedAt = newSale.createdAt
                if let snapshot = request.dealDeskSnapshot {
                    newSale.applyDealDeskSnapshot(snapshot)
                } else {
                    newSale.clearDealDeskSnapshot()
                }

                if let vatPercent = request.vatRefundPercent, vatPercent > 0 {
                    newSale.vatRefundPercent = NSDecimalNumber(decimal: vatPercent)
                    let vatAmount = request.saleAmount * vatPercent / 100
                    newSale.vatRefundAmount = NSDecimalNumber(decimal: vatAmount)
                }

                // 2. Update Vehicle Status
                let vehicle = request.vehicle
                vehicle.status = "sold"
                vehicle.salePrice = NSDecimalNumber(decimal: request.saleAmount)
                vehicle.saleDate = request.date
                vehicle.buyerName = request.buyerName
                vehicle.buyerPhone = request.buyerPhone
                vehicle.paymentMethod = request.paymentMethod
                let trimmedNotes = request.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedNotes.isEmpty {
                    let currentNotes = vehicle.notes ?? ""
                    let newNote = "\n[Sale Note]: \(trimmedNotes)"
                    vehicle.notes = currentNotes + newNote
                }
                vehicle.updatedAt = Date()
                
                // 3. Update Account Balance
                if let account = request.account {
                    let currentBalance = account.balance?.decimalValue ?? 0
                    account.balance = NSDecimalNumber(decimal: currentBalance + request.accountDepositAmount)
                    account.updatedAt = Date()
                }
                
                try viewContext.save()
                AppReviewManager.shared.handleSaleAdded(context: viewContext)
                
                if let dealerId = CloudSyncEnvironment.currentDealerId {
                    Task {
                        // 4. Client CRM Sync (NEW)
                        // Logic:
                        // - If specific client selected -> Update status + Add Interaction
                        // - If NO client selected -> Create NEW Client + Add Interaction
                        
                        let clientToUse: Client
                        if let selected = selectedClient {
                            clientToUse = selected
                            clientToUse.updatedAt = Date()
                        } else {
                            // Create new client from entered data
                            let newClient = Client(context: viewContext)
                            newClient.id = UUID()
                            newClient.name = buyerName
                            newClient.phone = buyerPhone
                            newClient.createdAt = Date()
                            newClient.updatedAt = Date()
                            newClient.vehicle = vehicle // Associate purchased vehicle
                            clientToUse = newClient
                        }
                        
                        // Update Client Status & Details
                        clientToUse.clientStatus = .sold
                        clientToUse.vehicle = vehicle
                        
                        // Create "Closed Won" Interaction
                        let interaction = ClientInteraction(context: viewContext)
                        interaction.id = UUID()
                        interaction.title = "Vehicle Purchased"
                        interaction.detail = "Purchased \(vehicle.make ?? "") \(vehicle.model ?? "") for \(request.saleAmount.asCurrencyFallback())"
                        interaction.occurredAt = Date()
                        interaction.stage = InteractionStage.closedWon.rawValue
                        interaction.value = NSDecimalNumber(decimal: request.saleAmount)
                        interaction.client = clientToUse
                        
                        try? viewContext.save()
                        
                        // Sync Client & Interaction
                        await CloudSyncManager.shared?.upsertClient(clientToUse, dealerId: dealerId)
                        // Note: We need upsertInteraction in CloudSyncManager, but we can rely on Client sync if it cascades?
                        // Supabase RPC 'sync_clients' usually handles the client record. Interactions might need separate table sync or be included.
                        // Checking CloudSyncManager... it seems to handle entities separately.
                        // Assuming basic Client sync for now. Interaction logs might not sync if there's no specific RPC for them yet
                        // OR if they are synced as part of Client payload?
                        // Based on existing code, `upsertClient` only sends Client data.
                        // We should check if we can sync interaction. If not, at least the client is created/updated.
                        
                        await CloudSyncManager.shared?.upsertSale(newSale, dealerId: dealerId)
                        await CloudSyncManager.shared?.upsertVehicle(vehicle, dealerId: dealerId)
                        
                        if let account = request.account {
                            await CloudSyncManager.shared?.upsertFinancialAccount(account, dealerId: dealerId)
                        }
                    }
                }
                
                generator.notificationOccurred(.success)
                withAnimation {
                    showSavedToast = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
                
            } catch {
                isSaving = false
                generator.notificationOccurred(.error)
                print("Failed to save sale: \(error)")
            }
        }
    }
    
    private func createDefaultAccounts() {
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
            print("Failed to create default accounts: \(error)")
        }
    }
}

private struct VehicleSaleSaveRequest {
    let vehicle: Vehicle
    let saleAmount: Decimal
    let date: Date
    let buyerName: String
    let buyerPhone: String
    let paymentMethod: String
    let account: FinancialAccount?
    let notes: String
    let vatRefundPercent: Decimal?
    let dealDeskSnapshot: DealDeskSnapshot?

    var accountDepositAmount: Decimal {
        dealDeskSnapshot?.totals.cashReceivedNow ?? saleAmount
    }
}

private struct DealDeskSaleView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var regionSettings: RegionSettingsManager

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FinancialAccount.accountType, ascending: true)],
        animation: .default
    )
    private var accounts: FetchedResults<FinancialAccount>

    let vehicle: Vehicle
    let settings: DealDeskSettings
    let onSave: (VehicleSaleSaveRequest) -> Void

    @State private var salePriceText: String
    @State private var buyerName: String
    @State private var buyerPhone: String
    @State private var notes: String
    @State private var date: Date
    @State private var selectedAccount: FinancialAccount?
    @State private var paymentMethodCode: String
    @State private var downPaymentText: String
    @State private var aprText: String
    @State private var termMonthsText: String
    @State private var jurisdictionCode: String
    @State private var taxLines: [DealDeskLine]
    @State private var feeLines: [DealDeskLine]
    @State private var isPriceExpanded = true
    @State private var isTaxesExpanded = true
    @State private var isFeesExpanded = false
    @State private var isPaymentsExpanded = false

    init(
        vehicle: Vehicle,
        settings: DealDeskSettings,
        initialBuyerName: String,
        initialBuyerPhone: String,
        initialNotes: String,
        initialDate: Date,
        initialAccount: FinancialAccount?,
        onSave: @escaping (VehicleSaleSaveRequest) -> Void
    ) {
        self.vehicle = vehicle
        self.settings = settings
        self.onSave = onSave

        let startingSalePrice = vehicle.askingPrice?.decimalValue ?? vehicle.salePrice?.decimalValue ?? 0
        let templateCode = settings.defaultTemplateCode
        _salePriceText = State(initialValue: initialDecimalText(startingSalePrice))
        _buyerName = State(initialValue: initialBuyerName)
        _buyerPhone = State(initialValue: initialBuyerPhone)
        _notes = State(initialValue: initialNotes)
        _date = State(initialValue: initialDate)
        _selectedAccount = State(initialValue: initialAccount)
        _paymentMethodCode = State(initialValue: "cash")
        _downPaymentText = State(initialValue: initialDecimalText(startingSalePrice))
        _aprText = State(initialValue: "")
        _termMonthsText = State(initialValue: "")
        _jurisdictionCode = State(initialValue: DealDeskTemplateCatalog.defaultJurisdictionCode(for: templateCode))
        _taxLines = State(initialValue: settings.seededTaxLines)
        _feeLines = State(initialValue: settings.seededFeeLines)
    }

    private var salePrice: Decimal {
        decimalFromInput(salePriceText)
    }

    private var dueToday: Decimal {
        if paymentMethodCode == "finance" {
            return min(max(decimalFromInput(downPaymentText), 0), outTheDoorTotal)
        }
        return outTheDoorTotal
    }

    private var taxTotal: Decimal {
        taxLines.reduce(0) { partialResult, line in
            partialResult + line.resolvedAmount(for: salePrice)
        }
    }

    private var feeTotal: Decimal {
        feeLines.reduce(0) { partialResult, line in
            partialResult + line.resolvedAmount(for: salePrice)
        }
    }

    private var outTheDoorTotal: Decimal {
        salePrice + taxTotal + feeTotal
    }

    private var amountFinanced: Decimal {
        paymentMethodCode == "finance" ? max(0, outTheDoorTotal - dueToday) : 0
    }

    private var monthlyEstimate: Decimal? {
        guard paymentMethodCode == "finance", amountFinanced > 0 else { return nil }
        guard let termMonths = Int(termMonthsText), termMonths > 0 else { return nil }
        guard let aprPercent = optionalDecimalFromInput(aprText) else { return nil }

        let principal = NSDecimalNumber(decimal: amountFinanced).doubleValue
        let monthlyRate = NSDecimalNumber(decimal: aprPercent).doubleValue / 1200
        if monthlyRate == 0 {
            return Decimal(principal / Double(termMonths))
        }

        let factor = pow(1 + monthlyRate, Double(termMonths))
        let payment = principal * monthlyRate * factor / (factor - 1)
        return Decimal(payment)
    }

    private var canSave: Bool {
        salePrice > 0 && !buyerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var summaryItems: [(String, String)] {
        var items: [(String, String)] = [
            ("Total", outTheDoorTotal.asCurrency()),
            ("Due today", dueToday.asCurrency()),
            ("Financed", amountFinanced.asCurrency())
        ]
        if let monthlyEstimate {
            items.append(("Monthly", monthlyEstimate.asCurrency()))
        }
        return items
    }

    private var paymentMethodOptions: [(String, String)] {
        [
            ("cash", localizedPaymentMethodLabel(for: "cash")),
            ("finance", localizedPaymentMethodLabel(for: "finance")),
            ("bank_transfer", localizedPaymentMethodLabel(for: "bank_transfer")),
            ("cheque", localizedPaymentMethodLabel(for: "cheque")),
            ("other", localizedPaymentMethodLabel(for: "other"))
        ]
    }

    private var jurisdictionOptions: [DealDeskJurisdictionOption] {
        DealDeskTemplateCatalog.jurisdictionOptions(for: settings.defaultTemplateCode)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    summaryCard

                    ScrollView {
                        VStack(spacing: 16) {
                            dealDeskSection(title: "Price", isExpanded: $isPriceExpanded) {
                                VStack(spacing: 14) {
                                    if settings.defaultTemplateCode != .generic {
                                        Picker("Jurisdiction", selection: $jurisdictionCode) {
                                            ForEach(jurisdictionOptions) { option in
                                                Text(option.title).tag(option.code)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                    }

                                    HStack(spacing: 12) {
                                        Text(regionSettings.selectedRegion.currencySymbol)
                                            .foregroundColor(ColorTheme.secondaryText)
                                        TextField("Vehicle sale price", text: $salePriceText)
                                            .keyboardType(.decimalPad)
                                            .onChange(of: salePriceText) { _, newValue in
                                                salePriceText = sanitizedDecimalInput(newValue)
                                            }
                                    }

                                    DatePicker("Sale date", selection: $date, displayedComponents: .date)

                                    TextField("Buyer name", text: $buyerName)
                                    TextField("Buyer phone", text: $buyerPhone)
                                        .keyboardType(.phonePad)
                                    TextField("Notes", text: $notes, axis: .vertical)
                                        .lineLimit(2...4)
                                }
                            }

                            if !taxLines.isEmpty {
                                dealDeskSection(title: "Taxes", isExpanded: $isTaxesExpanded) {
                                    VStack(spacing: 12) {
                                        ForEach($taxLines) { $line in
                                            DealDeskEditableLineRow(
                                                currencySymbol: regionSettings.selectedRegion.currencySymbol,
                                                line: $line
                                            )
                                        }
                                    }
                                }
                            }

                            if !feeLines.isEmpty {
                                dealDeskSection(title: "Fees", isExpanded: $isFeesExpanded) {
                                    VStack(spacing: 12) {
                                        ForEach($feeLines) { $line in
                                            DealDeskEditableLineRow(
                                                currencySymbol: regionSettings.selectedRegion.currencySymbol,
                                                line: $line
                                            )
                                        }
                                    }
                                }
                            }

                            dealDeskSection(title: "Payments", isExpanded: $isPaymentsExpanded) {
                                VStack(spacing: 14) {
                                    Picker("Payment method", selection: $paymentMethodCode) {
                                        ForEach(paymentMethodOptions, id: \.0) { option in
                                            Text(option.1).tag(option.0)
                                        }
                                    }
                                    .pickerStyle(.menu)

                                    Picker("Deposit to", selection: $selectedAccount) {
                                        Text("none".localizedString).tag(nil as FinancialAccount?)
                                        ForEach(accounts) { account in
                                            Text(account.displayTitle).tag(account as FinancialAccount?)
                                        }
                                    }
                                    .pickerStyle(.menu)

                                    if paymentMethodCode == "finance" {
                                        HStack(spacing: 12) {
                                            Text(regionSettings.selectedRegion.currencySymbol)
                                                .foregroundColor(ColorTheme.secondaryText)
                                            TextField("Down payment", text: $downPaymentText)
                                                .keyboardType(.decimalPad)
                                                .onChange(of: downPaymentText) { _, newValue in
                                                    downPaymentText = sanitizedDecimalInput(newValue)
                                                }
                                        }

                                        HStack(spacing: 12) {
                                            TextField("APR %", text: $aprText)
                                                .keyboardType(.decimalPad)
                                                .onChange(of: aprText) { _, newValue in
                                                    aprText = sanitizedDecimalInput(newValue)
                                                }
                                            TextField("Term months", text: $termMonthsText)
                                                .keyboardType(.numberPad)
                                                .onChange(of: termMonthsText) { _, newValue in
                                                    termMonthsText = newValue.filter(\.isNumber)
                                                }
                                        }
                                    } else {
                                        Text("Full customer total is collected today.")
                                            .font(.subheadline)
                                            .foregroundColor(ColorTheme.secondaryText)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 120)
                    }
                }
            }
            .navigationTitle(vehicle.displayNameWithInventory)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let snapshot = DealDeskSnapshot(
                        templateCode: settings.defaultTemplateCode.rawValue,
                        templateVersion: settings.templateVersion,
                        jurisdictionType: DealDeskTemplateCatalog.defaultJurisdictionType(for: settings.defaultTemplateCode),
                        jurisdictionCode: jurisdictionCode,
                        taxLines: taxLines,
                        feeLines: feeLines,
                        paymentPlan: DealDeskPaymentPlan(
                            methodCode: paymentMethodCode,
                            downPayment: dueToday,
                            aprPercent: optionalDecimalFromInput(aprText),
                            termMonths: Int(termMonthsText)
                        ),
                        totals: DealDeskTotals(
                            salePrice: salePrice,
                            taxTotal: taxTotal,
                            feeTotal: feeTotal,
                            outTheDoorTotal: outTheDoorTotal,
                            cashReceivedNow: dueToday,
                            amountFinanced: amountFinanced,
                            monthlyPaymentEstimate: monthlyEstimate
                        )
                    )
                    let request = VehicleSaleSaveRequest(
                        vehicle: vehicle,
                        saleAmount: salePrice,
                        date: date,
                        buyerName: buyerName.trimmingCharacters(in: .whitespacesAndNewlines),
                        buyerPhone: buyerPhone.trimmingCharacters(in: .whitespacesAndNewlines),
                        paymentMethod: localizedPaymentMethodLabel(for: paymentMethodCode),
                        account: selectedAccount,
                        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                        vatRefundPercent: nil,
                        dealDeskSnapshot: snapshot
                    )
                    onSave(request)
                    dismiss()
                } label: {
                    Text("Save Deal Desk Sale")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSave ? ColorTheme.primary : ColorTheme.secondaryText.opacity(0.3))
                        .cornerRadius(20)
                }
                .disabled(!canSave)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(ColorTheme.background.opacity(0.96))
            }
            .onAppear {
                if selectedAccount == nil {
                    selectedAccount = accounts.first(where: { ($0.accountType ?? "").localizedCaseInsensitiveContains("cash") })
                        ?? accounts.first
                }
            }
        }
    }

    private var summaryCard: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            ForEach(summaryItems, id: \.0) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                    Text(item.1)
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(ColorTheme.cardBackground)
                .cornerRadius(16)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(ColorTheme.background)
    }

    private func dealDeskSection<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            content()
                .padding(.top, 12)
        } label: {
            Text(title)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)
        }
        .padding(16)
        .background(ColorTheme.cardBackground)
        .cornerRadius(18)
    }
}

struct DealDeskSettingsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @ObservedObject private var permissionService = PermissionService.shared

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveSuccess = false
    @State private var settings = DealDeskTemplateCatalog.defaultSettings(for: .generic, isEnabled: false)
    @State private var taxLines = DealDeskTemplateCatalog.defaultTaxLines(for: .generic)
    @State private var feeLines = DealDeskTemplateCatalog.defaultFeeLines(for: .generic)

    private var canEdit: Bool {
        permissionService.currentRole == "owner" || permissionService.currentRole == "admin"
    }

    var body: some View {
        Form {
            Section {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    Toggle("Enable Deal Desk", isOn: $settings.isEnabled)
                        .disabled(!canEdit || isSaving)
                }
            } footer: {
                Text("Existing dealers stay off until someone turns this on. Old sales stay untouched.")
            }

            Section("Default template") {
                Picker("Business Region", selection: $settings.businessRegionCode) {
                    ForEach(DealDeskBusinessRegionCode.allCases) { region in
                        Text(region.displayName).tag(region)
                    }
                }
                .disabled(!canEdit || isSaving)
                .onChange(of: settings.businessRegionCode) { _, newValue in
                    settings.defaultTemplateCode = newValue.defaultTemplateCode
                    taxLines = DealDeskTemplateCatalog.defaultTaxLines(for: newValue.defaultTemplateCode)
                    feeLines = DealDeskTemplateCatalog.defaultFeeLines(for: newValue.defaultTemplateCode)
                }

                Picker("Template", selection: $settings.defaultTemplateCode) {
                    ForEach(DealDeskTemplateCode.allCases) { template in
                        Text(template.displayName).tag(template)
                    }
                }
                .disabled(!canEdit || isSaving)
                .onChange(of: settings.defaultTemplateCode) { _, newValue in
                    taxLines = DealDeskTemplateCatalog.defaultTaxLines(for: newValue)
                    feeLines = DealDeskTemplateCatalog.defaultFeeLines(for: newValue)
                }

                if !canEdit {
                    Text("Only owner or admin can change these settings.")
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }

            if !taxLines.isEmpty {
                Section("Default taxes") {
                    ForEach($taxLines) { $line in
                        DealDeskEditableLineRow(
                            currencySymbol: regionSettings.selectedRegion.currencySymbol,
                            line: $line
                        )
                        .disabled(!canEdit || isSaving)
                    }
                }
            }

            if !feeLines.isEmpty {
                Section("Default fees") {
                    ForEach($feeLines) { $line in
                        DealDeskEditableLineRow(
                            currencySymbol: regionSettings.selectedRegion.currencySymbol,
                            line: $line
                        )
                        .disabled(!canEdit || isSaving)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }

            if saveSuccess {
                Section {
                    Text("Deal Desk settings saved.")
                        .foregroundColor(.green)
                }
            }

            if canEdit {
                Section {
                    Button(isSaving ? "Saving..." : "Save settings") {
                        Task {
                            await saveSettings()
                        }
                    }
                    .disabled(isSaving || isLoading)
                }
            }
        }
        .navigationTitle("Deal Desk")
        .task {
            await loadSettings()
        }
    }

    @MainActor
    private func loadSettings() async {
        guard let organizationId = sessionStore.activeOrganizationId ?? CloudSyncEnvironment.currentDealerId else {
            errorMessage = "No active business selected."
            isLoading = false
            return
        }

        let loaded = await sessionStore.loadDealDeskSettings(for: organizationId)
        let resolved = loaded ?? DealDeskTemplateCatalog.defaultSettings(for: .generic, isEnabled: false)
        settings = resolved
        taxLines = resolved.seededTaxLines
        feeLines = resolved.seededFeeLines
        isLoading = false
        errorMessage = nil
    }

    @MainActor
    private func saveSettings() async {
        guard let organizationId = sessionStore.activeOrganizationId ?? CloudSyncEnvironment.currentDealerId else {
            errorMessage = "No active business selected."
            return
        }

        isSaving = true
        defer { isSaving = false }

        var settingsToSave = settings
        settingsToSave.taxOverrides = taxLines
        settingsToSave.feeOverrides = feeLines

        do {
            let saved = try await sessionStore.saveDealDeskSettings(settingsToSave, for: organizationId)
            settings = saved
            taxLines = saved.seededTaxLines
            feeLines = saved.seededFeeLines
            errorMessage = nil
            saveSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saveSuccess = false
            }
        } catch {
            errorMessage = error.localizedDescription
            saveSuccess = false
        }
    }
}

private struct DealDeskEditableLineRow: View {
    let currencySymbol: String
    @Binding var line: DealDeskLine

    private var valueBinding: Binding<String> {
        Binding(
            get: { stringFromDecimal(line.value) },
            set: { newValue in
                line.value = decimalFromInput(newValue)
            }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(line.title)
                    .foregroundColor(ColorTheme.primaryText)
                Text(line.calculationType == .percentOfSalePrice ? "% of sale price" : "Fixed amount")
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }

            Spacer()

            if line.calculationType == .fixedAmount {
                Text(currencySymbol)
                    .foregroundColor(ColorTheme.secondaryText)
            }

            TextField("0", text: valueBinding)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)

            if line.calculationType == .percentOfSalePrice {
                Text("%")
                    .foregroundColor(ColorTheme.secondaryText)
            }
        }
    }
}

@MainActor
private func localizedPaymentMethodLabel(for methodCode: String) -> String {
    switch methodCode {
    case "cash":
        return "payment_method_cash".localizedString
    case "finance":
        return "payment_method_finance".localizedString
    case "bank_transfer":
        return "payment_method_bank_transfer".localizedString
    case "cheque":
        return "payment_method_cheque".localizedString
    default:
        return "payment_method_other".localizedString
    }
}

private func sanitizedDecimalInput(_ value: String) -> String {
    var result = ""
    var hasDecimalSeparator = false

    for character in value {
        if character.isNumber {
            result.append(character)
            continue
        }
        if character == ".", !hasDecimalSeparator {
            hasDecimalSeparator = true
            result.append(character)
        }
    }

    return result
}

private func decimalFromInput(_ value: String) -> Decimal {
    Decimal(string: sanitizedDecimalInput(value)) ?? 0
}

private func optionalDecimalFromInput(_ value: String) -> Decimal? {
    let sanitized = sanitizedDecimalInput(value)
    guard !sanitized.isEmpty else { return nil }
    return Decimal(string: sanitized)
}

private func stringFromDecimal(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).stringValue
}

private func initialDecimalText(_ value: Decimal) -> String {
    value == 0 ? "" : stringFromDecimal(value)
}


#Preview {
    let context = PersistenceController.preview.container.viewContext
    return AddSaleView()
        .environment(\.managedObjectContext, context)
}
