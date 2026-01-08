//
//  AddVehicleView.swift
//  Ezcar24Business
//
//  Form for adding new vehicles
//

import SwiftUI
import PhotosUI
import CoreData

struct AddVehicleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSessionState: AppSessionState
    @ObservedObject var viewModel: VehicleViewModel
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    
    @State private var vin = ""
    @State private var make = ""
    @State private var model = ""
    @State private var year = ""
    @State private var purchasePrice = ""
    @State private var purchaseDate = Date()
    @State private var status = "owned"
    @State private var notes = ""
    @State private var salePrice = ""
    @State private var saleDate = Date()
    
    @State private var showingPaywall = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FinancialAccount.accountType, ascending: true)],
        animation: .default
    )
    private var accounts: FetchedResults<FinancialAccount>

    @State private var selectedAccount: FinancialAccount? = nil

    // Photo picking
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var selectedImage: Image? = nil
    @State private var isCompressing = false

    // Use keys for localization mapping
    let statusOrder = ["owned", "on_sale", "in_transit", "under_service", "sold"]
    
    func localizedStatus(_ key: String) -> LocalizedStringKey {
        switch key {
        case "owned": return "reserved"
        case "on_sale": return "on_sale"
        case "in_transit": return "in_transit"
        case "under_service": return "under_service"
        case "sold": return "status_sold"
        default: return LocalizedStringKey(key)
        }
    }

    var isFormValid: Bool {
        let baseValid = !vin.isEmpty && !make.isEmpty && !model.isEmpty && !year.isEmpty && !purchasePrice.isEmpty && selectedAccount != nil
        if status == "sold" { return baseValid && !salePrice.isEmpty }
        return baseValid
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Photo Section (Prominent at top)
                    photoSection
                    
                    VStack(spacing: 20) {
                        // Basic Info
                        GroupBox(label: Label("vehicle_details", systemImage: "car.fill")) {
                            VStack(spacing: 12) {
                                CustomTextField(title: "vin", text: $vin, icon: "number")
                                    .textInputAutocapitalization(.characters)
                                
                                HStack(spacing: 12) {
                                    CustomTextField(title: "make", placeholder: "Toyota", text: $make, icon: "tag")
                                    CustomTextField(title: "model", placeholder: "Camry", text: $model, icon: "tag.fill")
                                }
                                
                                CustomTextField(title: "year", text: $year, icon: "calendar")
                                    .keyboardType(.numberPad)
                            }
                            .padding(.vertical, 8)
                        }
                        
                        // Financials
                        GroupBox(label: Label("purchase_and_status", systemImage: "dollarsign.circle.fill")) {
                            VStack(spacing: 12) {
                                CustomTextField(title: "purchase_price", text: $purchasePrice, icon: "banknote")
                                    .keyboardType(.decimalPad)

                                Picker("paid_from", selection: $selectedAccount) {
                                    ForEach(accounts) { account in
                                        Text(account.accountType ?? "Unknown").tag(account as FinancialAccount?)
                                    }
                                }
                                .pickerStyle(.menu)

                                DatePicker("purchase_date", selection: $purchaseDate, displayedComponents: .date)
                                    .padding(.vertical, 4)
                                
                                Divider()
                                
                                Picker("status", selection: $status) {
                                    ForEach(statusOrder, id: \.self) { key in
                                        Text(localizedStatus(key)).tag(key)
                                    }
                                }
                                .pickerStyle(.menu)
                                .padding(.vertical, 4)
                            }
                            .padding(.vertical, 8)
                        }
                        
                        if status == "sold" {
                            GroupBox(label: Label("sale_details", systemImage: "checkmark.circle.fill")) {
                                VStack(spacing: 12) {
                                    CustomTextField(title: "sale_price", text: $salePrice, icon: "banknote.fill")
                                        .keyboardType(.decimalPad)
                                    DatePicker("sale_date", selection: $saleDate, displayedComponents: .date)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        
                        
                        GroupBox(label: Label("notes", systemImage: "note.text")) {
                            TextEditor(text: $notes)
                                .frame(minHeight: 80)
                                .padding(4)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(ColorTheme.secondaryBackground)
            .navigationTitle("add_vehicle_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("save") { saveVehicle() }
                        .disabled(!isFormValid || isCompressing)
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
        .onAppear {
            if accounts.isEmpty {
                createDefaultAccounts()
            }
            applyDefaultAccountIfNeeded()
            if isOverFreeLimit {
                handleUpgradeRequest()
            }
        }
        .onChange(of: accounts.count) { _, _ in
            applyDefaultAccountIfNeeded()
        }
    }
    
    var photoSection: some View {
        VStack {
            ZStack {
                if let image = selectedImage {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(ColorTheme.primary.opacity(0.3), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(ColorTheme.background)
                        .frame(width: 120, height: 120)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(ColorTheme.primary)
                                Text("add_photo")
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.secondaryText)
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                                .foregroundColor(ColorTheme.primary.opacity(0.5))
                        )
                }
                
                if isCompressing {
                    ProgressView()
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
            }
            .onTapGesture {
                // This is just visual, the picker is below or overlay
            }
            .overlay(
                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    Color.clear
                }
                .onChange(of: selectedPhoto) { _, newValue in
                    loadAndCompressImage(from: newValue)
                }
            )
        }
    }
    
    private func saveVehicle() {
        guard ensureCanAddVehicle() else { return }
        guard let yearInt = Int32(year),
              let priceDecimal = Decimal(string: purchasePrice),
              let account = selectedAccount else {
            return
        }

        let salePriceDecimal: Decimal? = (status == "sold") ? Decimal(string: salePrice) : nil

        let vehicle = viewModel.addVehicle(
            vin: vin,
            make: make,
            model: model,
            year: yearInt,
            purchasePrice: priceDecimal,
            purchaseDate: purchaseDate,
            status: status,
            notes: notes,
            account: account,
            imageData: selectedImageData,
            salePrice: salePriceDecimal,
            saleDate: (status == "sold") ? saleDate : nil
        )
        
        let createdSale = (vehicle.sales as? Set<Sale>)?.first(where: { $0.deletedAt == nil })

        if let dealerId = CloudSyncEnvironment.currentDealerId {
            Task {
                await CloudSyncManager.shared?.upsertVehicle(vehicle, dealerId: dealerId)
                await CloudSyncManager.shared?.upsertFinancialAccount(account, dealerId: dealerId)
                if let createdSale {
                    await CloudSyncManager.shared?.upsertSale(createdSale, dealerId: dealerId)
                }
                if let imageData = selectedImageData, let id = vehicle.id {
                    await CloudSyncManager.shared?.uploadVehicleImage(vehicleId: id, dealerId: dealerId, imageData: imageData)
                }
            }
        }

        dismiss()
    }
    
    private var isOverFreeLimit: Bool {
        !subscriptionManager.isProAccessActive &&
        !subscriptionManager.isCheckingStatus &&
        viewModel.vehicles.count >= 3
    }
    
    private func ensureCanAddVehicle() -> Bool {
        if isOverFreeLimit {
            handleUpgradeRequest()
            return false
        }
        return true
    }
    
    private func handleUpgradeRequest() {
        if case .signedIn = sessionStore.status {
            showingPaywall = true
        } else {
            appSessionState.exitGuestModeForLogin()
            dismiss()
        }
    }

    private func applyDefaultAccountIfNeeded() {
        guard selectedAccount == nil, !accounts.isEmpty else { return }
        selectedAccount = accounts.first(where: { ($0.accountType ?? "").lowercased() == "cash" }) ?? accounts.first
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
            viewContext.rollback()
            print("Failed to create default accounts: \(error)")
        }
    }
}

// Helper View for TextFields
struct CustomTextField: View {
    let title: LocalizedStringKey
    var placeholder: LocalizedStringKey = ""
    @Binding var text: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(ColorTheme.secondaryText)
            
            HStack {
                Image(systemName: icon)
                    .foregroundColor(ColorTheme.primary.opacity(0.6))
                    .frame(width: 20)
                
                // If placeholder is "", we default to title as placeholder. 
                // However, checking isEmpty on LocalizedStringKey is not straightforward.
                // Simplified: usage always provides a valid title. 
                TextField(placeholder, text: $text)
            }
            .padding(10)
            .background(ColorTheme.background)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

extension AddVehicleView {
    // Logic to load and compress image
    func loadAndCompressImage(from item: PhotosPickerItem?) {
        guard let item else { return }
        isCompressing = true
        
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                
                // Compress
                let compressedData = uiImage.compressed()
                
                await MainActor.run {
                    self.selectedImageData = compressedData
                    if let compressedData, let compressedImage = UIImage(data: compressedData) {
                        self.selectedImage = Image(uiImage: compressedImage)
                        print("Original size: \(data.count) bytes, Compressed: \(compressedData.count) bytes")
                    } else {
                        // Fallback if compression fails
                        self.selectedImage = Image(uiImage: uiImage)
                        self.selectedImageData = data
                    }
                    self.isCompressing = false
                }
            } else {
                await MainActor.run {
                    isCompressing = false
                }
            }
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let viewModel = VehicleViewModel(context: context)
    let provider = SupabaseClientProvider()
    let sessionStore = SessionStore(client: provider.client)
    let appSessionState = AppSessionState(sessionStore: sessionStore)
    
    return AddVehicleView(viewModel: viewModel)
        .environment(\.managedObjectContext, context)
        .environmentObject(sessionStore)
        .environmentObject(appSessionState)
}


extension UIImage {
    /// Resizes the image to fit within the maxDimension and compresses it to the specified quality.
    /// Returns the JPEG data.
    func compressed(maxDimension: CGFloat = 1024, compressionQuality: CGFloat = 0.7) -> Data? {
        var actualHeight = self.size.height
        var actualWidth = self.size.width
        let maxHeight: CGFloat = maxDimension
        let maxWidth: CGFloat = maxDimension
        var imgRatio = actualWidth / actualHeight
        let maxRatio = maxWidth / maxHeight
        
        // Resize logic
        if actualHeight > maxHeight || actualWidth > maxWidth {
            if imgRatio < maxRatio {
                // Adjust width according to maxHeight
                imgRatio = maxHeight / actualHeight
                actualWidth = imgRatio * actualWidth
                actualHeight = maxHeight
            } else if imgRatio > maxRatio {
                // Adjust height according to maxWidth
                imgRatio = maxWidth / actualWidth
                actualHeight = imgRatio * actualHeight
                actualWidth = maxWidth
            } else {
                actualHeight = maxHeight
                actualWidth = maxWidth
            }
        }
        
        let rect = CGRect(x: 0.0, y: 0.0, width: actualWidth, height: actualHeight)
        UIGraphicsBeginImageContext(rect.size)
        self.draw(in: rect)
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let resizedImage = img else { return nil }
        
        // Compress
        return resizedImage.jpegData(compressionQuality: compressionQuality)
    }
}
