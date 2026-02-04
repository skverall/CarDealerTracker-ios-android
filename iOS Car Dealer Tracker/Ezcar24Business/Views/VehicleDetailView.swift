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
import UniformTypeIdentifiers

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
    @State private var showPhotoManager: Bool = false
    @State private var showPhotoViewer: Bool = false
    @State private var photoViewerItems: [PhotoViewerItem] = []
    @State private var photoViewerIndex: Int = 0
    @State private var isSavingPhotoOrder: Bool = false
    @State private var refreshID = UUID()
    @State private var editStatus: String = "owned"
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

    private func normalizedStatus(_ status: String?) -> String {
        let value = status ?? "owned"
        return value == "reserved" ? "owned" : value
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

    private func buildViewerItems() -> [PhotoViewerItem] {
        guard let id = vehicle.id else { return [] }
        let dealerId = CloudSyncEnvironment.currentDealerId
        var items: [PhotoViewerItem] = []
        if ImageStore.shared.hasImage(id: id, dealerId: dealerId) {
            items.append(PhotoViewerItem(id: "cover", kind: .cover))
        }
        items.append(contentsOf: vehiclePhotos.map { PhotoViewerItem(id: $0.id.uuidString, kind: .photo($0)) })
        return items
    }

    private func openPhotoViewer(startingAt index: Int) {
        let items = buildViewerItems()
        guard !items.isEmpty else { return }
        photoViewerItems = items
        photoViewerIndex = min(max(0, index), items.count - 1)
        showPhotoViewer = true
    }

    private func savePhotoOrder(_ ordered: [RemoteVehiclePhoto]) {
        guard let dealerId = CloudSyncEnvironment.currentDealerId else { return }
        isSavingPhotoOrder = true
        Task {
            await CloudSyncManager.shared?.updateVehiclePhotoOrder(photos: ordered, dealerId: dealerId)
            await refreshVehiclePhotos()
            await MainActor.run {
                isSavingPhotoOrder = false
            }
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
                        editStatus = normalizedStatus(vehicle.status)
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
        .sheet(isPresented: $showPhotoManager) {
            if let id = vehicle.id {
                PhotoManagerSheet(
                    vehicleId: id,
                    photos: vehiclePhotos,
                    hasCover: ImageStore.shared.hasImage(id: id, dealerId: CloudSyncEnvironment.currentDealerId),
                    isSaving: $isSavingPhotoOrder,
                    onSave: { ordered in
                        savePhotoOrder(ordered)
                    },
                    onSetCover: { photo in
                        Task { await setCoverPhoto(photo) }
                    },
                    onDelete: { photo in
                        photoPendingDelete = photo
                        showPhotoDeleteDialog = true
                    },
                    onClose: {
                        showPhotoManager = false
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showPhotoViewer) {
            if let id = vehicle.id {
                VehiclePhotoViewer(
                    vehicleId: id,
                    items: photoViewerItems,
                    startIndex: photoViewerIndex,
                    onClose: { showPhotoViewer = false },
                    onSetCover: { photo in
                        Task { await setCoverPhoto(photo) }
                        showPhotoViewer = false
                    },
                    onDeletePhoto: { photo in
                        photoPendingDelete = photo
                        showPhotoDeleteDialog = true
                        showPhotoViewer = false
                    },
                    onDeleteCover: {
                        if let dealerId = CloudSyncEnvironment.currentDealerId {
                            Task { await CloudSyncManager.shared?.deleteVehicleImage(vehicleId: id, dealerId: dealerId) }
                        }
                        ImageStore.shared.delete(id: id, dealerId: CloudSyncEnvironment.currentDealerId) {
                            refreshID = UUID()
                        }
                        showPhotoViewer = false
                    }
                )
            }
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
            editStatus = normalizedStatus(vehicle.status)
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
                .onTapGesture {
                    if hasImage || !vehiclePhotos.isEmpty {
                        openPhotoViewer(startingAt: 0)
                    }
                }

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
                        Button {
                            showPhotoManager = true
                        } label: {
                            Label("manage_photos".localizedString, systemImage: "square.grid.2x2")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(ColorTheme.cardBackground)
                                .foregroundColor(ColorTheme.primaryText)
                                .cornerRadius(12)
                        }
                        .disabled(isUploadingPhotos || (!hasImage && vehiclePhotos.isEmpty))
                    }
                    .padding(.horizontal)
                }

                if !vehiclePhotos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(vehiclePhotos.enumerated()), id: \.element.id) { index, photo in
                                VehiclePhotoThumbnail(
                                    vehicleId: id,
                                    photoId: photo.id,
                                    isEditing: isEditing,
                                    onTap: {
                                        let start = (hasImage ? 1 : 0) + index
                                        openPhotoViewer(startingAt: start)
                                    },
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
                            Text("status_owned".localizedString).tag("owned")
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

struct PhotoViewerItem: Identifiable {
    enum Kind {
        case cover
        case photo(RemoteVehiclePhoto)
    }

    let id: String
    let kind: Kind
}

struct VehiclePhotoViewer: View {
    let vehicleId: UUID
    let items: [PhotoViewerItem]
    let startIndex: Int
    let onClose: () -> Void
    let onSetCover: (RemoteVehiclePhoto) -> Void
    let onDeletePhoto: (RemoteVehiclePhoto) -> Void
    let onDeleteCover: () -> Void

    @State private var index: Int = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    PhotoViewerPage(vehicleId: vehicleId, item: item)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text("\(index + 1)/\(items.count)")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if let current = currentPhotoItem {
                        Menu {
                            Button("set_as_cover".localizedString) {
                                onSetCover(current)
                            }
                            Button("delete_photo".localizedString, role: .destructive) {
                                onDeletePhoto(current)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    } else {
                        Menu {
                            Button("remove_cover".localizedString, role: .destructive) {
                                onDeleteCover()
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                Spacer()
            }
        }
        .onAppear { index = startIndex }
    }

    private var currentPhotoItem: RemoteVehiclePhoto? {
        guard index >= 0, index < items.count else { return nil }
        if case .photo(let photo) = items[index].kind {
            return photo
        }
        return nil
    }
}

struct PhotoViewerPage: View {
    let vehicleId: UUID
    let item: PhotoViewerItem
    @State private var uiImage: UIImage? = nil
    @State private var isLoading: Bool = true

    var body: some View {
        ZStack {
            if let uiImage {
                ZoomableImage(uiImage: uiImage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .onAppear { loadImage() }
    }

    private func loadImage() {
        isLoading = true
        uiImage = nil
        let dealerId = CloudSyncEnvironment.currentDealerId
        switch item.kind {
        case .cover:
            ImageStore.shared.load(id: vehicleId, dealerId: dealerId) { loaded in
                self.uiImage = loaded
                self.isLoading = false
            }
        case .photo(let photo):
            ImageStore.shared.loadPhoto(vehicleId: vehicleId, photoId: photo.id, dealerId: dealerId) { loaded in
                self.uiImage = loaded
                self.isLoading = false
            }
        }
    }
}

struct ZoomableImage: View {
    let uiImage: UIImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0

    var body: some View {
        GeometryReader { geo in
            let container = geo.size
            let baseSize = aspectFitSize(imageSize: uiImage.size, in: container)
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnificationGesture(baseSize: baseSize, container: container))
                .simultaneousGesture(dragGesture(baseSize: baseSize, container: container))
                .onTapGesture(count: 2) {
                    reset()
                }
                .frame(width: container.width, height: container.height)
        }
    }

    private func magnificationGesture(baseSize: CGSize, container: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let proposed = lastScale * value
                scale = min(max(proposed, minScale), maxScale)
                offset = clampOffset(offset, baseSize: baseSize, container: container, scale: scale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= minScale {
                    reset()
                } else {
                    let clamped = clampOffset(offset, baseSize: baseSize, container: container, scale: scale)
                    if clamped != offset {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            offset = clamped
                        }
                    } else {
                        offset = clamped
                    }
                }
            }
    }

    private func dragGesture(baseSize: CGSize, container: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > minScale else { return }
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = rubberBandOffset(proposed, baseSize: baseSize, container: container, scale: scale)
            }
            .onEnded { _ in
                guard scale > minScale else {
                    reset()
                    return
                }
                let clamped = clampOffset(offset, baseSize: baseSize, container: container, scale: scale)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    offset = clamped
                }
                lastOffset = clamped
            }
    }

    private func reset() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            scale = minScale
            lastScale = minScale
            offset = .zero
            lastOffset = .zero
        }
    }

    private func clampOffset(_ offset: CGSize, baseSize: CGSize, container: CGSize, scale: CGFloat) -> CGSize {
        guard scale > minScale else { return .zero }
        let maxX = max(0, (baseSize.width * scale - container.width) / 2)
        let maxY = max(0, (baseSize.height * scale - container.height) / 2)
        let clampedX = min(max(offset.width, -maxX), maxX)
        let clampedY = min(max(offset.height, -maxY), maxY)
        return CGSize(width: clampedX, height: clampedY)
    }

    private func rubberBandOffset(_ offset: CGSize, baseSize: CGSize, container: CGSize, scale: CGFloat) -> CGSize {
        guard scale > minScale else { return .zero }
        let maxX = max(0, (baseSize.width * scale - container.width) / 2)
        let maxY = max(0, (baseSize.height * scale - container.height) / 2)
        return CGSize(
            width: rubberBand(offset.width, limit: maxX),
            height: rubberBand(offset.height, limit: maxY)
        )
    }

    private func rubberBand(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 0 else { return 0 }
        let magnitude = abs(value)
        guard magnitude > limit else { return value }
        let excess = magnitude - limit
        let damped = limit + (excess * 0.25)
        return value < 0 ? -damped : damped
    }

    private func aspectFitSize(imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return container
        }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = container.width / container.height
        if imageAspect > containerAspect {
            let width = container.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            let height = container.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }
}

struct PhotoManagerSheet: View {
    let vehicleId: UUID
    let photos: [RemoteVehiclePhoto]
    let hasCover: Bool
    @Binding var isSaving: Bool
    let onSave: ([RemoteVehiclePhoto]) -> Void
    let onSetCover: (RemoteVehiclePhoto) -> Void
    let onDelete: (RemoteVehiclePhoto) -> Void
    let onClose: () -> Void

    @State private var workingPhotos: [RemoteVehiclePhoto]
    @State private var draggingPhoto: RemoteVehiclePhoto? = nil
    @State private var didReorder: Bool = false
    @State private var photoFrames: [UUID: CGRect] = [:]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    init(
        vehicleId: UUID,
        photos: [RemoteVehiclePhoto],
        hasCover: Bool,
        isSaving: Binding<Bool>,
        onSave: @escaping ([RemoteVehiclePhoto]) -> Void,
        onSetCover: @escaping (RemoteVehiclePhoto) -> Void,
        onDelete: @escaping (RemoteVehiclePhoto) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.vehicleId = vehicleId
        self.photos = photos
        self.hasCover = hasCover
        self._isSaving = isSaving
        self.onSave = onSave
        self.onSetCover = onSetCover
        self.onDelete = onDelete
        self.onClose = onClose
        _workingPhotos = State(initialValue: photos)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if hasCover {
                        CoverPhotoTile(vehicleId: vehicleId)
                            .padding(.horizontal, 16)
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(workingPhotos.enumerated()), id: \.element.id) { index, photo in
                            PhotoGridCell(
                                vehicleId: vehicleId,
                                photo: photo,
                                index: index + 1,
                                isDragging: draggingPhoto?.id == photo.id,
                                onSetCover: {
                                    onSetCover(photo)
                                },
                                onDelete: {
                                    onDelete(photo)
                                }
                            )
                            .onDrag {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.prepare()
                                generator.impactOccurred()
                                draggingPhoto = photo
                                return NSItemProvider(object: photo.id.uuidString as NSString)
                            }
                            .onDrop(of: [UTType.text], delegate: PhotoDropDelegate(
                                item: photo,
                                items: $workingPhotos,
                                dragging: $draggingPhoto,
                                didReorder: $didReorder
                            ))
                        }
                    }
                    .coordinateSpace(name: "PhotoGrid")
                    .onPreferenceChange(PhotoFramePreferenceKey.self) { values in
                        var updated: [UUID: CGRect] = [:]
                        for value in values {
                            updated[value.id] = value.frame
                        }
                        photoFrames = updated
                    }
                    .onDrop(of: [UTType.text], delegate: PhotoGridDropDelegate(
                        items: $workingPhotos,
                        frames: $photoFrames,
                        dragging: $draggingPhoto,
                        didReorder: $didReorder
                    ))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .padding(.top, 12)
            }
            .navigationTitle("photo_gallery".localizedString)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("cancel".localizedString) {
                        onClose()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("save_order".localizedString) {
                        onSave(workingPhotos)
                    }
                    .disabled(isSaving || workingPhotos.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: workingPhotos.map { $0.id })
        .onChange(of: photos.map { $0.id }) { _, _ in
            workingPhotos = photos
        }
    }
}

struct PhotoDropDelegate: DropDelegate {
    let item: RemoteVehiclePhoto
    @Binding var items: [RemoteVehiclePhoto]
    @Binding var dragging: RemoteVehiclePhoto?
    @Binding var didReorder: Bool

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging.id != item.id else { return }
        guard let from = items.firstIndex(where: { $0.id == dragging.id }),
              let to = items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        didReorder = true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        if didReorder {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
        dragging = nil
        didReorder = false
        return true
    }
}

struct PhotoFrameData: Equatable {
    let id: UUID
    let frame: CGRect
}

struct PhotoFramePreferenceKey: PreferenceKey {
    static var defaultValue: [PhotoFrameData] = []
    static func reduce(value: inout [PhotoFrameData], nextValue: () -> [PhotoFrameData]) {
        value.append(contentsOf: nextValue())
    }
}

struct PhotoGridDropDelegate: DropDelegate {
    @Binding var items: [RemoteVehiclePhoto]
    @Binding var frames: [UUID: CGRect]
    @Binding var dragging: RemoteVehiclePhoto?
    @Binding var didReorder: Bool

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragging, !frames.isEmpty else {
            self.dragging = nil
            didReorder = false
            return true
        }
        let location = info.location
        if let targetId = nearestPhotoId(to: location), let from = items.firstIndex(where: { $0.id == dragging.id }),
           let to = items.firstIndex(where: { $0.id == targetId }), from != to {
            withAnimation {
                items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
            didReorder = true
        }
        if didReorder {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
        self.dragging = nil
        didReorder = false
        return true
    }

    private func nearestPhotoId(to point: CGPoint) -> UUID? {
        frames.min(by: { lhs, rhs in
            let leftCenter = CGPoint(x: lhs.value.midX, y: lhs.value.midY)
            let rightCenter = CGPoint(x: rhs.value.midX, y: rhs.value.midY)
            let left = distance(from: leftCenter, to: point)
            let right = distance(from: rightCenter, to: point)
            return left < right
        })?.key
    }

    private func distance(from a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

struct CoverPhotoTile: View {
    let vehicleId: UUID
    @State private var image: Image? = nil

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(ColorTheme.secondaryBackground)
                .frame(height: 160)
            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .clipped()
                    .cornerRadius(14)
            }
            Text("cover_photo".localizedString)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.5))
                .cornerRadius(10)
                .padding(10)
        }
        .onAppear { loadImage() }
        .onReceive(NotificationCenter.default.publisher(for: .vehicleImageUpdated)) { notification in
            if let updatedID = notification.object as? UUID, updatedID == vehicleId {
                loadImage()
            }
        }
    }

    private func loadImage() {
        let dealerId = CloudSyncEnvironment.currentDealerId
        ImageStore.shared.swiftUIImage(id: vehicleId, dealerId: dealerId) { loaded in
            self.image = loaded
        }
    }
}

struct PhotoGridCell: View {
    let vehicleId: UUID
    let photo: RemoteVehiclePhoto
    let index: Int
    let isDragging: Bool
    let onSetCover: () -> Void
    let onDelete: () -> Void

    @State private var image: Image? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorTheme.secondaryBackground)
                .frame(height: 110)
            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(height: 110)
                    .clipped()
                    .cornerRadius(12)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundColor(ColorTheme.secondaryText)
            }

            HStack(spacing: 6) {
                Text("\(index)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                Menu {
                    Button("set_as_cover".localizedString) {
                        onSetCover()
                    }
                    Button("delete_photo".localizedString, role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.white)
                        .font(.title3)
                }
            }
            .padding(6)
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "line.3.horizontal")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(6)
                .background(Color.black.opacity(0.5))
                .cornerRadius(8)
                .padding(6)
        }
        .scaleEffect(isDragging ? 1.03 : 1.0)
        .opacity(isDragging ? 0.88 : 1.0)
        .shadow(color: Color.black.opacity(isDragging ? 0.2 : 0.0), radius: isDragging ? 10 : 0, x: 0, y: 6)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: PhotoFramePreferenceKey.self,
                    value: [PhotoFrameData(id: photo.id, frame: geo.frame(in: .named("PhotoGrid")))]
                )
            }
        )
        .onAppear { loadImage() }
    }

    private func loadImage() {
        let dealerId = CloudSyncEnvironment.currentDealerId
        ImageStore.shared.swiftUIImagePhoto(vehicleId: vehicleId, photoId: photo.id, dealerId: dealerId) { loaded in
            self.image = loaded
        }
    }
}

struct VehiclePhotoThumbnail: View {
    let vehicleId: UUID
    let photoId: UUID
    let isEditing: Bool
    let onTap: (() -> Void)?
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
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            if !isEditing { onTap?() }
        }
        .onLongPressGesture {
            if isEditing { onTap?() }
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
    vehicle.status = "owned"
    vehicle.createdAt = Date()

    return NavigationStack {
        VehicleDetailView(vehicle: vehicle)
            .environment(\.managedObjectContext, context)
    }
}
