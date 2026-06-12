//
//  AddPartView.swift
//  Ezcar24Business
//
//  Premium redesigned form for adding new parts with optional initial stock
//

import SwiftUI
import CoreData

struct AddPartView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FinancialAccount.accountType, ascending: true)],
        predicate: NSPredicate(format: "deletedAt == nil"),
        animation: .default
    )
    private var accounts: FetchedResults<FinancialAccount>

    // Form State - Part Info
    @State private var name: String = ""
    @State private var code: String = ""
    @State private var category: String = ""
    @State private var notes: String = ""
    
    // Form State - Initial Stock (Optional)
    @State private var addInitialStock: Bool = false
    @State private var initialQuantity: String = ""
    @State private var unitCost: String = ""
    @State private var batchLabel: String = ""
    @State private var selectedAccount: FinancialAccount?
    
    @State private var showError = false
    @State private var isSaving = false
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case name, code, category, notes, quantity, unitCost, batchLabel
    }
    
    // Common categories for quick selection
    private let suggestedCategories = [
        (storedValue: "Engine", labelKey: "parts_category_engine", icon: "engine.combustion.fill"),
        (storedValue: "Body", labelKey: "parts_category_body", icon: "car.side.front.open.fill"),
        (storedValue: "Electrical", labelKey: "parts_category_electrical", icon: "bolt.fill"),
        (storedValue: "Suspension", labelKey: "parts_category_suspension", icon: "figure.cooldown"),
        (storedValue: "Interior", labelKey: "parts_category_interior", icon: "carseat.left.fill"),
        (storedValue: "Other", labelKey: "parts_category_other", icon: "wrench.and.screwdriver.fill")
    ]
    
    var isFormValid: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if addInitialStock {
            return hasName && quantityDecimal > 0 && selectedAccount != nil
        }
        return hasName
    }
    
    private var quantityDecimal: Decimal {
        Decimal(string: initialQuantity) ?? 0
    }
    
    private var unitCostDecimal: Decimal {
        Decimal(string: unitCost) ?? 0
    }
    
    private var totalCost: Decimal {
        quantityDecimal * unitCostDecimal
    }

    private func isSuggestedCategorySelected(_ storedValue: String) -> Bool {
        category.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(storedValue) == .orderedSame
    }

    private var categoryDisplayBinding: Binding<String> {
        Binding(
            get: { localizedPartCategory(category) },
            set: { category = storedPartCategory(from: $0) }
        )
    }

    private func localizedPartCategory(_ storedValue: String) -> String {
        switch storedValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "engine": return "parts_category_engine".localizedString
        case "body": return "parts_category_body".localizedString
        case "electrical": return "parts_category_electrical".localizedString
        case "suspension": return "parts_category_suspension".localizedString
        case "interior": return "parts_category_interior".localizedString
        case "other": return "parts_category_other".localizedString
        default: return storedValue
        }
    }

    private func storedPartCategory(from displayValue: String) -> String {
        let trimmed = displayValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower == "engine" || lower == "parts_category_engine".localizedString.lowercased() { return "Engine" }
        if lower == "body" || lower == "parts_category_body".localizedString.lowercased() { return "Body" }
        if lower == "electrical" || lower == "parts_category_electrical".localizedString.lowercased() { return "Electrical" }
        if lower == "suspension" || lower == "parts_category_suspension".localizedString.lowercased() { return "Suspension" }
        if lower == "interior" || lower == "parts_category_interior".localizedString.lowercased() { return "Interior" }
        if lower == "other" || lower == "parts_category_other".localizedString.lowercased() { return "Other" }
        return displayValue
    }

    var body: some View {
        ZStack {
            ColorTheme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom Header
                headerView
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Part Name Hero Section
                        nameInputSection
                        
                        // Category Quick Selector
                        categoryQuickSelector
                        
                        // Details Card
                        detailsCard
                        
                        // Initial Stock Toggle
                        initialStockToggle
                        
                        // Initial Stock Card (if enabled)
                        if addInitialStock {
                            initialStockCard
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
        }
        .alert("parts_add_part_error".localizedString, isPresented: $showError) {
            Button("ok".localizedString, role: .cancel) {}
        }
        .onAppear {
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
            
            Text("parts_add_part_title".localizedString)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)
            
            Spacer()
            
            // Invisible placeholder for symmetry
            Color.clear
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(ColorTheme.background)
    }
    
    // MARK: - Part Name Input
    private var nameInputSection: some View {
        VStack(spacing: 12) {
            Text("parts_add_part_name".localizedString.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(ColorTheme.secondaryText)
                .tracking(1)
            
            TextField("parts_name_placeholder".localizedString, text: $name)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(ColorTheme.primaryText)
                .focused($focusedField, equals: .name)
                .submitLabel(.next)
                .onSubmit { focusedField = .code }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Category Quick Selector
    private var categoryQuickSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("category".localizedString.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(ColorTheme.secondaryText)
                .tracking(1)
                .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(suggestedCategories, id: \.storedValue) { cat in
                        let isSelected = isSuggestedCategorySelected(cat.storedValue)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                category = cat.storedValue
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(isSelected ? ColorTheme.primary : ColorTheme.secondaryBackground)
                                        .frame(width: 52, height: 52)
                                        .shadow(color: isSelected ? ColorTheme.primary.opacity(0.4) : Color.clear, radius: 8, y: 4)
                                    
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 20))
                                        .foregroundColor(isSelected ? .white : ColorTheme.secondaryText)
                                }
                                
                                Text(cat.labelKey.localizedString)
                                    .font(.caption)
                                    .fontWeight(isSelected ? .semibold : .medium)
                                    .foregroundColor(isSelected ? ColorTheme.primaryText : ColorTheme.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
    }
    
    // MARK: - Details Card
    private var detailsCard: some View {
        VStack(spacing: 0) {
            // Part Code Input
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "barcode")
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(width: 24)
                
                TextField("parts_code_placeholder".localizedString, text: $code)
                    .font(.body)
                    .focused($focusedField, equals: .code)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .category }
            }
            .padding(16)
            
            Divider()
                .padding(.leading, 52)
            
            // Custom Category Input
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "tag.fill")
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(width: 24)
                
                TextField("parts_add_part_category".localizedString, text: categoryDisplayBinding)
                    .font(.body)
                    .focused($focusedField, equals: .category)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .notes }
            }
            .padding(16)
            
            Divider()
                .padding(.leading, 52)
            
            // Notes Input
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "note.text")
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(width: 24)
                    .padding(.top, 4)
                
                TextField("parts_add_part_notes".localizedString, text: $notes, axis: .vertical)
                    .font(.body)
                    .lineLimit(3...6)
                    .focused($focusedField, equals: .notes)
            }
            .padding(16)
        }
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .padding(.horizontal, 20)
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 5)
    }
    
    // MARK: - Initial Stock Toggle
    private var initialStockToggle: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                addInitialStock.toggle()
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(addInitialStock ? ColorTheme.primary.opacity(0.1) : ColorTheme.secondaryBackground)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: addInitialStock ? "cube.box.fill" : "cube.box")
                        .font(.system(size: 18))
                        .foregroundColor(addInitialStock ? ColorTheme.primary : ColorTheme.secondaryText)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("parts_add_initial_stock".localizedString)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(ColorTheme.primaryText)
                    Text("parts_add_initial_stock_hint".localizedString)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
                
                Spacer()
                
                Image(systemName: addInitialStock ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(addInitialStock ? ColorTheme.primary : ColorTheme.tertiaryText)
            }
            .padding(16)
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(addInitialStock ? ColorTheme.primary.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .shadow(color: Color.black.opacity(0.02), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Initial Stock Card
    private var initialStockCard: some View {
        VStack(spacing: 0) {
            // Quantity
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "number")
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(width: 24)
                
                TextField("parts_initial_quantity".localizedString, text: $initialQuantity)
                    .font(.body)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .quantity)
                    .onChange(of: initialQuantity) { _, newValue in
                        initialQuantity = filterDecimalInput(newValue)
                    }
            }
            .padding(16)
            
            Divider()
                .padding(.leading, 52)
            
            // Unit Cost
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "dollarsign.circle")
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(width: 24)
                
                TextField("parts_unit_cost".localizedString, text: $unitCost)
                    .font(.body)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .unitCost)
                    .onChange(of: unitCost) { _, newValue in
                        unitCost = filterDecimalInput(newValue)
                    }
            }
            .padding(16)
            
            Divider()
                .padding(.leading, 52)
            
            // Batch Label
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "shippingbox")
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(width: 24)
                
                TextField("parts_batch_label".localizedString, text: $batchLabel)
                    .font(.body)
                    .focused($focusedField, equals: .batchLabel)
            }
            .padding(16)
            
            Divider()
                .padding(.leading, 52)
            
            // Account Picker
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "creditcard")
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(width: 24)
                
                Picker("account_label".localizedString, selection: $selectedAccount) {
                    Text("select_account".localizedString).tag(nil as FinancialAccount?)
                    ForEach(accounts) { account in
                        Text(account.displayTitle).tag(account as FinancialAccount?)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(16)
            
            // Total Cost Summary
            if quantityDecimal > 0 {
                Divider()
                
                HStack {
                    Text("parts_total_cost".localizedString)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                    Spacer()
                    Text(totalCost.asCurrency())
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText)
                }
                .padding(16)
                .background(ColorTheme.secondaryBackground.opacity(0.5))
            }
        }
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .padding(.horizontal, 20)
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 5)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    // MARK: - Save Button
    private var saveButton: some View {
        Button(action: savePart) {
            HStack {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 8)
                }
                Text(isSaving ? "saving".localizedString : "parts_save_part".localizedString)
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

    // MARK: - Save Logic
    private func savePart() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        isSaving = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let now = Date()
            
            // Create the Part
            let part = Part(context: viewContext)
            part.id = UUID()
            part.name = trimmedName
            part.code = code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : code
            part.category = category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : category
            part.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
            part.createdAt = now
            part.updatedAt = now
            
            // Create initial batch if enabled
            var newBatch: PartBatch?
            if addInitialStock && quantityDecimal > 0 {
                let batch = PartBatch(context: viewContext)
                batch.id = UUID()
                batch.part = part
                batch.batchLabel = batchLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : batchLabel
                batch.quantityReceived = NSDecimalNumber(decimal: quantityDecimal)
                batch.quantityRemaining = NSDecimalNumber(decimal: quantityDecimal)
                batch.unitCost = NSDecimalNumber(decimal: unitCostDecimal)
                batch.purchaseDate = now
                batch.purchaseAccountId = selectedAccount?.id
                batch.createdAt = now
                batch.updatedAt = now
                newBatch = batch
                
                // Update account balance
                if let account = selectedAccount {
                    let currentBalance = account.balance?.decimalValue ?? 0
                    account.balance = NSDecimalNumber(decimal: currentBalance - totalCost)
                    account.updatedAt = now
                }
            }

            do {
                try viewContext.save()
                if let dealerId = CloudSyncEnvironment.currentDealerId {
                    Task {
                        await CloudSyncManager.shared?.upsertPart(part, dealerId: dealerId)
                        if let batch = newBatch {
                            await CloudSyncManager.shared?.upsertPartBatch(batch, dealerId: dealerId)
                        }
                        if let account = selectedAccount, addInitialStock {
                            await CloudSyncManager.shared?.upsertFinancialAccount(account, dealerId: dealerId)
                        }
                    }
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                print("AddPartView savePart error: \(error)")
                isSaving = false
                showError = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
    
    private func filterDecimalInput(_ value: String) -> String {
        value.filter { "0123456789.".contains($0) }
    }
}
