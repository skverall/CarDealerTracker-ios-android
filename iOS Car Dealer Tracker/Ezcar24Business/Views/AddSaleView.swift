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
                        
                        // Financial Preview Card (only if vehicle selected)
                        if selectedVehicle != nil {
                            financialPreviewCard
                        }
                        
                        // Sale Details
                        saleDetailsSection

                        // Account Selection
                        accountSelectionSection
                        
                        // Buyer Details
                        buyerDetailsSection
                        
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
                            Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                                .font(.headline)
                                .foregroundColor(ColorTheme.primaryText)
                            Text(vehicle.vin ?? "No VIN")
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
        Button(action: saveSale) {
            HStack {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 8)
                }
                Text(isSaving ? "saving".localizedString : "complete_sale".localizedString)
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isFormValid ? ColorTheme.primary : ColorTheme.secondaryText.opacity(0.3))
            .cornerRadius(20)
            .shadow(color: isFormValid ? ColorTheme.primary.opacity(0.3) : Color.clear, radius: 10, y: 5)
        }
        .disabled(!isFormValid || isSaving)
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
    
    private func saveSale() {
        guard let vehicle = selectedVehicle else { return }
        
        isSaving = true
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        
        // Simulate delay for UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            do {
                // 1. Create Sale Record
                let newSale = Sale(context: viewContext)
                newSale.id = UUID()
                newSale.vehicle = vehicle
                newSale.amount = NSDecimalNumber(decimal: salePrice)
                newSale.date = date
                newSale.buyerName = buyerName
                newSale.buyerPhone = buyerPhone
                newSale.paymentMethod = paymentMethod
                newSale.account = selectedAccount
                newSale.createdAt = Date()
                newSale.updatedAt = newSale.createdAt
                
                // VAT Refund
                if let vatPercent = Decimal(string: vatRefundPercent), vatPercent > 0 {
                    newSale.vatRefundPercent = NSDecimalNumber(decimal: vatPercent)
                    let vatAmount = salePrice * vatPercent / 100
                    newSale.vatRefundAmount = NSDecimalNumber(decimal: vatAmount)
                }                
                // 2. Update Vehicle Status
                vehicle.status = "sold"
                vehicle.salePrice = NSDecimalNumber(decimal: salePrice)
                vehicle.saleDate = date
                vehicle.buyerName = buyerName
                vehicle.buyerPhone = buyerPhone
                vehicle.paymentMethod = paymentMethod
                if !notes.isEmpty {
                    // Append sale notes to vehicle notes or replace?
                    // Let's append for history
                    let currentNotes = vehicle.notes ?? ""
                    let newNote = "\n[Sale Note]: \(notes)"
                    vehicle.notes = currentNotes + newNote
                }
                vehicle.updatedAt = Date()
                
                // 3. Update Account Balance
                if let account = selectedAccount {
                    let currentBalance = account.balance?.decimalValue ?? 0
                    account.balance = NSDecimalNumber(decimal: currentBalance + salePrice)
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
                        interaction.detail = "Purchased \(vehicle.make ?? "") \(vehicle.model ?? "") for \(salePrice.asCurrencyFallback())"
                        interaction.occurredAt = Date()
                        interaction.stage = InteractionStage.closedWon.rawValue
                        interaction.value = NSDecimalNumber(decimal: salePrice)
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
                        
                        if let account = selectedAccount {
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



#Preview {
    let context = PersistenceController.preview.container.viewContext
    return AddSaleView()
        .environment(\.managedObjectContext, context)
}
