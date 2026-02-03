//
//  VehicleDetailView.swift
//  Ezcar24Business
//
//  Detailed view of a single vehicle with expenses
//

import SwiftUI
import PhotosUI
import CoreData
import UIKit

struct VehicleDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject private var permissionService = PermissionService.shared
    let vehicle: Vehicle
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var pendingPhotos: [PendingVehiclePhoto] = []
    @State private var showPhotoUploadSheet: Bool = false
    @State private var isUploadingPhotos: Bool = false
    @State private var replaceCoverOnUpload: Bool = false
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
    @State private var editMileage: String = ""
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
    @State private var vehiclePhotos: [RemoteVehiclePhoto] = []
    @State private var photoPendingDelete: RemoteVehiclePhoto? = nil
    @State private var showPhotoDeleteDialog: Bool = false

    let paymentMethods = ["Cash", "Bank Transfer", "Cheque", "Finance", "Other"]

    @State private var isEditing: Bool = false


    private var canDeleteRecords: Bool {
        if case .signedIn = sessionStore.status {
            return permissionService.can(.deleteRecords)
        }
        return true
    }



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
        return sale - (buy + totalExpenses + holdingCost)
    }

    var totalCost: Decimal {
        (vehicle.purchasePrice?.decimalValue ?? 0) + totalExpenses + holdingCost
    }
    
    var holdingCost: Decimal {
        guard let vehicleId = vehicle.id else { return 0 }
        let stats = InventoryStatsManager.shared.getStats(for: vehicleId)
        return stats?.holdingCostAccumulated?.decimalValue ?? 0
    }
    
    var dailyHoldingCost: Decimal {
        guard daysInInventory > 0 else { return 0 }
        return holdingCost / Decimal(daysInInventory)
    }
    
    var daysInInventory: Int {
        HoldingCostCalculator.calculateDaysInInventory(vehicle: vehicle)
    }
    
    var roiPercent: Decimal? {
        guard let salePrice = vehicle.salePrice?.decimalValue else { return nil }
        return VehicleFinancialsCalculator.calculateROI(
            salePrice: salePrice,
            totalCost: totalCost
        )
    }
    
    var profitEstimate: Decimal? {
        guard let askingPrice = vehicle.askingPrice?.decimalValue else { return nil }
        return VehicleFinancialsCalculator.calculateProfitEstimate(
            askingPrice: askingPrice,
            totalCost: totalCost
        )
    }

    private func preparePendingPhotos(items: [PhotosPickerItem]) async {
        var pending: [PendingVehiclePhoto] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                pending.append(PendingVehiclePhoto(id: UUID(), data: data, image: Image(uiImage: uiImage)))
            }
        }
        await MainActor.run {
            pendingPhotos = pending
            selectedPhotos = []
            if let id = vehicle.id {
                let dealerId = CloudSyncEnvironment.currentDealerId
                replaceCoverOnUpload = !ImageStore.shared.hasImage(id: id, dealerId: dealerId)
            } else {
                replaceCoverOnUpload = false
            }
            showPhotoUploadSheet = !pending.isEmpty
        }
    }

    private func uploadPendingPhotos() {
        guard let id = vehicle.id, !pendingPhotos.isEmpty else { return }
        isUploadingPhotos = true

        Task {
            await viewContext.perform {
                vehicle.updatedAt = Date()
                try? viewContext.save()
            }

            guard let dealerId = CloudSyncEnvironment.currentDealerId else {
                await MainActor.run {
                    isUploadingPhotos = false
                    pendingPhotos = []
                    showPhotoUploadSheet = false
                }
                return
            }

            let hasCover = ImageStore.shared.hasImage(id: id, dealerId: dealerId)
            let shouldSetCover = replaceCoverOnUpload || !hasCover
            var sortOrder = vehiclePhotos.count
            var isFirst = true

            await CloudSyncManager.shared?.upsertVehicle(vehicle, dealerId: dealerId)

            for photo in pendingPhotos {
                await CloudSyncManager.shared?.uploadVehiclePhoto(
                    vehicleId: id,
                    dealerId: dealerId,
                    imageData: photo.data,
                    makePrimary: shouldSetCover && isFirst,
                    sortOrder: sortOrder
                )
                sortOrder += 1
                isFirst = false
            }

            refreshID = UUID()
            await refreshVehiclePhotos()

            await MainActor.run {
                isUploadingPhotos = false
                pendingPhotos = []
                showPhotoUploadSheet = false
            }
        }
    }

    private func refreshVehiclePhotos() async {
        guard let id = vehicle.id, let dealerId = CloudSyncEnvironment.currentDealerId else { return }
        do {
            let photos = try await CloudSyncManager.shared?.fetchVehiclePhotos(dealerId: dealerId, vehicleId: id) ?? []
            for photo in photos {
                await CloudSyncManager.shared?.downloadVehiclePhoto(photo, dealerId: dealerId)
            }
            await MainActor.run { self.vehiclePhotos = photos }
        } catch {
            print("Failed to refresh vehicle photos: \(error)")
        }
    }

    private func setCoverPhoto(_ photo: RemoteVehiclePhoto) async {
        guard let dealerId = CloudSyncEnvironment.currentDealerId else { return }
        if let image = await loadPhotoImage(vehicleId: photo.vehicleId, photoId: photo.id, dealerId: dealerId),
           let data = image.jpegData(compressionQuality: 0.9) {
            await CloudSyncManager.shared?.uploadVehicleImage(vehicleId: photo.vehicleId, dealerId: dealerId, imageData: data)
            ImageStore.shared.save(imageData: data, for: photo.vehicleId, dealerId: dealerId)
            await MainActor.run {
                refreshID = UUID()
            }
        }
    }

    private func deleteVehiclePhoto(_ photo: RemoteVehiclePhoto) async {
        guard let dealerId = CloudSyncEnvironment.currentDealerId else { return }
        await CloudSyncManager.shared?.deleteVehiclePhoto(photo: photo, dealerId: dealerId)
        await refreshVehiclePhotos()
    }

    private func loadPhotoImage(vehicleId: UUID, photoId: UUID, dealerId: UUID?) async -> UIImage? {
        await withCheckedContinuation { continuation in
            ImageStore.shared.loadPhoto(vehicleId: vehicleId, photoId: photoId, dealerId: dealerId) { image in
                continuation.resume(returning: image)
            }
        }
    }

    private func loadPrimaryImage(vehicleId: UUID, dealerId: UUID?) async -> UIImage? {
        await withCheckedContinuation { continuation in
            ImageStore.shared.load(id: vehicleId, dealerId: dealerId) { image in
                continuation.resume(returning: image)
            }
        }
    }

    private func currentUserPhone() -> String? {
        guard case .signedIn(let user) = sessionStore.status else { return nil }
        let request: NSFetchRequest<User> = User.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", user.id as CVarArg)
        request.fetchLimit = 1
        return (try? viewContext.fetch(request).first)?.phone
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
                        editMileage = vehicle.mileage == 0 ? "" : String(vehicle.mileage)
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
                        editMileage = vehicle.mileage == 0 ? "" : String(vehicle.mileage)
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


                let dealerId = CloudSyncEnvironment.currentDealerId
                if canDeleteRecords, isEditing, let id = vehicle.id, ImageStore.shared.hasImage(id: id, dealerId: dealerId) {
                    Button(role: .destructive) {
                        ImageStore.shared.delete(id: id, dealerId: dealerId) {
                            refreshID = UUID()
                        }
                        if let dealerId {
                            Task { await CloudSyncManager.shared?.deleteVehicleImage(vehicleId: id, dealerId: dealerId) }
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
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await preparePendingPhotos(items: items)
            }
        }
        .sheet(isPresented: $showPhotoUploadSheet) {
            PhotoUploadSheet(
                photos: pendingPhotos,
                replaceCover: $replaceCoverOnUpload,
                isUploading: $isUploadingPhotos,
                onConfirm: {
                    uploadPendingPhotos()
                },
                onCancel: {
                    pendingPhotos = []
                    selectedPhotos = []
                    showPhotoUploadSheet = false
                }
            )
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .confirmationDialog("delete_photo_confirm".localizedString, isPresented: $showPhotoDeleteDialog) {
            Button("delete_photo".localizedString, role: .destructive) {
                if let photo = photoPendingDelete {
                    Task { await deleteVehiclePhoto(photo) }
                }
                photoPendingDelete = nil
            }
            Button("cancel".localizedString, role: .cancel) {
                photoPendingDelete = nil
            }
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
            editMileage = vehicle.mileage == 0 ? "" : String(vehicle.mileage)
            editPurchaseDate = vehicle.purchaseDate ?? Date()
            editNotes = vehicle.notes ?? ""
            editBuyerName = vehicle.buyerName ?? ""
            editBuyerPhone = vehicle.buyerPhone ?? ""

            editPaymentMethod = vehicle.paymentMethod ?? "Cash"
            
            Task { await refreshVehiclePhotos() }

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
            let dealerId = CloudSyncEnvironment.currentDealerId
            let hasImage = ImageStore.shared.hasImage(id: id, dealerId: dealerId)
            let addPhotosText = "add_photos".localizedString
            VStack(spacing: 12) {
                ZStack {
                    if hasImage {
                        VehicleLargeImageView(vehicleID: id)
                            .id(refreshID)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(ColorTheme.secondaryBackground)
                            .frame(height: 200)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
                                    .foregroundColor(ColorTheme.secondary)
                            )
                            .overlay(
                                VStack(spacing: 12) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(ColorTheme.secondary)
                                    Text(addPhotosText)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(ColorTheme.secondary)
                                }
                            )
                    }
                }
                .padding(.horizontal)

                if isEditing {
                    HStack(spacing: 12) {
                        PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 20, matching: .images) {
                            Label(addPhotosText, systemImage: "photo.on.rectangle.angled")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(ColorTheme.primary.opacity(0.12))
                                .foregroundColor(ColorTheme.primary)
                                .cornerRadius(12)
                        }
                        .disabled(isUploadingPhotos)

                        
                    }
                    .padding(.horizontal)
                }

                if !vehiclePhotos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(vehiclePhotos, id: \.id) { photo in
                                VehiclePhotoThumbnail(
                                    vehicleId: id,
                                    photoId: photo.id,
                                    isEditing: isEditing,
                                    onSetCover: {
                                        Task { await setCoverPhoto(photo) }
                                    },
                                    onDelete: {
                                        photoPendingDelete = photo
                                        showPhotoDeleteDialog = true
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var editModeView: some View {
        let canSeeCost = permissionService.canViewVehicleCost()

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
                    editRow(label: "mileage".localizedString, text: $editMileage, placeholder: "0", keyboardType: .numberPad)
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

                    if canSeeCost {
                        editRow(label: "purchase_price".localizedString, text: $editPurchasePrice, placeholder: "0.00", keyboardType: .decimalPad)
                        Divider().padding(.leading)
                    }

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
        if permissionService.canViewVehicleCost() {
            displayExpensesView
        }
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
        let canSeeCost = PermissionService.shared.canViewVehicleCost()

        return VStack(alignment: .leading, spacing: 12) {
            Text("financial_summary_section".localizedString)
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                DatePicker("purchase_date_label".localizedString, selection: $editPurchaseDate, displayedComponents: .date)
                
                if canSeeCost {
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
                }
                
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
        let canSeeCost = PermissionService.shared.canViewVehicleCost()
        let canSeeProfit = PermissionService.shared.canViewVehicleProfit()

        return VStack(alignment: .leading, spacing: 12) {
            Text("financial_summary_section".localizedString)
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                // Days in Inventory Indicator
                if vehicle.status != "sold" {
                    DaysInInventoryIndicator(days: daysInInventory, showLabel: true, isCompact: false)
                }
                
                // Public Info: Asking Price & Report
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

                if canSeeCost {
                    Divider()
                    
                    HStack {
                        Text("purchase_price".localizedString)
                            .foregroundColor(ColorTheme.secondaryText)
                        Spacer()
                        Text((vehicle.purchasePrice?.decimalValue ?? 0).asCurrency())
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("total_expenses_label".localizedString)
                            .foregroundColor(ColorTheme.secondaryText)
                        Spacer()
                        Text(totalExpenses.asCurrency())
                            .fontWeight(.medium)
                            .foregroundColor(ColorTheme.accent)
                    }
                    
                    // Holding Cost
                    if holdingCost > 0 {
                        HStack {
                            Text("holding_cost".localizedString)
                                .foregroundColor(ColorTheme.secondaryText)
                            Spacer()
                            Text(holdingCost.asCurrency())
                                .fontWeight(.medium)
                                .foregroundColor(ColorTheme.warning)
                        }
                        
                        if dailyHoldingCost > 0 {
                            HStack {
                                Text("holding_cost_per_day".localizedString)
                                    .foregroundColor(ColorTheme.secondaryText)
                                Spacer()
                                Text(dailyHoldingCost.asCurrency())
                                    .fontWeight(.medium)
                                    .foregroundColor(ColorTheme.warning)
                            }
                        }
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
                    
                    // Profit Estimate (if asking price set)
                    if let estimate = profitEstimate, vehicle.status != "sold" {
                        Divider()
                        HStack {
                            Text("estimated_profit".localizedString)
                                .font(.subheadline)
                                .foregroundColor(ColorTheme.secondaryText)
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: estimate >= 0 ? "arrow.up" : "arrow.down")
                                    .font(.caption)
                                Text(estimate.asCurrency())
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(estimate >= 0 ? ColorTheme.success : ColorTheme.danger)
                        }
                    }
                }
                
                if let sale = vehicle.salePrice?.decimalValue {
                    Divider()
                    
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
                    
                    // ROI Display
                    if let roi = roiPercent {
                        HStack {
                            Text("roi".localizedString)
                                .foregroundColor(ColorTheme.secondaryText)
                            Spacer()
                            ROIBadge(roi: roi, isCompact: true, showLabel: false)
                        }
                    }
                    
                    if canSeeProfit, let p = profit {
                        Divider()
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
        let previousPurchasePrice = vehicle.purchasePrice?.decimalValue ?? 0
        let purchaseAccountId = vehicle.purchaseAccountId
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
        if let m = Int32(editMileage) { vehicle.mileage = m } else { vehicle.mileage = 0 }
        vehicle.purchaseDate = editPurchaseDate
        let trimmedNotes = editNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        vehicle.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            
        let ap = sanitizedDecimal(from: editAskingPrice) ?? 0
        vehicle.askingPrice = ap > 0 ? NSDecimalNumber(decimal: ap) : nil
        vehicle.reportURL = editReportURL.isEmpty ? nil : editReportURL

        // Prices & status
        if permissionService.canViewVehicleCost() {
            let newPurchasePrice = sanitizedDecimal(from: editPurchasePrice) ?? 0
            if newPurchasePrice != previousPurchasePrice,
               let accountId = purchaseAccountId,
               let account = fetchAccount(by: accountId) {
                let delta = newPurchasePrice - previousPurchasePrice
                if delta != 0 {
                    let currentBalance = account.balance?.decimalValue ?? 0
                    account.balance = NSDecimalNumber(decimal: currentBalance - delta)
                    account.updatedAt = Date()
                    trackAccount(account)
                }
            }
            vehicle.purchasePrice = NSDecimalNumber(decimal: newPurchasePrice)
        }
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
        Task {
            await buildShareItems()
        }
    }

    private func buildShareItems() async {
        guard let id = vehicle.id else { return }

        let reportLink = vehicle.reportURL ?? ""
        let askingPrice = vehicle.askingPrice?.decimalValue ?? 0
        let make = vehicle.make ?? ""
        let model = vehicle.model ?? ""
        let year = vehicle.year
        let vin = vehicle.vin ?? ""
        let dealerId = CloudSyncEnvironment.currentDealerId

        var photos = vehiclePhotos
        if photos.isEmpty, let dealerId {
            photos = (try? await CloudSyncManager.shared?.fetchVehiclePhotos(dealerId: dealerId, vehicleId: id)) ?? []
        }
        if let dealerId {
            for photo in photos {
                await CloudSyncManager.shared?.downloadVehiclePhoto(photo, dealerId: dealerId)
            }
        }

        let primaryImage = await loadPrimaryImage(vehicleId: id, dealerId: dealerId)

        let cardView = VehicleShareCard(
            image: primaryImage,
            make: make,
            model: model,
            year: year,
            vin: vin,
            price: askingPrice,
            hasReport: !reportLink.isEmpty,
            dealerName: sessionStore.activeOrganizationName ?? "Ezcar24"
        )

        let renderer = ImageRenderer(content: cardView)
        renderer.scale = UIScreen.main.scale

        var items: [Any] = []
        if let cardImage = renderer.uiImage {
            items.append(cardImage)
        }

        if let dealerId {
            for photo in photos {
                if let image = await loadPhotoImage(vehicleId: id, photoId: photo.id, dealerId: dealerId) {
                    items.append(image)
                }
            }
        }

        let contactPhone = currentUserPhone()
        let shareUrl = dealerId != nil ? await CloudSyncManager.shared?.createVehicleShareLink(
            vehicleId: id,
            dealerId: dealerId!,
            contactPhone: contactPhone,
            contactWhatsApp: contactPhone
        ) : nil

        var message = "Check out this \(year.asYear()) \(make) \(model)!"
        if askingPrice > 0 {
            message += " Asking: \(askingPrice.asCurrency())"
        }
        if !reportLink.isEmpty {
            message += "\n\nFull Inspection Report: \(reportLink)"
        }
        if let shareUrl {
            message += "\n\nView all photos: \(shareUrl.absoluteString)"
        }
        items.append(message)

        if let shareUrl {
            items.append(shareUrl)
        } else if let url = URL(string: reportLink) {
            items.append(url)
        }

        await MainActor.run {
            self.shareItems = items
            self.showShareSheet = true
        }
    }
    
    private func currentSale(for vehicle: Vehicle) -> Sale? {
        let sales = (vehicle.sales as? Set<Sale>)?.filter { $0.deletedAt == nil } ?? []
        return sales.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.first
    }

    private func fetchAccount(by id: UUID) -> FinancialAccount? {
        let request: NSFetchRequest<FinancialAccount> = FinancialAccount.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
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
    let dealerName: String
    
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
                        
                        Text(dealerName)
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
        let dealerId = CloudSyncEnvironment.currentDealerId
        ImageStore.shared.swiftUIImage(id: vehicleID, dealerId: dealerId) { loaded in
            self.image = loaded
        }
    }
}

struct PendingVehiclePhoto: Identifiable {
    let id: UUID
    let data: Data
    let image: Image
}

struct PhotoUploadSheet: View {
    let photos: [PendingVehiclePhoto]
    @Binding var replaceCover: Bool
    @Binding var isUploading: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if photos.isEmpty {
                    Text("no_photos_selected".localizedString)
                        .foregroundColor(ColorTheme.secondaryText)
                        .padding(.top, 24)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(photos) { photo in
                                photo.image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 100)
                                    .clipped()
                                    .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                Toggle("replace_cover_photo".localizedString, isOn: $replaceCover)
                    .padding(.horizontal, 16)

                if isUploading {
                    ProgressView()
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("upload_photos".localizedString)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("cancel".localizedString) {
                        onCancel()
                    }
                    .disabled(isUploading)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("upload".localizedString) {
                        onConfirm()
                    }
                    .disabled(isUploading || photos.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(isUploading)
    }
}

struct VehiclePhotoThumbnail: View {
    let vehicleId: UUID
    let photoId: UUID
    let isEditing: Bool
    let onSetCover: (() -> Void)?
    let onDelete: (() -> Void)?
    @State private var image: Image? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.12))
                .frame(width: 120, height: 80)
            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 80)
                    .clipped()
                    .cornerRadius(10)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(ColorTheme.secondaryText)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isEditing {
                Button {
                    onDelete?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .onAppear { loadImage() }
        .onReceive(NotificationCenter.default.publisher(for: .vehicleImageUpdated)) { notification in
            if let updatedID = notification.object as? UUID, updatedID == vehicleId {
                loadImage()
            }
        }
        .contextMenu {
            if isEditing {
                Button("set_as_cover".localizedString) {
                    onSetCover?()
                }
                Button(role: .destructive) {
                    onDelete?()
                } label: {
                    Text("delete_photo".localizedString)
                }
            }
        }
    }

    private func loadImage() {
        let dealerId = CloudSyncEnvironment.currentDealerId
        ImageStore.shared.swiftUIImagePhoto(vehicleId: vehicleId, photoId: photoId, dealerId: dealerId) { loaded in
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
