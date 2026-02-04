
import SwiftUI
import CoreData

struct AddPartSaleView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var permissionService = PermissionService.shared
    var showHeader: Bool = true

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Part.name, ascending: true)],
        predicate: NSPredicate(format: "deletedAt == nil"),
        animation: .default
    )
    private var parts: FetchedResults<Part>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FinancialAccount.accountType, ascending: true)],
        predicate: NSPredicate(format: "deletedAt == nil"),
        animation: .default
    )
    private var accounts: FetchedResults<FinancialAccount>

    @State private var lineItems: [DraftPartSaleLine] = [DraftPartSaleLine()]
    @State private var selectedClient: Client?
    @State private var showClientSelection = false
    @State private var paymentMethod: String = "payment_method_cash".localizedString
    @State private var notes: String = ""
    @State private var saleDate: Date = Date()
    @State private var selectedAccount: FinancialAccount?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isSaving = false
    
    // Focus State
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case notes
        case quantity(Int)
        case price(Int)
    }

    private var paymentMethods: [String] {
        ["payment_method_cash".localizedString, 
         "payment_method_bank_transfer".localizedString, 
         "payment_method_cheque".localizedString, 
         "payment_method_finance".localizedString, 
         "payment_method_other".localizedString]
    }

    var body: some View {
        ZStack {
            if showHeader {
                ColorTheme.background.ignoresSafeArea()
            }
            
            VStack(spacing: 0) {
                // Custom Header
                if showHeader {
                    headerView
                }
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Sale Details Card
                        saleDetailsCard
                        
                        // Items Section
                        itemsSection
                        
                        // Summary Card
                        summaryCard
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.vertical, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            
            // Bottom Save Button
            VStack {
                Spacer()
                saveButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .alert(errorMessage ?? "parts_sale_save_error".localizedString, isPresented: $showError) {
            Button("ok".localizedString, role: .cancel) {}
        }
        .onAppear {
            if selectedAccount == nil {
                selectedAccount = accounts.first(where: { $0.kind == .cash }) ?? accounts.first
            }
            if accounts.isEmpty {
                createDefaultAccountsIfNeeded()
            }
        }
        .onChange(of: accounts.count) { _, _ in
            if selectedAccount == nil {
                selectedAccount = accounts.first(where: { $0.kind == .cash }) ?? accounts.first
            }
        }
    }
    
    // MARK: - Header
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
            
            Text("parts_sale_title".localizedString)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)
            
            Spacer()
            
            // Invisible placeholder
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(ColorTheme.background)
    }
    
    // MARK: - Sale Details Card
    private var saleDetailsCard: some View {
        VStack(spacing: 0) {
            // Section Title
            HStack {
                Text("parts_sale_details_section".localizedString.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(ColorTheme.secondaryText)
                    .tracking(1)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            
            VStack(spacing: 0) {
                // Date Picker
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                    DatePicker("date".localizedString, selection: $saleDate, displayedComponents: .date)
                        .labelsHidden()
                    Spacer()
                }
                .padding(16)
                
                Divider().padding(.leading, 52)
                
                // Client Selection
                Button {
                     showClientSelection = true
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .foregroundColor(ColorTheme.secondaryText)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedClient?.name ?? "select_client".localizedString)
                                .font(.body)
                                .foregroundColor(selectedClient != nil ? ColorTheme.primaryText : ColorTheme.secondaryText)
                            
                            if let phone = selectedClient?.phone, !phone.isEmpty {
                                Text(phone)
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.secondaryText)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                    .padding(16)
                }
                .sheet(isPresented: $showClientSelection) {
                    ClientSelectionView(selectedClient: $selectedClient)
                }
                .background(ColorTheme.cardBackground)
                
                Divider().padding(.leading, 52)
                
                // Payment Method
                HStack {
                    Image(systemName: "creditcard")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                    
                    Picker("payment_method".localizedString, selection: $paymentMethod) {
                        ForEach(paymentMethods, id: \.self) { method in
                            Text(method.localizedString).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .accentColor(ColorTheme.primaryText)
                    
                    Spacer()
                }
                .padding(16)
                
                Divider().padding(.leading, 52)
                
                // Account Picker
                HStack {
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                    
                    Picker("deposit_to_section".localizedString, selection: $selectedAccount) {
                        Text("select_account".localizedString).tag(nil as FinancialAccount?)
                        ForEach(accounts) { account in
                            Text(account.displayTitle).tag(account as FinancialAccount?)
                        }
                    }
                    .pickerStyle(.menu)
                    .accentColor(ColorTheme.primaryText)
                    
                    Spacer()
                }
                .padding(16)
                
                Divider().padding(.leading, 52)
                
                // Notes
                HStack(alignment: .top) {
                    Image(systemName: "note.text")
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(width: 24)
                        .padding(.top, 4)
                    TextField("parts_sale_notes".localizedString, text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .notes)
                }
                .padding(16)
            }
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .padding(.horizontal, 20)
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 5)
        }
    }

    // MARK: - Items Section
    private var itemsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("parts_sale_items_section".localizedString.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(ColorTheme.secondaryText)
                    .tracking(1)
                Spacer()
                
                Button(action: {
                    withAnimation {
                        lineItems.append(DraftPartSaleLine())
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }) {
                    Label("parts_sale_add_item".localizedString, systemImage: "plus.circle.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(ColorTheme.primary)
                }
            }
            .padding(.horizontal, 20)
            
            ForEach(lineItems.indices, id: \.self) { index in
                itemCard(index: index)
            }
        }
    }
    
    private func itemCard(index: Int) -> some View {
        let binding = Binding<DraftPartSaleLine>(
            get: { lineItems[index] },
            set: { lineItems[index] = $0 }
        )
        let part = partForId(lineItems[index].partId)
        
        return VStack(spacing: 0) {
            // Header: Part Selection & Remove
            HStack {
                Menu {
                    ForEach(parts) { p in
                        Button(action: {
                            lineItems[index].partId = p.id
                        }) {
                            Text(p.displayName)
                        }
                    }
                } label: {
                    HStack {
                        if let part = part {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(part.displayName)
                                    .font(.headline)
                                    .foregroundColor(ColorTheme.primaryText)
                                HStack(spacing: 4) {
                                    Text(String(format: "parts_sale_available_format".localizedString, formatQuantity(part.quantityOnHand)))
                                        .font(.caption)
                                        .foregroundColor(part.quantityOnHand > 0 ? ColorTheme.success : ColorTheme.danger)
                                    if permissionService.canViewPartCost() {
                                        let avgCost = averageUnitCost(for: part)
                                        if avgCost > 0 {
                                            Text("•")
                                                .font(.caption)
                                                .foregroundColor(ColorTheme.secondaryText)
                                            Text("\("parts_sale_total_cost".localizedString): \(avgCost.asCurrency())")
                                                .font(.caption)
                                                .foregroundColor(ColorTheme.secondaryText)
                                        }
                                    }
                                }
                            }
                        } else {
                            Text("parts_select_part".localizedString)
                                .font(.body)
                                .foregroundColor(ColorTheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                }
                
                if lineItems.count > 1 {
                    Button {
                        withAnimation {
                            _ = lineItems.remove(at: index)
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(ColorTheme.danger.opacity(0.8))
                    }
                    .padding(.leading, 8)
                }
            }
            .padding(16)
            .background(ColorTheme.secondaryBackground.opacity(0.3))
            
            Divider()
            
            // Inputs: Qty & Price
            HStack(spacing: 12) {
                // Quantity
                VStack(alignment: .leading, spacing: 4) {
                    Text("parts_sale_quantity".localizedString)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                    
                    TextField("0", text: binding.quantity)
                        .keyboardType(.decimalPad)
                        .font(.system(.body, design: .monospaced))
                        .padding(10)
                        .background(ColorTheme.background)
                        .cornerRadius(8)
                        .focused($focusedField, equals: .quantity(index))
                        .onChange(of: lineItems[index].quantity) { _, newValue in
                            lineItems[index].quantity = filterDecimalInput(newValue)
                        }
                }
                
                // Unit Price
                VStack(alignment: .leading, spacing: 4) {
                    Text("parts_sale_unit_price".localizedString)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                    
                    TextField("0.00", text: binding.unitPrice)
                        .keyboardType(.decimalPad)
                        .font(.system(.body, design: .monospaced))
                        .padding(10)
                        .background(ColorTheme.background)
                        .cornerRadius(8)
                        .focused($focusedField, equals: .price(index))
                        .onChange(of: lineItems[index].unitPrice) { _, newValue in
                            lineItems[index].unitPrice = filterDecimalInput(newValue)
                        }
                }
                
                // Subtotal
                VStack(alignment: .trailing, spacing: 4) {
                    Text("total".localizedString)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                    
                    Text((lineItems[index].quantityDecimal * lineItems[index].unitPriceDecimal).asCurrency())
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(ColorTheme.primaryText)
                        .frame(height: 38) // Align with textfields roughly
                }
            }
            .padding(16)
            
            // Profit per item (if permission granted)
            if permissionService.canViewPartCost(), let part = part {
                let avgCost = averageUnitCost(for: part)
                let qty = lineItems[index].quantityDecimal
                let unitPrice = lineItems[index].unitPriceDecimal
                let profitPerUnit = unitPrice - avgCost
                let totalProfit = profitPerUnit * qty
                
                if qty > 0 && unitPrice > 0 {
                    Divider()
                    
                    HStack {
                        Text("parts_sale_total_cost".localizedString)
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                        Text(avgCost.asCurrency())
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(ColorTheme.primaryText)
                        
                        Spacer()
                        
                        Text("parts_sale_total_profit".localizedString)
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                        Text(totalProfit >= 0 ? "+\(totalProfit.asCurrency())" : totalProfit.asCurrency())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(totalProfit >= 0 ? ColorTheme.success : ColorTheme.danger)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(totalProfit >= 0 ? ColorTheme.success.opacity(0.08) : ColorTheme.danger.opacity(0.08))
                }
            }
        }
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .padding(.horizontal, 20)
        .shadow(color: Color.black.opacity(0.03), radius: 8, y: 4)
    }
    
    // MARK: - Summary Card
    private var summaryCard: some View {
        VStack(spacing: 12) {
            // Revenue
            HStack {
                Text("parts_sale_total_revenue".localizedString)
                    .foregroundColor(ColorTheme.secondaryText)
                Spacer()
                Text(totalRevenue.asCurrency())
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(ColorTheme.primaryText)
            }
            
            // Profit (if allowed)
            if permissionService.canViewPartCost() {
                Divider()
                HStack {
                    Text("parts_sale_total_cost".localizedString)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                    Spacer()
                    Text(estimatedCost.asCurrency())
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.primaryText)
                }
                
                HStack {
                    Text("parts_sale_total_profit".localizedString)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                    Spacer()
                    let profit = totalRevenue - estimatedCost
                    Text(profit.asCurrency())
                        .font(.headline)
                        .foregroundColor(profit >= 0 ? ColorTheme.success : ColorTheme.danger)
                }
            }
            
            // Stock Warning
            if hasStockShortage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(ColorTheme.danger)
                    Text("parts_sale_stock_warning".localizedString)
                        .font(.caption)
                        .foregroundColor(ColorTheme.danger)
                        .multilineTextAlignment(.leading)
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    // MARK: - Save Button
    private var saveButton: some View {
        Button(action: saveSale) {
            HStack {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 8)
                }
                Text(isSaving ? "saving".localizedString : "save".localizedString)
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

    private var totalRevenue: Decimal {
        lineItems.reduce(Decimal(0)) { total, line in
            total + (line.quantityDecimal * line.unitPriceDecimal)
        }
    }

    private var estimatedCost: Decimal {
        simulateCost().totalCost
    }

    private var hasStockShortage: Bool {
        simulateCost().hasShortage
    }
    
    // Existing logic methods remain unchanged
    private var isFormValid: Bool {
        selectedAccount != nil && lineItems.allSatisfy { $0.isValid } && !hasStockShortage
    }

    private func saveSale() {
        guard let account = selectedAccount else { return }
        
        isSaving = true
        let now = Date()

        var remainingByBatch: [UUID: Decimal] = [:]
        for part in parts {
            for batch in part.activeBatches {
                if let id = batch.id {
                    remainingByBatch[id] = batch.quantityRemaining?.decimalValue ?? 0
                }
            }
        }

        let sale = PartSale(context: viewContext)
        sale.id = UUID()
        sale.date = saleDate
        sale.buyerName = selectedClient?.name
        sale.buyerPhone = selectedClient?.phone
        if let client = selectedClient {
            sale.setValue(client, forKey: "client")
        }
        sale.paymentMethod = paymentMethod
        sale.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        sale.account = account
        sale.createdAt = now
        sale.updatedAt = now

        var updatedBatches: Set<PartBatch> = []
        var updatedPartsById: [UUID: Part] = [:]
        var createdLineItems: [PartSaleLineItem] = []
        var total = Decimal(0)

        for line in lineItems {
            guard let part = partForId(line.partId) else { continue }
            var remaining = line.quantityDecimal
            let batches = part.activeBatches
                .filter { ($0.quantityRemaining?.decimalValue ?? 0) > 0 }
                .sorted { ($0.purchaseDate ?? .distantPast) < ($1.purchaseDate ?? .distantPast) }

            for batch in batches {
                guard let batchId = batch.id else { continue }
                let available = remainingByBatch[batchId] ?? (batch.quantityRemaining?.decimalValue ?? 0)
                if available <= 0 { continue }
                let allocate = min(available, remaining)
                if allocate <= 0 { continue }

                let lineItem = PartSaleLineItem(context: viewContext)
                lineItem.id = UUID()
                lineItem.sale = sale
                lineItem.part = part
                lineItem.batch = batch
                lineItem.quantity = NSDecimalNumber(decimal: allocate)
                lineItem.unitPrice = NSDecimalNumber(decimal: line.unitPriceDecimal)
                lineItem.unitCost = batch.unitCost
                lineItem.createdAt = now
                lineItem.updatedAt = now
                createdLineItems.append(lineItem)

                remaining -= allocate
                remainingByBatch[batchId] = available - allocate
                total += allocate * line.unitPriceDecimal

                let updatedRemaining = (batch.quantityRemaining?.decimalValue ?? 0) - allocate
                batch.quantityRemaining = NSDecimalNumber(decimal: updatedRemaining)
                batch.updatedAt = now
                updatedBatches.insert(batch)
            }

            if remaining > 0 {
                errorMessage = "parts_sale_stock_error".localizedString
                showError = true
                isSaving = false
                viewContext.rollback()
                return
            }
            part.updatedAt = now
            if let partId = part.id {
                updatedPartsById[partId] = part
            }
        }

        sale.amount = NSDecimalNumber(decimal: total)

        let currentBalance = account.balance?.decimalValue ?? 0
        account.balance = NSDecimalNumber(decimal: currentBalance + total)
        account.updatedAt = now

        do {
            try viewContext.save()
            if let dealerId = CloudSyncEnvironment.currentDealerId {
                Task {
                    await CloudSyncManager.shared?.upsertPartSale(sale, dealerId: dealerId)
                    for item in createdLineItems {
                        await CloudSyncManager.shared?.upsertPartSaleLineItem(item, dealerId: dealerId)
                    }
                    for part in updatedPartsById.values {
                        await CloudSyncManager.shared?.upsertPart(part, dealerId: dealerId)
                    }
                    if let client = selectedClient {
                        await CloudSyncManager.shared?.upsertClient(client, dealerId: dealerId)
                    }
                    for batch in updatedBatches {
                        await CloudSyncManager.shared?.upsertPartBatch(batch, dealerId: dealerId)
                    }
                    await CloudSyncManager.shared?.upsertFinancialAccount(account, dealerId: dealerId)
                }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            print("AddPartSaleView saveSale error: \(error)")
            errorMessage = "parts_sale_save_error".localizedString
            showError = true
            isSaving = false
        }
    }

    private func simulateCost() -> (totalCost: Decimal, hasShortage: Bool) {
        var totalCost = Decimal(0)
        var hasShortage = false
        var remainingByBatch: [UUID: Decimal] = [:]

        for part in parts {
            for batch in part.activeBatches {
                if let id = batch.id {
                    remainingByBatch[id] = batch.quantityRemaining?.decimalValue ?? 0
                }
            }
        }

        for line in lineItems {
            guard let part = partForId(line.partId) else { continue }
            var remaining = line.quantityDecimal
            let batches = part.activeBatches
                .filter { ($0.quantityRemaining?.decimalValue ?? 0) > 0 }
                .sorted { ($0.purchaseDate ?? .distantPast) < ($1.purchaseDate ?? .distantPast) }

            for batch in batches {
                guard let batchId = batch.id else { continue }
                let available = remainingByBatch[batchId] ?? 0
                if available <= 0 { continue }
                let allocate = min(available, remaining)
                if allocate <= 0 { continue }
                remainingByBatch[batchId] = available - allocate
                totalCost += allocate * (batch.unitCost?.decimalValue ?? 0)
                remaining -= allocate
                if remaining <= 0 { break }
            }
            if remaining > 0 {
                hasShortage = true
            }
        }

        return (totalCost, hasShortage)
    }

    private func partForId(_ id: UUID?) -> Part? {
        guard let id else { return nil }
        return parts.first(where: { $0.id == id })
    }

    private func filterDecimalInput(_ value: String) -> String {
        value.filter { "0123456789.".contains($0) }
    }

    private func formatQuantity(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
    
    /// Calculates the weighted average unit cost from a part's active batches
    private func averageUnitCost(for part: Part) -> Decimal {
        let batches = part.activeBatches.filter { ($0.quantityRemaining?.decimalValue ?? 0) > 0 }
        guard !batches.isEmpty else { return 0 }
        
        var totalCost: Decimal = 0
        var totalQty: Decimal = 0
        for batch in batches {
            let qty = batch.quantityRemaining?.decimalValue ?? 0
            let cost = batch.unitCost?.decimalValue ?? 0
            totalCost += qty * cost
            totalQty += qty
        }
        return totalQty > 0 ? totalCost / totalQty : 0
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
            print("AddPartSaleView createDefaultAccounts error: \(error)")
        }
    }
}

private struct DraftPartSaleLine: Identifiable {
    let id = UUID()
    var partId: UUID?
    var quantity: String = ""
    var unitPrice: String = ""

    var quantityDecimal: Decimal {
        Decimal(string: quantity) ?? 0
    }

    var unitPriceDecimal: Decimal {
        Decimal(string: unitPrice) ?? 0
    }

    var isValid: Bool {
        partId != nil && quantityDecimal > 0 && unitPriceDecimal > 0
    }
}



struct ClientSelectionView: View {
    @Binding var selectedClient: Client?
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var showAddClient = false
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Client.updatedAt, ascending: false)],
        animation: .default)
    private var clients: FetchedResults<Client>

    var filteredClients: [Client] {
        if searchText.isEmpty {
            return Array(clients)
        } else {
            return clients.filter { client in
                (client.name ?? "").localizedCaseInsensitiveContains(searchText) ||
                (client.phone ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredClients) { client in
                    Button {
                        selectedClient = client
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(client.name ?? "Unknown")
                                    .font(.headline)
                                if let phone = client.phone, !phone.isEmpty {
                                    Text(phone)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if selectedClient == client {
                                Image(systemName: "checkmark")
                                    .foregroundColor(ColorTheme.primary)
                            }
                        }
                    }
                    .foregroundColor(ColorTheme.primaryText)
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "search_client".localizedString)
            .navigationTitle("select_client".localizedString)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("cancel".localizedString) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddClient = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddClient) {
                QuickAddClientView(selectedClient: $selectedClient)
            }
        }
    }
}

struct QuickAddClientView: View {
    @Binding var selectedClient: Client?
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var phone = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("buyer_name".localizedString, text: $name)
                    TextField("phone_number".localizedString, text: $phone)
                        .keyboardType(.phonePad)
                } header: {
                    Text("client_details".localizedString)
                }
            }
            .navigationTitle("new_client".localizedString)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localizedString) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save".localizedString) {
                        saveClient()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveClient() {
        let client = Client(context: viewContext)
        client.id = UUID()
        client.name = name
        client.phone = phone
        client.createdAt = Date()
        client.updatedAt = Date()
        client.status = "new"
        
        do {
            try viewContext.save()
            
            // Trigger sync
            if let dealerId = CloudSyncEnvironment.currentDealerId {
                Task {
                    await CloudSyncManager.shared?.upsertClient(client, dealerId: dealerId)
                }
            }
            
            selectedClient = client
            dismiss()
        } catch {
            print("Error saving client: \(error)")
        }
    }
}
