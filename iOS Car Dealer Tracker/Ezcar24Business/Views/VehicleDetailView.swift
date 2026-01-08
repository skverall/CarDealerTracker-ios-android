//
//  VehicleDetailView.swift
//  Ezcar24Business
//
//  Detailed view of a single vehicle with expenses
//

import SwiftUI

import PhotosUI

struct VehicleDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    let vehicle: Vehicle
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var pendingImageData: Data? = nil // Image data waiting for confirmation
    @State private var showImageConfirmation: Bool = false
    @State private var isUploadingImage: Bool = false
    @State private var refreshID = UUID()
    @State private var editStatus: String = ""
    @State private var editPurchasePrice: String = ""
    @State private var editSalePrice: String = ""
    @State private var editSaleDate: Date = Date()
    @State private var isSaving: Bool = false
    @State private var showSavedToast: Bool = false
    @State private var saveError: String? = nil

    // Editable fields
    @State private var editVIN: String = ""
    @State private var editMake: String = ""
    @State private var editModel: String = ""
    @State private var editYear: String = ""
    @State private var editPurchaseDate: Date = Date()
    @State private var editNotes: String = ""
    @State private var editBuyerName: String = ""
    @State private var editBuyerPhone: String = ""

    @State private var editPaymentMethod: String = "Cash"
    @State private var selectedAccount: FinancialAccount? = nil
    
    // New Feature Fields
    @State private var editAskingPrice: String = ""
    @State private var editReportURL: String = ""

    // Sharing
    @State private var showShareSheet: Bool = false
    @State private var shareItems: [Any] = []

    let paymentMethods = ["Cash", "Bank Transfer", "Cheque", "Finance", "Other"]

    @State private var isEditing: Bool = false



    private func filterAmountInput(_ s: String) -> String {
        var result = ""
        var hasDot = false
        var decimals = 0
        for ch in s.replacingOccurrences(of: ",", with: ".") {
            if ch >= "0" && ch <= "9" {
                if hasDot { if decimals < 2 { result.append(ch); decimals += 1 } }
                else { result.append(ch) }
            } else if ch == "." && !hasDot {
                hasDot = true
                result.append(ch)
            }
        }
        return result
    }

    private func sanitizedDecimal(from s: String) -> Decimal? {
        let filtered = filterAmountInput(s)
        return Decimal(string: filtered)
    }




    @FetchRequest var expenses: FetchedResults<Expense>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FinancialAccount.accountType, ascending: true)],
        animation: .default
    )
    private var accounts: FetchedResults<FinancialAccount>

    init(vehicle: Vehicle, startEditing: Bool = false) {
        self.vehicle = vehicle
        _isEditing = State(initialValue: startEditing)
        _expenses = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Expense.date, ascending: false)],
            predicate: NSPredicate(format: "vehicle == %@", vehicle),
            animation: .default
        )
    }

    var totalExpenses: Decimal {
        expenses.reduce(0) { $0 + ($1.amount?.decimalValue ?? 0) }
    }

    var profit: Decimal? {
        guard let sale = vehicle.salePrice?.decimalValue else { return nil }
        let buy = vehicle.purchasePrice?.decimalValue ?? 0
        return sale - (buy + totalExpenses)
    }

    var totalCost: Decimal {
        (vehicle.purchasePrice?.decimalValue ?? 0) + totalExpenses
    }

    private func confirmAndUploadImage() {
        guard let data = pendingImageData, let id = vehicle.id else { return }
        isUploadingImage = true

        Task {
            // 1. Update local timestamp to trigger sync logic
            await viewContext.perform {
                vehicle.updatedAt = Date()
                try? viewContext.save()
            }

            // 2. Save image locally
            ImageStore.shared.save(imageData: data, for: id)
            refreshID = UUID()

            // 3. Sync vehicle update & upload image
            if let dealerId = CloudSyncEnvironment.currentDealerId {
                // First push the vehicle update so other clients know something changed
                await CloudSyncManager.shared?.upsertVehicle(vehicle, dealerId: dealerId)
                // Then upload the image
                await CloudSyncManager.shared?.uploadVehicleImage(vehicleId: id, dealerId: dealerId, imageData: data)
            }

            await MainActor.run {
                isUploadingImage = false
                pendingImageData = nil
                showImageConfirmation = false
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                vehiclePhotoView

                contentView
            }
            .padding(.vertical)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isEditing {
                    Button("cancel".localizedString) {
                        // discard edits and exit mode
                        editStatus = vehicle.status ?? "reserved"
                        if let pp = vehicle.purchasePrice?.decimalValue { editPurchasePrice = String(describing: pp) } else { editPurchasePrice = "" }
                        if let sp = vehicle.salePrice?.decimalValue { editSalePrice = String(describing: sp) } else { editSalePrice = "" }
                        if let sd = vehicle.saleDate { editSaleDate = sd }
                        editVIN = vehicle.vin ?? ""
                        editMake = vehicle.make ?? ""
                        editModel = vehicle.model ?? ""
                        editYear = vehicle.year == 0 ? "" : String(vehicle.year)
                        editPurchaseDate = vehicle.purchaseDate ?? Date()
                        editNotes = vehicle.notes ?? ""
                        editBuyerName = vehicle.buyerName ?? ""
                        editBuyerPhone = vehicle.buyerPhone ?? ""
                        editPaymentMethod = vehicle.paymentMethod ?? "Cash"
                        if let ap = vehicle.askingPrice?.decimalValue { editAskingPrice = String(describing: ap) } else { editAskingPrice = "" }
                        editReportURL = vehicle.reportURL ?? ""
                        isEditing = false
                    }
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "done".localizedString : "edit_action".localizedString) {
                    if isEditing {
                        saveVehicleDetails()
                        isEditing = false
                    } else {
                        // populate fields from current vehicle
                        editVIN = vehicle.vin ?? ""
                        editMake = vehicle.make ?? ""
                        editModel = vehicle.model ?? ""
                        editYear = vehicle.year == 0 ? "" : String(vehicle.year)
                        editPurchaseDate = vehicle.purchaseDate ?? Date()
                        editNotes = vehicle.notes ?? ""
                        editBuyerName = vehicle.buyerName ?? ""
                        editBuyerPhone = vehicle.buyerPhone ?? ""
                        editPaymentMethod = vehicle.paymentMethod ?? "Cash"
                        isEditing = true
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {


                if isEditing, let id = vehicle.id, ImageStore.shared.hasImage(id: id) {
                    Button(role: .destructive) {
                        ImageStore.shared.delete(id: id) {
                            refreshID = UUID()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }

            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                 Button {
                     prepareShareData()
                 } label: {
                     Image(systemName: "square.and.arrow.up")
                 }
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item, let _ = vehicle.id else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    // Store the image data for preview, don't upload yet
                    pendingImageData = data
                    showImageConfirmation = true
                }
            }
        }
        .sheet(isPresented: $showImageConfirmation) {
            ImageConfirmationSheet(
                imageData: pendingImageData,
                isUploading: $isUploadingImage,
                onConfirm: {
                    confirmAndUploadImage()
                },
                onCancel: {
                    pendingImageData = nil
                    showImageConfirmation = false
                }
            )
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .onAppear {
            // Initialize edit fields
            editStatus = vehicle.status ?? "reserved"
            if let pp = vehicle.purchasePrice?.decimalValue { editPurchasePrice = String(describing: pp) } else { editPurchasePrice = "" }
            if let sp = vehicle.salePrice?.decimalValue { editSalePrice = String(describing: sp) }
            if let sd = vehicle.saleDate { editSaleDate = sd }

            // Basic info
            editVIN = vehicle.vin ?? ""
            editMake = vehicle.make ?? ""
            editModel = vehicle.model ?? ""
            editYear = vehicle.year == 0 ? "" : String(vehicle.year)
            editPurchaseDate = vehicle.purchaseDate ?? Date()
            editNotes = vehicle.notes ?? ""
            editBuyerName = vehicle.buyerName ?? ""
            editBuyerPhone = vehicle.buyerPhone ?? ""

            editPaymentMethod = vehicle.paymentMethod ?? "Cash"
            
            if let ap = vehicle.askingPrice?.decimalValue { editAskingPrice = String(describing: ap) } else { editAskingPrice = "" }
            editReportURL = vehicle.reportURL ?? ""
            
            createDefaultAccountsIfNeeded()
            if let existingSale = currentSale(for: vehicle) {
                selectedAccount = existingSale.account
            }
            applyDefaultSaleAccountIfNeeded()
        }
        .onChange(of: accounts.count) { _, _ in
            applyDefaultSaleAccountIfNeeded()
        }
        .background(ColorTheme.secondaryBackground)
        .navigationTitle("vehicle_details".localizedString)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            VStack {
                if isSaving {
                    Label("saving_label".localizedString, systemImage: "arrow.triangle.2.circlepath")
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                        .transition(.opacity)
                } else if showSavedToast {
                    Label("saved_label".localizedString, systemImage: "checkmark.circle.fill")
                        .foregroundColor(ColorTheme.success)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if let err = saveError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundColor(ColorTheme.danger)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var vehiclePhotoView: some View {
        if let id = vehicle.id {
                let hasImage = ImageStore.shared.hasImage(id: id)
                let addPhotoText = "add_photo".localizedString
                let changePhotoText = "change_photo".localizedString
                
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    if isEditing && !hasImage {
                        // Empty State for Editing
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(ColorTheme.secondaryBackground)
                                .frame(height: 200)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
                                        .foregroundColor(ColorTheme.secondary)
                                )
                            
                            VStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(ColorTheme.secondary)
                                Text(addPhotoText) // Fallback: "Add Photo"
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(ColorTheme.secondary)
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        // Default / View Mode / Edit with Image
                        ZStack {
                            VehicleLargeImageView(vehicleID: id)
                                .id(refreshID)
                            
                            if isEditing {
                                // Overlay for existing image
                                ZStack {
                                    Color.black.opacity(0.2)
                                    
                                    VStack {
                                        Image(systemName: "pencil")
                                            .font(.title2)
                                            .foregroundColor(.white)
                                            .padding(12)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Circle())
                                        
                                        Text(changePhotoText)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.ultraThinMaterial)
                                            .cornerRadius(6)
                                    }
                                }
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .disabled(!isEditing)
            }
    }

    @ViewBuilder
    private var editModeView: some View {
        VStack(spacing: 24) {
            // Basic Info Section
            VStack(alignment: .leading, spacing: 16) {
                Text("vehicle_info_section".localizedString)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                VStack(spacing: 0) {
                    editRow(label: "make".localizedString, text: $editMake, placeholder: "Toyota")
                    Divider().padding(.leading)
                    editRow(label: "model".localizedString, text: $editModel, placeholder: "Camry")
                    Divider().padding(.leading)
                    editRow(label: "year".localizedString, text: $editYear, placeholder: "2024", keyboardType: .numberPad)
                    Divider().padding(.leading)
                    editRow(label: "vin".localizedString, text: $editVIN, placeholder: "VIN...", autocapitalization: .characters)
                }
                .background(ColorTheme.cardBackground)
                .cornerRadius(12)
                .padding(.horizontal)
            }

            // Financials Section
            VStack(alignment: .leading, spacing: 16) {
                Text("financial_summary_section".localizedString)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                VStack(spacing: 0) {
                    DatePicker("purchase_date_label".localizedString, selection: $editPurchaseDate, displayedComponents: .date)
                        .padding()
                    
                    Divider().padding(.leading)
                    
                    editRow(label: "purchase_price".localizedString, text: $editPurchasePrice, placeholder: "0.00", keyboardType: .decimalPad)
                    Divider().padding(.leading)
                    editRow(label: "asking_price".localizedString, text: $editAskingPrice, placeholder: "0.00", keyboardType: .decimalPad)
                }
                .background(ColorTheme.cardBackground)
                .cornerRadius(12)
                .padding(.horizontal)
            }

            // Status & Sale Section
            VStack(alignment: .leading, spacing: 16) {
                Text("status_and_sale_section".localizedString)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                VStack(spacing: 0) {
                    HStack {
                        Text("status".localizedString)
                            .foregroundColor(ColorTheme.primaryText)
                        Spacer()
                        Picker("Status", selection: $editStatus) {
                            Text("status_reserved".localizedString).tag("reserved")
                            Text("on_sale".localizedString).tag("on_sale")
                            Text("in_transit".localizedString).tag("in_transit")
                            Text("under_service".localizedString).tag("under_service")
                            Text("sold".localizedString).tag("sold")
                        }
                        .pickerStyle(.menu)
                        .tint(ColorTheme.accent)
                    }
                    .padding()

                    if editStatus == "sold" {
                        Divider().padding(.leading)
                        
                        editRow(label: "sale_price".localizedString, text: $editSalePrice, placeholder: "0.00", keyboardType: .decimalPad)
                        Divider().padding(.leading)
                        
                        DatePicker("sale_date".localizedString, selection: $editSaleDate, displayedComponents: .date)
                            .padding()
                        
                        Divider().padding(.leading)
                        
                        editRow(label: "Buyer Name", text: $editBuyerName, placeholder: "John Doe")
                        Divider().padding(.leading)
                        editRow(label: "Buyer Phone", text: $editBuyerPhone, placeholder: "+1234567890", keyboardType: .phonePad)
                        Divider().padding(.leading)
                        
                        HStack {
                            Text("Payment Method")
                                .foregroundColor(ColorTheme.primaryText)
                            Spacer()
                            Picker("", selection: $editPaymentMethod) {
                                ForEach(paymentMethods, id: \.self) { method in
                                    Text(method).tag(method)
                                }
                            }
                            .pickerStyle(.menu)
                             .tint(ColorTheme.accent)
                        }
                        .padding()
                        
                        Divider().padding(.leading)
                        
                        HStack {
                            Text("deposit_to".localizedString)
                                .foregroundColor(ColorTheme.primaryText)
                            Spacer()
                            Picker("", selection: $selectedAccount) {
                                Text("select_account".localizedString).tag(nil as FinancialAccount?)
                                ForEach(accounts) { account in
                                    Text(account.accountType ?? "Unknown").tag(account as FinancialAccount?)
                                }
                            }
                            .pickerStyle(.menu)
                             .tint(ColorTheme.accent)
                        }
                        .padding()
                    }
                }
                .background(ColorTheme.cardBackground)
                .cornerRadius(12)
                .padding(.horizontal)
            }

            // Notes & Report
            VStack(alignment: .leading, spacing: 16) {
                Text("notes".localizedString)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                VStack(spacing: 0) {
                    editRow(label: "report_link".localizedString, text: $editReportURL, placeholder: "https://...", keyboardType: .URL, autocapitalization: .never)
                    
                    Divider().padding(.leading)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("notes".localizedString)
                            .foregroundColor(ColorTheme.secondaryText)
                            .font(.subheadline)
                        
                        TextEditor(text: $editNotes)
                            .frame(minHeight: 100)
                            .scrollContentBackground(.hidden)
                            .background(ColorTheme.secondaryBackground)
                            .cornerRadius(8)
                    }
                    .padding()
                }
                .background(ColorTheme.cardBackground)
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 40)
    }

    private func editRow(label: String, text: Binding<String>, placeholder: String, keyboardType: UIKeyboardType = .default, autocapitalization: TextInputAutocapitalization = .sentences) -> some View {
        HStack {
            Text(label)
                .foregroundColor(ColorTheme.primaryText)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .multilineTextAlignment(.trailing)
        }
        .padding()
    }

    @ViewBuilder
    private var contentView: some View {
        if isEditing {
            editModeView
        } else {
            displayModeView
        }
    }

    @ViewBuilder
    private var displayModeView: some View {
        displayHeaderView
        displayFinancialsView
        displayExpensesView
    }

    // MARK: - Edit Mode Subviews
    private var editBasicInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("vehicle_info_section".localizedString)
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                HStack {
                    Text("make".localizedString)
                        .foregroundColor(ColorTheme.secondaryText)
                    Spacer()
                    TextField("Make", text: $editMake)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 200)
                }
                
                HStack {
                    Text("model".localizedString)
                        .foregroundColor(ColorTheme.secondaryText)
                    Spacer()
                    TextField("Model", text: $editModel)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 200)
                }
                
                HStack {
                    Text("year".localizedString)
                        .foregroundColor(ColorTheme.secondaryText)
                    Spacer()
                    TextField("Year", text: $editYear)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                Divider()
                
                HStack {
                    Text("vin".localizedString)
                        .foregroundColor(ColorTheme.secondaryText)
                    Spacer()
                    TextField("VIN", text: $editVIN)
                        .textInputAutocapitalization(.characters)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 200)
                }
            }
            .padding()
            .cardStyle()
            .padding(.horizontal)
        }
    }

    private var editFinancialsModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("financial_summary_section".localizedString)
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                DatePicker("purchase_date_label".localizedString, selection: $editPurchaseDate, displayedComponents: .date)
                
                HStack {
                    Text("purchase_price".localizedString)
                        .foregroundColor(ColorTheme.secondaryText)
                    Spacer()
                    TextField("0", text: $editPurchasePrice)
                        .keyboardType(.decimalPad)
                        .onChange(of: editPurchasePrice) { old, new in
                            let filtered = filterAmountInput(new)
                            if filtered != new { editPurchasePrice = filtered }
                        }
                        .multilineTextAlignment(.trailing)
                        .frame(width: 140)
                }
                
                Divider()
                
                HStack {
                    Text("asking_price".localizedString)
                        .foregroundColor(ColorTheme.secondaryText)
                    Spacer()
                    TextField("0", text: $editAskingPrice)
                        .keyboardType(.decimalPad)
                        .onChange(of: editAskingPrice) { old, new in
                            let filtered = filterAmountInput(new)
                            if filtered != new { editAskingPrice = filtered }
                        }
                        .multilineTextAlignment(.trailing)
                        .frame(width: 140)
                }
            }
            .padding()
            .cardStyle()
            .padding(.horizontal)
        }
    }

    private var editStatusSaleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("status_and_sale_section".localizedString)
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                HStack {
                    Text("status".localizedString)
                        .foregroundColor(ColorTheme.secondaryText)
                    Spacer()
                    Picker("Status", selection: $editStatus) {
                        Text("status_owned".localizedString).tag("owned")
                        Text("on_sale".localizedString).tag("on_sale")
                        Text("in_transit".localizedString).tag("in_transit")
                        Text("under_service".localizedString).tag("under_service")
                        Text("sold".localizedString).tag("sold")
                    }
                    .pickerStyle(.menu)
                }
                
                if editStatus == "sold" {
                    Divider()
                    
                    HStack {
                        Text("sale_price".localizedString)
                            .foregroundColor(ColorTheme.secondaryText)
                        Spacer()
                        TextField("0", text: $editSalePrice)
                            .keyboardType(.decimalPad)
                            .onChange(of: editSalePrice) { old, new in
                                let filtered = filterAmountInput(new)
                                if filtered != new { editSalePrice = filtered }
                            }
                            .multilineTextAlignment(.trailing)
                            .frame(width: 140)
                    }
                    
                    DatePicker("sale_date".localizedString, selection: $editSaleDate, displayedComponents: .date)
                    
                    Divider()
                    
                    Group {
                        Text("buyer_details".localizedString)
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                        
                        TextField("Buyer Name", text: $editBuyerName)
                        TextField("Buyer Phone", text: $editBuyerPhone)
                            .keyboardType(.phonePad)
                        
                        Picker("Payment Method", selection: $editPaymentMethod) {
                            ForEach(paymentMethods, id: \.self) { method in
                                Text(method).tag(method)
                            }
                        }
                        
                        HStack {
                            Text("deposit_to".localizedString)
                                .foregroundColor(ColorTheme.secondaryText)
                            Spacer()
                            Picker("Account", selection: $selectedAccount) {
                                Text("select_account".localizedString).tag(nil as FinancialAccount?)
                                ForEach(accounts) { account in
                                    Text(account.accountType ?? "Unknown").tag(account as FinancialAccount?)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
            .padding()
            .cardStyle()
            .padding(.horizontal)
        }
    }

    private var editNotesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("notes".localizedString) 
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                HStack {
                    Text("report_link".localizedString)
                        .foregroundColor(ColorTheme.secondaryText)
                    Spacer()
                    TextField("https://...", text: $editReportURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 200)
                }
                
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("notes".localizedString)
                        .foregroundColor(ColorTheme.secondaryText)
                    TextEditor(text: $editNotes)
                        .frame(minHeight: 90)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2))
                        )
                }
            }
            .padding()
            .cardStyle()
            .padding(.horizontal)
        }
    }

    // MARK: - Display Mode Subviews
    private var displayHeaderView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("vehicle_year_prefix".localizedString + "\(vehicle.year.asYear())")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                }
                
                Spacer()
                
                StatusBadge(status: vehicle.status ?? "")
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("VIN:")
                        .foregroundColor(ColorTheme.secondaryText)
                    Text(vehicle.vin ?? "")
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                
                HStack {
                    Text("purchase_date_label".localizedString)
                        .foregroundColor(ColorTheme.secondaryText)
                    Text(vehicle.purchaseDate ?? Date(), style: .date)
                        .fontWeight(.medium)
                }
                .font(.subheadline)
            }
            
            if let notes = vehicle.notes, !notes.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("notes".localizedString)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                    Text(notes)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding()
        .textFieldStyle(.roundedBorder)
        .cardStyle()
        .padding(.horizontal)
    }

    private var displayFinancialsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("financial_summary_section".localizedString)
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                HStack {
                    Text("purchase_price".localizedString)
                        .foregroundColor(ColorTheme.secondaryText)
                    Spacer()
                    Text((vehicle.purchasePrice?.decimalValue ?? 0).asCurrency())
                        .fontWeight(.medium)
                }
                
                if let asking = vehicle.askingPrice?.decimalValue, asking > 0 {
                    HStack {
                        Text("asking_price".localizedString)
                            .foregroundColor(ColorTheme.secondaryText)
                        Spacer()
                        Text(asking.asCurrency())
                            .fontWeight(.medium)
                            .foregroundColor(ColorTheme.primary)
                    }
                }
                
                if let report = vehicle.reportURL, !report.isEmpty, let url = URL(string: report) {
                    HStack {
                        Text("inspection_report_label".localizedString)
                            .foregroundColor(ColorTheme.secondaryText)
                        Spacer()
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Text("view_report_button".localizedString)
                                Image(systemName: "arrow.up.right.square")
                            }
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.accent)
                        }
                    }
                }
                
                HStack {
                    Text("total_expenses_label".localizedString)
                        .foregroundColor(ColorTheme.secondaryText)
                    Spacer()
                    Text(totalExpenses.asCurrency())
                        .fontWeight(.medium)
                        .foregroundColor(ColorTheme.accent)
                }
                
                Divider()
                
                HStack {
                    Text("total_cost".localizedString)
                        .font(.headline)
                        Spacer()
                    Text(totalCost.asCurrency())
                        .font(.headline)
                        .foregroundColor(ColorTheme.primary)
                }
                
                if let sale = vehicle.salePrice?.decimalValue {
                    HStack {
                        Text("sale_price".localizedString)
                            .foregroundColor(ColorTheme.secondaryText)
                        Spacer()
                        Text(sale.asCurrency())
                            .fontWeight(.medium)
                            .foregroundColor(ColorTheme.success)
                    }
                    if let d = vehicle.saleDate {
                        HStack {
                            Text("sale_date".localizedString)
                                .foregroundColor(ColorTheme.secondaryText)
                            Spacer()
                            Text(d.formatted(date: .abbreviated, time: .omitted))
                                .fontWeight(.medium)
                        }
                    }
                    
                    Divider()
                    
                    if let p = profit {
                        HStack {
                            Text("profit_loss_label".localizedString)
                                .font(.headline)
                            Spacer()
                            Text(p.asCurrency())
                                .font(.headline)
                                .foregroundColor(p >= 0 ? ColorTheme.success : ColorTheme.danger)
                        }
                    }
                }
                
                if let buyer = vehicle.buyerName, !buyer.isEmpty {
                    Divider()
                    HStack {
                        Text("buyer_label".localizedString)
                            .foregroundColor(ColorTheme.secondaryText)
                        Spacer()
                        Text(buyer)
                            .fontWeight(.medium)
                    }
                    if let phone = vehicle.buyerPhone, !phone.isEmpty {
                        HStack {
                            Text("phone".localizedString)
                            .foregroundColor(ColorTheme.secondaryText)
                        Spacer()
                        Text(phone)
                            .fontWeight(.medium)
                        }
                    }
                    if let method = vehicle.paymentMethod, !method.isEmpty {
                        HStack {
                            Text("payment_label".localizedString)
                            .foregroundColor(ColorTheme.secondaryText)
                            Spacer()
                            Text(method)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
            .padding()
            .cardStyle()
            .padding(.horizontal)
        }
    }

    private var displayExpensesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: "expenses_count_format".localizedString, expenses.count))
                .font(.headline)
                .padding(.horizontal)
            
            if expenses.isEmpty {
                Text("no_expenses_recorded".localizedString)
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .cardStyle()
                    .padding(.horizontal)
            } else {
                VStack(spacing: 12) {
                    ForEach(expenses, id: \.id) { expense in
                        VehicleExpenseRow(expense: expense)
                    }
                }
                .padding()
                .cardStyle()
                .padding(.horizontal)
            }
        }
    }

    private func saveVehicleDetails() {
        guard !isSaving else { return }
        withAnimation { saveError = nil; showSavedToast = false; isSaving = true }
        let existingSale = currentSale(for: vehicle)
        let previousSaleAmount = existingSale?.amount?.decimalValue ?? 0
        let previousAccount = existingSale?.account
        var saleToSync: Sale? = nil
        var accountsToSync: [FinancialAccount] = []
        
        func trackAccount(_ account: FinancialAccount?) {
            guard let account else { return }
            if !accountsToSync.contains(where: { $0.objectID == account.objectID }) {
                accountsToSync.append(account)
            }
        }

        // Haptics
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        #endif

        // Basic info from edit fields
        vehicle.vin = editVIN
        vehicle.make = editMake
        vehicle.model = editModel
        if let y = Int32(editYear) { vehicle.year = y }
        vehicle.purchaseDate = editPurchaseDate
        let trimmedNotes = editNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        vehicle.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            
        let ap = sanitizedDecimal(from: editAskingPrice) ?? 0
        vehicle.askingPrice = ap > 0 ? NSDecimalNumber(decimal: ap) : nil
        vehicle.reportURL = editReportURL.isEmpty ? nil : editReportURL

        // Prices & status
        let pp = sanitizedDecimal(from: editPurchasePrice) ?? 0
        vehicle.purchasePrice = NSDecimalNumber(decimal: pp)
        vehicle.status = editStatus
        if editStatus == "sold" {
            let saleAmount = sanitizedDecimal(from: editSalePrice)
            if let sp = saleAmount {
                vehicle.salePrice = NSDecimalNumber(decimal: sp)
            } else {
                vehicle.salePrice = nil
            }
            vehicle.saleDate = editSaleDate
            vehicle.buyerName = editBuyerName
            vehicle.buyerPhone = editBuyerPhone
            vehicle.paymentMethod = editPaymentMethod
            
            if let sp = saleAmount {
                let sale = existingSale ?? Sale(context: viewContext)
                if existingSale == nil {
                    sale.id = UUID()
                    sale.createdAt = Date()
                    sale.vehicle = vehicle
                }
                sale.amount = NSDecimalNumber(decimal: sp)
                sale.date = editSaleDate
                sale.buyerName = editBuyerName
                sale.buyerPhone = editBuyerPhone
                sale.paymentMethod = editPaymentMethod
                sale.updatedAt = Date()
                saleToSync = sale

                let targetAccount = selectedAccount ?? previousAccount ?? defaultSaleAccount()
                sale.account = targetAccount

                if existingSale == nil {
                    if let account = targetAccount {
                        let currentBalance = account.balance?.decimalValue ?? 0
                        account.balance = NSDecimalNumber(decimal: currentBalance + sp)
                        account.updatedAt = Date()
                        trackAccount(account)
                    }
                } else if let account = targetAccount, account.objectID == previousAccount?.objectID {
                    let delta = sp - previousSaleAmount
                    if delta != 0 {
                        let currentBalance = account.balance?.decimalValue ?? 0
                        account.balance = NSDecimalNumber(decimal: currentBalance + delta)
                        account.updatedAt = Date()
                        trackAccount(account)
                    }
                } else {
                    if let oldAccount = previousAccount {
                        let currentBalance = oldAccount.balance?.decimalValue ?? 0
                        oldAccount.balance = NSDecimalNumber(decimal: currentBalance - previousSaleAmount)
                        oldAccount.updatedAt = Date()
                        trackAccount(oldAccount)
                    }
                    if let newAccount = targetAccount {
                        let currentBalance = newAccount.balance?.decimalValue ?? 0
                        newAccount.balance = NSDecimalNumber(decimal: currentBalance + sp)
                        newAccount.updatedAt = Date()
                        trackAccount(newAccount)
                    }
                }
            }
        } else {
            vehicle.salePrice = nil
            vehicle.saleDate = nil
            vehicle.buyerName = nil
            vehicle.buyerPhone = nil
            vehicle.paymentMethod = nil
        }
        vehicle.updatedAt = Date()
        do {
            try viewContext.save()
            #if os(iOS)
            generator.notificationOccurred(.success)
            #endif
            if let dealerId = CloudSyncEnvironment.currentDealerId {
                Task {
                    await CloudSyncManager.shared?.upsertVehicle(vehicle, dealerId: dealerId)
                    if let saleToSync {
                        await CloudSyncManager.shared?.upsertSale(saleToSync, dealerId: dealerId)
                    }
                    for account in accountsToSync {
                        await CloudSyncManager.shared?.upsertFinancialAccount(account, dealerId: dealerId)
                    }
                }
            }
            withAnimation {
                isSaving = false
                showSavedToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation { showSavedToast = false }
            }
        } catch {
            #if os(iOS)
            generator.notificationOccurred(.error)
            #endif
            withAnimation {
                isSaving = false
                saveError = "Save failed"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation { saveError = nil }
            }
            print("Failed to save sale details: \(error)")
        }
    }

    private func prepareShareData() {
        guard let id = vehicle.id else { return }
        
        let reportLink = vehicle.reportURL ?? ""
        let askingPrice = vehicle.askingPrice?.decimalValue ?? 0
        let make = vehicle.make ?? ""
        let model = vehicle.model ?? ""
        let year = vehicle.year
        let vin = vehicle.vin ?? ""
        
        // 1. Load image (async)
        ImageStore.shared.load(id: id) { loadedImage in
            // 2. Generate Image Card
            let cardView = VehicleShareCard(
                image: loadedImage,
                make: make,
                model: model,
                year: year,
                vin: vin,
                price: askingPrice,
                hasReport: !reportLink.isEmpty
            )
            
            let renderer = ImageRenderer(content: cardView)
            renderer.scale = UIScreen.main.scale
            
            var items: [Any] = []
            
            if let cardImage = renderer.uiImage {
                items.append(cardImage)
            }
            
            // 3. Add Message text with link
            var message = "Check out this \(year.asYear()) \(make) \(model)!"
            if askingPrice > 0 {
                message += " Asking: \(askingPrice.asCurrency())"
            }
            if !reportLink.isEmpty {
                message += "\n\nFull Inspection Report: \(reportLink)"
            }
            items.append(message)
            
            if let url = URL(string: reportLink) {
                items.append(url)
            }
            
            self.shareItems = items
            self.showShareSheet = true
        }
    }
    
    private func currentSale(for vehicle: Vehicle) -> Sale? {
        let sales = (vehicle.sales as? Set<Sale>)?.filter { $0.deletedAt == nil } ?? []
        return sales.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.first
    }
    
    private func defaultSaleAccount() -> FinancialAccount? {
        accounts.first(where: { ($0.accountType ?? "").lowercased() == "cash" }) ?? accounts.first
    }
    
    private func applyDefaultSaleAccountIfNeeded() {
        if selectedAccount == nil {
            selectedAccount = defaultSaleAccount()
        }
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
}

struct VehicleShareCard: View {
    let image: UIImage?
    let make: String
    let model: String
    let year: Int32
    let vin: String
    let price: Decimal
    let hasReport: Bool
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white
            
            VStack(spacing: 0) {
                // Image Area
                GeometryReader { geo in
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else {
                        ZStack {
                            Color.gray.opacity(0.1)
                            Image(systemName: "car.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.gray.opacity(0.5))
                        }
                    }
                }
                .frame(height: 250)
                
                // Info Area
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(year.asYear()) \(make) \(model)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.black)
                            
                            Text("VIN: \(vin)")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        if price > 0 {
                            Text(price.asCurrency())
                                .font(.system(size: 24, weight: .heavy))
                                .foregroundColor(Color(red: 0/255, green: 122/255, blue: 255/255)) // Blue
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(hasReport ? .green : .gray)
                        Text(hasReport ? "Inspection Report Available" : "Verified Dealer")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.black)
                        
                        Spacer()
                        
                        Text("Ezcar24")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.gray)
                    }
                }
                .padding(20)
                .background(Color.white)
            }
        }
        .frame(width: 400, height: 400)
        .cornerRadius(20)
        .shadow(radius: 10)
    }
}



struct VehicleLargeImageView: View {
    let vehicleID: UUID
    @State private var image: Image? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.12))
                .frame(height: 180)
            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .clipped()
                    .cornerRadius(12)
            } else {
                Image(systemName: "car.fill")
                    .font(.system(size: 42))
                    .foregroundColor(ColorTheme.secondaryText)
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

struct VehicleExpenseRow: View {
    @ObservedObject var expense: Expense

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(expense.expenseDescription ?? "No description")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text((expense.amount as Decimal? ?? 0).asCurrency())
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(ColorTheme.primary)
            }

            HStack {
                Text(expense.date ?? Date(), style: .date)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)

                if let user = expense.user {
                    Spacer()
                    Label(user.name ?? "", systemImage: "person.fill")
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }

        }
    }
}

// MARK: - Image Confirmation Sheet
struct ImageConfirmationSheet: View {
    let imageData: Data?
    @Binding var isUploading: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Preview Photo")
                    .font(.headline)
                    .padding(.top)

                // Image Preview
                if let data = imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 400)
                        .cornerRadius(12)
                        .padding(.horizontal)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 300)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal)
                }

                Text("Do you want to use this photo?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: onConfirm) {
                        HStack {
                            if isUploading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(isUploading ? "Uploading..." : "Confirm")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(ColorTheme.primary)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isUploading)

                    Button(action: onCancel) {
                        Text("cancel".localizedString)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.15))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                    .disabled(isUploading)
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("cancel".localizedString) {
                        onCancel()
                    }
                    .disabled(isUploading)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        onConfirm()
                    } label: {
                        if isUploading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(ColorTheme.primary)
                        }
                    }
                    .disabled(isUploading)
                }
            }
        }
        .interactiveDismissDisabled(isUploading)
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let vehicle = Vehicle(context: context)
    vehicle.id = UUID()
    vehicle.vin = "1HGBH41JXMN109186"
    vehicle.make = "Toyota"
    vehicle.model = "Land Cruiser"
    vehicle.year = 2022
    vehicle.purchasePrice = NSDecimalNumber(value: 185000.0)
    vehicle.purchaseDate = Date()
    vehicle.status = "reserved"
    vehicle.createdAt = Date()

    return NavigationStack {
        VehicleDetailView(vehicle: vehicle)
            .environment(\.managedObjectContext, context)
    }
}
