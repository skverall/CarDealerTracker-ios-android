//
//  AddExpenseView.swift
//  Ezcar24Business
//
//  Redesigned form for adding new expenses with a premium feel
//

import SwiftUI
import PhotosUI
import CoreData
import UIKit
import UniformTypeIdentifiers

private struct ReceiptAttachment {
    let data: Data
    let fileName: String
    let contentType: String
    let fileExtension: String
}

private final class AddExpenseDraft: ObservableObject {
    @Published var amount = ""
    @Published var date = Date()
    @Published var description = ""
    @Published var category = "vehicle"
    @Published var selectedVehicle: Vehicle?
    @Published var selectedUser: User?
    @Published var selectedAccount: FinancialAccount?
    @Published var receiptAttachment: ReceiptAttachment? = nil
    @Published var receiptPath: String? = nil
    @Published var receiptRemoved = false
    var didPrefill = false
}

private final class AddExpenseDraftStore {
    static let shared = AddExpenseDraftStore()
    private var drafts: [String: AddExpenseDraft] = [:]

    func draft(for key: String) -> AddExpenseDraft {
        if let existing = drafts[key] {
            return existing
        }

        let draft = AddExpenseDraft()
        drafts[key] = draft
        return draft
    }

    func clear(_ key: String) {
        drafts.removeValue(forKey: key)
    }
}

struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @ObservedObject var viewModel: ExpenseViewModel
    
    // Persistence for last used values
    @AppStorage("lastExpenseCategory") private var lastExpenseCategory: String = "vehicle"
    @AppStorage("lastExpenseUserID") private var lastExpenseUserID: String = ""
    @AppStorage("lastExpenseAccountID") private var lastExpenseAccountID: String = ""
    @ObservedObject private var draft: AddExpenseDraft

    var editingExpense: Expense? = nil
    private let draftKey: String

    // UI State
    @State private var templateName: String = ""
    @State private var isSaving: Bool = false
    @State private var showSavedToast: Bool = false
    @State private var vehicleSearchText: String = ""
    @State private var showReceiptImporter: Bool = false
    @State private var showReceiptCameraPicker: Bool = false
    @State private var showReceiptPhotoPicker: Bool = false
    @State private var selectedReceiptPhoto: PhotosPickerItem? = nil
    @State private var receiptShareUrl: URL? = nil
    @State private var showVehicleSelectionError: Bool = false
    
    // Quick Add States
    @State private var showAddUserAlert: Bool = false
    @State private var newUserName: String = ""
    @StateObject private var vehicleViewModel: VehicleViewModel
    
    // Sheet Presentation
    @State private var activeSheet: ActiveSheet?
    
    enum ActiveSheet: Identifiable {
        case vehicle, user, account
        case templates, saveTemplate, addVehicle
        case datePicker, receiptOptions, receiptShare
        var id: Int { hashValue }
    }

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Vehicle.make, ascending: true)],
        predicate: NSPredicate(format: "deletedAt == nil AND (status != 'sold' OR status == nil)"),
        animation: .default)
    private var vehicles: FetchedResults<Vehicle>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \User.name, ascending: true)],
        predicate: NSPredicate(format: "deletedAt == nil"),
        animation: .default)
    private var users: FetchedResults<User>

    let categoryOptions = [
        ("vehicle", "vehicle".localizedString, "car.fill"),
        ("personal", "personal".localizedString, "person.fill"),
        ("employee", "employee".localizedString, "briefcase.fill"),
        ("office", "bills".localizedString, "doc.text.fill"),
        ("marketing", "marketing".localizedString, "megaphone.fill")
    ]
    
    let quickAddOptions = [
        "petrol".localizedString,
        "insurance".localizedString,
        "plate_number".localizedString
    ]

    var isFormValid: Bool {
        let trimmedAmount = draft.amount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let val = Decimal(string: trimmedAmount), val > 0 else { return false }
        return true
    }

    private var shouldShowVehicleSelectionError: Bool {
        showVehicleSelectionError && draft.category == "vehicle" && draft.selectedVehicle == nil
    }
    
    init(viewModel: ExpenseViewModel, editingExpense: Expense? = nil) {
        self.viewModel = viewModel
        self.editingExpense = editingExpense
        let draftKey = editingExpense?.objectID.uriRepresentation().absoluteString ?? "new-expense"
        self.draftKey = draftKey
        _draft = ObservedObject(wrappedValue: AddExpenseDraftStore.shared.draft(for: draftKey))
        _vehicleViewModel = StateObject(wrappedValue: VehicleViewModel(context: PersistenceController.shared.container.viewContext))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorTheme.background.ignoresSafeArea()
                    .onTapToDismissKeyboard()
                
                VStack(spacing: 0) {
                    // Custom Header
                    headerView
                    
                    ScrollView {
                        VStack(spacing: 24) {
                            // Hero Amount Input
                            amountInputSection
                            
                            // Category Selector
                            categorySelector
                            
                            // Main Details Card
                            detailsCard
                            
                            // Context Selectors (Vehicle, User, Account)
                            contextSection

                            receiptSection
                            
                            Spacer(minLength: 100) // Space for bottom button
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
            .sheet(item: $activeSheet) { item in
                switch item {
                case .vehicle: vehicleSelector
                case .user: userSelector
                case .account: accountSelector
                case .templates: templatesView
                case .saveTemplate: saveTemplateView
                case .addVehicle: AddVehicleView(viewModel: vehicleViewModel)
                case .datePicker:
                    NavigationStack {
                        VStack(spacing: 20) {
                            DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .tint(ColorTheme.primary)

                            DatePicker("Time", selection: $draft.date, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                        }
                        .padding()
                        .navigationTitle("Select Date & Time")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("done".localizedString) { activeSheet = nil }
                            }
                        }
                    }
                case .receiptOptions:
                    receiptOptionsView
                case .receiptShare:
                    if let url = receiptShareUrl {
                        ActivityView(activityItems: [url])
                    }
                }
            }
            .sheet(isPresented: $showReceiptCameraPicker) {
                ImagePicker(
                    sourceType: .camera,
                    onImagePicked: { image in
                        attachReceiptImage(image)
                        showReceiptCameraPicker = false
                    },
                    onCancel: {
                        showReceiptCameraPicker = false
                    }
                )
            }
            .photosPicker(
                isPresented: $showReceiptPhotoPicker,
                selection: $selectedReceiptPhoto,
                matching: .images,
                photoLibrary: .shared()
            )
            .fileImporter(
                isPresented: $showReceiptImporter,
                allowedContentTypes: [.image, .pdf],
                allowsMultipleSelection: false
            ) { result in
                showReceiptImporter = false
                handleReceiptImport(result)
            }
            .onChange(of: selectedReceiptPhoto) { _, newValue in
                loadReceiptPhoto(from: newValue)
            }
            .alert("Add New User", isPresented: $showAddUserAlert) {
                TextField("User Name", text: $newUserName)
                    .textInputAutocapitalization(.words)
                Button("cancel".localizedString, role: .cancel) { newUserName = "" }
                Button("Add") { addNewUser() }
            } message: {
                Text("Enter the name of the new user.")
            }
            .onAppear {
                viewModel.refreshFiltersIfNeeded()
                if !draft.didPrefill {
                    prefillIfNeeded()
                    draft.didPrefill = true
                }
            }
            .onChange(of: draft.selectedVehicle) { _, newValue in
                if newValue != nil {
                    showVehicleSelectionError = false
                }
            }
            .onChange(of: draft.category) { _, newValue in
                if newValue != "vehicle" {
                    showVehicleSelectionError = false
                }
            }
        }
    }
    
    // MARK: - UI Components
    
    private var headerView: some View {
        HStack {
            Button {
                closeView()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(width: 36, height: 36)
                    .background(ColorTheme.secondaryBackground)
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Text(editingExpense == nil ? "new_expense".localizedString : "edit_expense".localizedString)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)
            
            Spacer()
            
            Button {
                saveExpense()
            } label: {
                Text("save".localizedString)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(ColorTheme.primaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(ColorTheme.secondaryBackground)
                    .clipShape(Capsule())
            }
            .disabled(!isFormValid || isSaving)
            .opacity(isFormValid ? 1 : 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(ColorTheme.background)
    }
    
    private var amountInputSection: some View {
        VStack(spacing: 8) {
            Text("amount".localizedString.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(ColorTheme.secondaryText)
                .tracking(1)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(regionSettings.selectedRegion.currencySymbol)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(ColorTheme.tertiaryText)
                
                TextField("0", text: $draft.amount)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(ColorTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .frame(minWidth: 80)
                    .fixedSize(horizontal: true, vertical: false)
                    .onChange(of: draft.amount) { old, new in
                        let filtered = filterAmountInput(new)
                        if filtered != new { draft.amount = filtered }
                    }
            }
        }
        .padding(.top, 4)
    }
    
    private var categorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(categoryOptions, id: \.0) { option in
                    let isSelected = draft.category == option.0
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            draft.category = option.0
                            if draft.category != "vehicle" { draft.selectedVehicle = nil }
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(isSelected ? ColorTheme.primary : ColorTheme.secondaryBackground)
                                    .frame(width: 56, height: 56)
                                    .shadow(color: isSelected ? ColorTheme.primary.opacity(0.4) : Color.clear, radius: 8, y: 4)
                                
                                Image(systemName: option.2)
                                    .font(.system(size: 24))
                                    .foregroundColor(isSelected ? .white : ColorTheme.secondaryText)
                            }
                            
                            Text(option.1)
                                .font(.caption)
                                .fontWeight(isSelected ? .semibold : .medium)
                                .foregroundColor(isSelected ? ColorTheme.primaryText : ColorTheme.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }
    
    private var detailsCard: some View {
        VStack(spacing: 0) {
            // Quick Add Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickAddOptions, id: \.self) { option in
                        Button {
                            withAnimation {
                                draft.description = option
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(option)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(draft.description == option ? .white : ColorTheme.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(draft.description == option ? ColorTheme.primary : ColorTheme.primary.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            
            Divider()
                .padding(.horizontal, 16)

            // Description Input
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.alignleft")
                    .foregroundColor(ColorTheme.secondaryText)
                    .padding(.top, 4)
                
                TextField("what_is_this_for".localizedString, text: $draft.description, axis: .vertical)
                    .font(.body)
                    .lineLimit(2...4)
            }
            .padding(16)
            
            Divider()
                .padding(.leading, 44)
            
            // Date Picker
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .foregroundColor(ColorTheme.secondaryText)
                
                Text("date".localizedString)
                    .font(.body)
                    .foregroundColor(ColorTheme.primaryText)
                
                Spacer()

                Button {
                    activeSheet = .datePicker
                } label: {
                    Text(draft.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .padding(.horizontal, 20)
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 5)
    }
    
    private var contextSection: some View {
        VStack(spacing: 12) {
            if draft.category == "vehicle" {
                contextButton(
                    title: "Vehicle",
                    value: draft.selectedVehicle.map(vehicleDisplayName) ?? "Select Vehicle",
                    icon: "car.fill",
                    isActive: draft.selectedVehicle != nil,
                    showsError: shouldShowVehicleSelectionError,
                    errorMessage: "expense_vehicle_required".localizedString
                ) {
                    activeSheet = .vehicle
                }
            }
            
            contextButton(
                title: "Paid By",
                value: draft.selectedUser?.name ?? "Select User",
                icon: "person.fill",
                isActive: draft.selectedUser != nil
            ) {
                activeSheet = .user
            }
            
            contextButton(
                title: "Account",
                value: draft.selectedAccount.map(accountDisplayName) ?? "Select Account",
                icon: "creditcard.fill",
                isActive: draft.selectedAccount != nil
            ) {
                activeSheet = .account
            }
        }
        .padding(.horizontal, 20)
    }

    private var receiptSection: some View {
        VStack(spacing: 12) {
            Button {
                activeSheet = .receiptOptions
            } label: {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(ColorTheme.secondaryBackground)
                            .frame(width: 44, height: 44)
                        Image(systemName: "paperclip")
                            .foregroundColor(ColorTheme.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("receipt".localizedString)
                            .font(.headline)
                            .foregroundColor(ColorTheme.primaryText)
                        Text(receiptLabelText)
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(ColorTheme.tertiaryText)
                }
                .padding(16)
                .background(ColorTheme.cardBackground)
                .cornerRadius(16)
            }
            .buttonStyle(.plain)

            if hasReceipt {
                HStack(spacing: 12) {
                    Button {
                        openReceipt()
                    } label: {
                        Text("view_receipt".localizedString)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(ColorTheme.secondaryBackground)
                            .cornerRadius(12)
                    }

                    Button {
                        removeReceipt()
                    } label: {
                        Text("remove_receipt".localizedString)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(ColorTheme.secondaryBackground)
                            .cornerRadius(12)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var receiptOptionsView: some View {
        SelectionSheet(title: "attach_receipt".localizedString) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    activeSheet = nil
                    DispatchQueue.main.async {
                        showReceiptCameraPicker = true
                    }
                } label: {
                    SelectionRow(title: "take_photo".localizedString, isSelected: false)
                }
            }

            Button {
                activeSheet = nil
                DispatchQueue.main.async {
                    showReceiptPhotoPicker = true
                }
            } label: {
                SelectionRow(title: "choose_from_gallery".localizedString, isSelected: false)
            }

            Button {
                activeSheet = nil
                DispatchQueue.main.async {
                    showReceiptImporter = true
                }
            } label: {
                SelectionRow(title: "choose_file".localizedString, isSelected: false)
            }
        }
    }
    
    private func contextButton(title: String, value: String, icon: String, isActive: Bool, showsError: Bool = false, errorMessage: String? = nil, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: action) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(isActive ? ColorTheme.primary.opacity(0.1) : ColorTheme.secondaryBackground)
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: icon)
                            .font(.system(size: 18))
                            .foregroundColor(isActive ? ColorTheme.primary : (showsError ? .red : ColorTheme.secondaryText))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption)
                            .foregroundColor(showsError ? .red : ColorTheme.secondaryText)
                        Text(value)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(showsError ? .red : ColorTheme.primaryText)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(showsError ? .red : ColorTheme.tertiaryText)
                }
                .padding(12)
                .background(ColorTheme.cardBackground)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            showsError ? Color.red.opacity(0.8) : (isActive ? ColorTheme.primary.opacity(0.3) : Color.clear),
                            lineWidth: showsError ? 1.5 : 1
                        )
                )
                .shadow(color: Color.black.opacity(0.02), radius: 5, x: 0, y: 2)
            }
            .buttonStyle(.plain)

            if let errorMessage, showsError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 4)
            }
        }
    }
    
    private var saveButton: some View {
        Button(action: saveExpense) {
            HStack {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 8)
                }
                Text(isSaving ? "Saving..." : "Save Expense")
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
                Text("expense_saved".localizedString)
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
    
    // MARK: - Selection Sheets
    
    private var vehicleSelector: some View {
        VehicleSelectionSheet(
            isPresented: Binding(
                get: { activeSheet == .vehicle },
                set: { if !$0 { activeSheet = nil } }
            ),
            searchText: $vehicleSearchText,
            selectedVehicle: $draft.selectedVehicle,
            vehicles: Array(vehicles)
        )
    }
    
    private var userSelector: some View {
        SelectionSheet(title: "Select User") {
            Button {
                showAddUserAlert = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(ColorTheme.primary)
                    Text("add_new_user".localizedString)
                        .foregroundColor(ColorTheme.primary)
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            
            Button {
                draft.selectedUser = nil
                activeSheet = nil
            } label: {
                SelectionRow(title: "None", isSelected: draft.selectedUser == nil)
            }
            
            ForEach(users, id: \.objectID) { user in
                Button {
                    draft.selectedUser = user
                    activeSheet = nil
                } label: {
                    SelectionRow(
                        title: user.name ?? "Unknown",
                        isSelected: draft.selectedUser?.objectID == user.objectID
                    )
                }
            }
        }
    }
    
    private var accountSelector: some View {
        SelectionSheet(title: "Select Account") {
            Button {
                draft.selectedAccount = nil
                activeSheet = nil
            } label: {
                SelectionRow(title: "None", isSelected: draft.selectedAccount == nil)
            }
            
            ForEach(viewModel.accounts, id: \.objectID) { account in
                Button {
                    draft.selectedAccount = account
                    activeSheet = nil
                } label: {
                    SelectionRow(
                        title: accountDisplayName(account),
                        isSelected: draft.selectedAccount?.objectID == account.objectID
                    )
                }
            }
        }
    }
    
    // MARK: - Templates Views
    
    private var templatesView: some View {
        NavigationStack {
            List(viewModel.templates, id: \.objectID) { t in
                Button {
                    applyTemplate(t)
                    activeSheet = nil
                } label: {
                    VStack(alignment: .leading) {
                        Text(t.name ?? "Template")
                            .font(.headline)
                        if let cat = t.category {
                            Text(cat.capitalized)
                                .font(.caption)
                                .foregroundColor(ColorTheme.secondaryText)
                        }
                    }
                }
            }
            .navigationTitle("templates".localizedString)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".localizedString) { activeSheet = nil }
                }
            }
        }
    }
    
    private var saveTemplateView: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Template Name", text: $templateName)
                } footer: {
                    Text("This will save the current category, vehicle, user, and account as a template.")
                }
            }
            .navigationTitle("save_template".localizedString)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localizedString) { activeSheet = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save".localizedString) {
                        saveTemplate()
                    }
                    .disabled(templateName.isEmpty)
                }
            }
        }
    }
    
    // MARK: - Logic & Helpers
    
    private func addNewUser() {
        guard !newUserName.isEmpty else { return }
        let user = User(context: viewContext)
        user.id = UUID()
        user.name = newUserName
        user.createdAt = Date()
        user.updatedAt = Date()
        
        do {
            try viewContext.save()
            if let dealerId = CloudSyncEnvironment.currentDealerId {
                Task {
                    await CloudSyncManager.shared?.upsertUser(user, dealerId: dealerId)
                }
            }
            draft.selectedUser = user
            newUserName = ""
            activeSheet = nil // Dismiss selection sheet
        } catch {
            print("Failed to add user: \(error)")
        }
    }
    
    private func filterAmountInput(_ s: String) -> String {
        var result = ""
        var hasDot = false
        var decimals = 0
        for ch in s {
            if ch >= "0" && ch <= "9" {
                if hasDot { if decimals < 2 { result.append(ch); decimals += 1 } else { continue } }
                else { result.append(ch) }
            } else if ch == "." && !hasDot {
                hasDot = true
                result.append(ch)
            }
        }
        return result
    }
    
    private func vehicleDisplayName(_ vehicle: Vehicle) -> String {
        vehicle.displayNameWithInventory
    }
    
    private func accountDisplayName(_ account: FinancialAccount) -> String {
        account.displayTitle
    }

    private var hasReceipt: Bool {
        draft.receiptAttachment != nil || draft.receiptPath != nil
    }

    private var receiptLabelText: String {
        if let attachment = draft.receiptAttachment {
            return attachment.fileName
        }
        if let path = draft.receiptPath {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return "attach_receipt".localizedString
    }
    
    private func prefillIfNeeded() {
        if let exp = editingExpense {
            if let dec = exp.amount as Decimal? { draft.amount = NSDecimalNumber(decimal: dec).stringValue } else { draft.amount = "" }
            if draft.amount.isEmpty { draft.amount = String(describing: exp.amount ?? 0) }
            draft.date = exp.date ?? Date()
            draft.description = exp.expenseDescription ?? ""
            draft.category = exp.category ?? "vehicle"
            draft.selectedVehicle = exp.vehicle
            draft.selectedUser = exp.user
            draft.selectedAccount = exp.account
            draft.receiptPath = exp.receiptPath
        } else {
            draft.category = lastExpenseCategory
            draft.selectedVehicle = nil
            if !lastExpenseUserID.isEmpty {
                draft.selectedUser = users.first { $0.id?.uuidString == lastExpenseUserID }
            }
            if !lastExpenseAccountID.isEmpty {
                draft.selectedAccount = viewModel.accounts.first { $0.objectID.uriRepresentation().absoluteString == lastExpenseAccountID }
            }
        }
    }
    
    private func applyTemplate(_ t: ExpenseTemplate) {
        if let amt = t.defaultAmount?.decimalValue { draft.amount = NSDecimalNumber(decimal: amt).stringValue }
        if let desc = t.defaultDescription { draft.description = desc }
        if let cat = t.category { draft.category = cat }
        draft.selectedVehicle = t.vehicle
        draft.selectedUser = t.user
        draft.selectedAccount = t.account
    }
    
    private func saveTemplate() {
        do {
            try viewModel.saveTemplate(
                name: templateName.isEmpty ? "Template" : templateName,
                category: draft.category,
                vehicle: draft.selectedVehicle,
                user: draft.selectedUser,
                account: draft.selectedAccount,
                defaultAmount: Decimal(string: draft.amount),
                defaultDescription: draft.description.isEmpty ? nil : draft.description
            )
            templateName = ""
            activeSheet = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            print("Failed to save template: \(error)")
        }
    }

    private func handleReceiptImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let data = try Data(contentsOf: url)
                let fileName = url.lastPathComponent
                let fileExtension = url.pathExtension.lowercased()
                let contentType = UTType(filenameExtension: fileExtension)?.preferredMIMEType ?? "application/octet-stream"
                draft.receiptAttachment = ReceiptAttachment(
                    data: data,
                    fileName: fileName,
                    contentType: contentType,
                    fileExtension: fileExtension
                )
                draft.receiptRemoved = false
            } catch {
                print("Failed to load receipt: \(error)")
            }
        case .failure(let error):
            print("Receipt import failed: \(error)")
        }
    }

    private func attachReceiptImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let fileName = "receipt-\(Int(Date().timeIntervalSince1970)).jpg"
        draft.receiptAttachment = ReceiptAttachment(
            data: data,
            fileName: fileName,
            contentType: "image/jpeg",
            fileExtension: "jpg"
        )
        draft.receiptRemoved = false
    }

    private func loadReceiptPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }

        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                return
            }

            await MainActor.run {
                attachReceiptImage(image)
                selectedReceiptPhoto = nil
            }
        }
    }

    private func removeReceipt() {
        if draft.receiptPath != nil {
            draft.receiptRemoved = true
        }
        draft.receiptAttachment = nil
        draft.receiptPath = nil
    }

    private func openReceipt() {
        if let attachment = draft.receiptAttachment {
            if let url = writeReceiptTempFile(data: attachment.data, fileName: attachment.fileName) {
                receiptShareUrl = url
                activeSheet = .receiptShare
            }
            return
        }

        guard let path = draft.receiptPath else { return }
        Task {
            if let data = await CloudSyncManager.shared?.downloadExpenseReceipt(path: path) {
                let fileName = URL(fileURLWithPath: path).lastPathComponent
                let url = writeReceiptTempFile(data: data, fileName: fileName)
                await MainActor.run {
                    receiptShareUrl = url
                    if url != nil { activeSheet = .receiptShare }
                }
            }
        }
    }

    private func writeReceiptTempFile(data: Data, fileName: String) -> URL? {
        let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: tempUrl, options: .atomic)
            return tempUrl
        } catch {
            print("Failed to write receipt temp file: \(error)")
            return nil
        }
    }

    private func syncReceiptChanges(for expense: Expense, previousPath: String?) async {
        guard let dealerId = CloudSyncEnvironment.currentDealerId else { return }

        if draft.receiptRemoved {
            await MainActor.run {
                expense.receiptPath = nil
                expense.updatedAt = Date()
                try? viewContext.save()
            }
            if let previousPath {
                await CloudSyncManager.shared?.deleteExpenseReceipt(path: previousPath)
            }
        }

        if let attachment = draft.receiptAttachment,
           let newPath = await CloudSyncManager.shared?.uploadExpenseReceipt(
                expenseId: expense.id ?? UUID(),
                dealerId: dealerId,
                data: attachment.data,
                contentType: attachment.contentType,
                fileExtension: attachment.fileExtension
           ) {
            await MainActor.run {
                expense.receiptPath = newPath
                expense.updatedAt = Date()
                try? viewContext.save()
            }
            if let previousPath, previousPath != newPath {
                await CloudSyncManager.shared?.deleteExpenseReceipt(path: previousPath)
            }
        }

        await CloudSyncManager.shared?.upsertExpense(expense, dealerId: dealerId)
    }
    
    private func saveExpense() {
        guard let amountDecimal = Decimal(string: draft.amount), amountDecimal > 0 else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()

        if draft.category == "vehicle" && draft.selectedVehicle == nil {
            showVehicleSelectionError = true
            generator.notificationOccurred(.error)
            return
        }

        showVehicleSelectionError = false
        isSaving = true
        
        let selectedDate = draft.date
        let previousReceiptPath = editingExpense?.receiptPath

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            do {
                if let exp = editingExpense {
                    try viewModel.updateExpense(
                        exp,
                        amount: amountDecimal,
                        date: selectedDate,
                        description: draft.description,
                        category: draft.category,
                        vehicle: draft.selectedVehicle,
                        user: draft.selectedUser,
                        account: draft.selectedAccount
                    )
                    
                    Task {
                        await syncReceiptChanges(for: exp, previousPath: previousReceiptPath)
                    }
                } else {
                    let expense = try viewModel.addExpense(
                        amount: amountDecimal,
                        date: selectedDate,
                        description: draft.description,
                        category: draft.category,
                        vehicle: draft.selectedVehicle,
                        user: draft.selectedUser,
                        account: draft.selectedAccount,
                        shouldRefresh: false
                    )
                    viewModel.fetchExpenses()
                    AppReviewManager.shared.handleExpenseAdded(context: viewContext)
                    
                    Task {
                        await syncReceiptChanges(for: expense, previousPath: nil)
                    }
                    
                    lastExpenseCategory = draft.category
                    lastExpenseUserID = draft.selectedUser?.id?.uuidString ?? ""
                    lastExpenseAccountID = draft.selectedAccount?.objectID.uriRepresentation().absoluteString ?? ""
                }
                
                if let dealerId = CloudSyncEnvironment.currentDealerId {
                    if let newAccount = draft.selectedAccount {
                        Task {
                            await CloudSyncManager.shared?.upsertFinancialAccount(newAccount, dealerId: dealerId)
                        }
                    }
                    
                    if let oldAccount = editingExpense?.account, oldAccount != draft.selectedAccount {
                        Task {
                            await CloudSyncManager.shared?.upsertFinancialAccount(oldAccount, dealerId: dealerId)
                        }
                    }
                }
                
                isSaving = false
                showSavedToast = true
                generator.notificationOccurred(.success)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    showSavedToast = false
                    AddExpenseDraftStore.shared.clear(draftKey)
                    dismiss()
                }
            } catch {
                isSaving = false
                generator.notificationOccurred(.error)
                showSavedToast = false
                print("Failed to save expense: \(error)")
            }
        }
    }

    private func closeView() {
        AddExpenseDraftStore.shared.clear(draftKey)
        dismiss()
    }
}

// MARK: - Helper Views

struct SelectionSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                content()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".localizedString) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct SelectionRow: View {
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(ColorTheme.primaryText)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(ColorTheme.primary)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let viewModel = ExpenseViewModel(context: context)
    
    return AddExpenseView(viewModel: viewModel)
        .environment(\.managedObjectContext, context)
}
