import Foundation
import SwiftUI
import CoreData
import Combine

@MainActor
class NotionExportViewModel: ObservableObject {
    
    typealias ExportType = NotionExportType
    
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    
    @Published var selectedExportTypes: Set<NotionExportType> = [.vehicles]
    @Published var selectedDatabaseId: String?
    @Published var createNewDatabase: Bool = false
    @Published var newDatabaseName: String = "Car Dealer Data"
    @Published var parentPageId: String = ""
    
    @Published var startDate: Date = Date().addingTimeInterval(-90*24*60*60)
    @Published var endDate: Date = Date()
    
    @Published var isExporting: Bool = false
    @Published var exportProgress: Double = 0
    @Published var exportedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var currentItem: String = ""
    @Published var errorMessage: String?
    @Published var exportResults: ExportResults?
    @Published var showSuccessAlert: Bool = false
    
    @Published var availableDatabases: [NotionDatabase] = []
    @Published var isLoadingDatabases: Bool = false
    
    @Published var showAuthSheet: Bool = false
    @Published var authUrl: URL?
    
    private let notionService = NotionAPIService.shared
    private let authManager = NotionAuthManager.shared
    private let context: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()
    
    init(context: NSManagedObjectContext? = nil) {
        self.context = context ?? PersistenceController.shared.viewContext
        
        authManager.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .assign(to: &$isConnected)
        
        authManager.$accessToken
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if self?.isConnected == true {
                    Task {
                        await self?.fetchDatabases()
                    }
                }
            }
            .store(in: &cancellables)
        
        isConnected = authManager.isAuthenticated
        if isConnected {
            Task {
                await fetchDatabases()
            }
        }
    }
    
    func connectToNotion() {
        guard let url = authManager.initiateOAuth() else {
            errorMessage = "Failed to create OAuth URL"
            return
        }
        
        authUrl = url
        showAuthSheet = true
    }
    
    func handleAuthCallback(url: URL) {
        Task {
            isConnecting = true
            defer { isConnecting = false }
            
            do {
                try await authManager.handleCallback(url: url)
                showAuthSheet = false
                await fetchDatabases()
            } catch {
                errorMessage = "Authentication failed: \(error.localizedDescription)"
            }
        }
    }
    
    func disconnect() {
        authManager.logout()
        availableDatabases = []
        selectedDatabaseId = nil
    }
    
    func fetchDatabases() async {
        isLoadingDatabases = true
        defer { isLoadingDatabases = false }
        
        do {
            availableDatabases = try await notionService.listDatabases()
        } catch {
            errorMessage = "Failed to fetch databases: \(error.localizedDescription)"
        }
    }
    
    func exportData() {
        guard !selectedExportTypes.isEmpty else {
            errorMessage = "Please select at least one export type"
            return
        }
        
        if createNewDatabase && parentPageId.isEmpty {
            errorMessage = "Please enter a parent page ID for the new database"
            return
        }
        
        isExporting = true
        exportProgress = 0
        exportedCount = 0
        exportResults = nil
        errorMessage = nil
        
        Task {
            do {
                var vehiclesResult: ExportResult?
                var leadsResult: ExportResult?
                var salesResult: ExportResult?
                
                let totalTypes = selectedExportTypes.count
                var completedTypes = 0
                
                for exportType in selectedExportTypes {
                    currentItem = "Exporting \(exportType.rawValue)..."
                    
                    let databaseId: String
                    let database: NotionDatabase?
                    if createNewDatabase {
                        let createdDatabase = try await createNotionDatabase(name: newDatabaseName, type: exportType)
                        databaseId = createdDatabase.id
                        database = createdDatabase
                    } else {
                        guard let selectedId = selectedDatabaseId else {
                            throw NotionError.databaseNotFound
                        }
                        databaseId = selectedId
                        database = availableDatabases.first { $0.id == selectedId }
                    }
                    
                    switch exportType {
                    case .vehicles:
                        let vehicles = try await fetchVehiclesForExport()
                        totalCount = vehicles.count
                        exportedCount = 0
                        vehiclesResult = try await exportVehiclesWithProgress(vehicles, databaseId: databaseId, database: database)
                        
                    case .leads:
                        let leads = try await fetchLeadsForExport()
                        totalCount = leads.count
                        exportedCount = 0
                        leadsResult = try await exportLeadsWithProgress(leads, databaseId: databaseId, database: database)
                        
                    case .sales:
                        let sales = try await fetchSalesForExport()
                        totalCount = sales.count
                        exportedCount = 0
                        salesResult = try await exportSalesWithProgress(sales, databaseId: databaseId, database: database)
                    }
                    
                    completedTypes += 1
                    exportProgress = Double(completedTypes) / Double(totalTypes)
                }
                
                exportResults = ExportResults(
                    vehiclesResult: vehiclesResult,
                    leadsResult: leadsResult,
                    salesResult: salesResult
                )
                
                showSuccessAlert = true
                
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
            
            isExporting = false
        }
    }
    
    func createNotionDatabase(name: String, type: ExportType) async throws -> NotionDatabase {
        let schema = NotionDatabaseTemplates.schema(for: type)
        let databaseName = "\(name) - \(type.rawValue)"
        
        let database = try await notionService.createDatabase(
            name: databaseName,
            properties: schema,
            parentPageId: parentPageId
        )
        
        return database
    }
    
    private func fetchVehiclesForExport() async throws -> [VehicleExportData] {
        let request: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
        request.predicate = NSPredicate(format: "deletedAt == nil AND purchaseDate >= %@ AND purchaseDate <= %@", startDate as NSDate, endDate as NSDate)
        
        let vehicles = try context.fetch(request)
        
        let settings = try? context.fetch(HoldingCostSettings.fetchRequest()).first
        let calculator = HoldingCostCalculator(settings: settings)
        
        return vehicles.map { VehicleExportData(from: $0, holdingCostCalculator: calculator) }
    }
    
    private func fetchLeadsForExport() async throws -> [LeadExportData] {
        let request: NSFetchRequest<Client> = Client.fetchRequest()
        request.predicate = NSPredicate(format: "deletedAt == nil AND createdAt >= %@ AND createdAt <= %@", startDate as NSDate, endDate as NSDate)
        
        let clients = try context.fetch(request)
        return clients.map { LeadExportData(from: $0) }
    }
    
    private func fetchSalesForExport() async throws -> [SaleExportData] {
        let request: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
        request.predicate = NSPredicate(format: "deletedAt == nil AND status == %@ AND saleDate >= %@ AND saleDate <= %@", "sold", startDate as NSDate, endDate as NSDate)
        
        let vehicles = try context.fetch(request)
        
        let settings = try? context.fetch(HoldingCostSettings.fetchRequest()).first
        let calculator = HoldingCostCalculator(settings: settings)
        
        return vehicles.map { SaleExportData(from: $0, holdingCostCalculator: calculator) }
    }
    
    private func exportVehiclesWithProgress(
        _ vehicles: [VehicleExportData],
        databaseId: String,
        database: NotionDatabase?
    ) async throws -> ExportResult {
        var successCount = 0
        var failedVehicles: [String] = []
        
        for (index, vehicle) in vehicles.enumerated() {
            currentItem = "Exporting: \(vehicle.make) \(vehicle.model)"
            exportedCount = index + 1
            
            do {
                let properties = filteredProperties(vehicleToNotionProperties(vehicle), using: database)
                _ = try await notionService.createPage(databaseId: databaseId, properties: properties)
                successCount += 1
            } catch {
                failedVehicles.append(vehicle.vin ?? vehicle.id.uuidString)
            }
        }
        
        return ExportResult(
            successCount: successCount,
            failedCount: failedVehicles.count,
            failedIdentifiers: failedVehicles,
            databaseUrl: nil
        )
    }
    
    private func exportLeadsWithProgress(
        _ leads: [LeadExportData],
        databaseId: String,
        database: NotionDatabase?
    ) async throws -> ExportResult {
        var successCount = 0
        var failedLeads: [String] = []
        
        for (index, lead) in leads.enumerated() {
            currentItem = "Exporting: \(lead.name)"
            exportedCount = index + 1
            
            do {
                let properties = filteredProperties(leadToNotionProperties(lead), using: database)
                _ = try await notionService.createPage(databaseId: databaseId, properties: properties)
                successCount += 1
            } catch {
                failedLeads.append(lead.name)
            }
        }
        
        return ExportResult(
            successCount: successCount,
            failedCount: failedLeads.count,
            failedIdentifiers: failedLeads,
            databaseUrl: nil
        )
    }
    
    private func exportSalesWithProgress(
        _ sales: [SaleExportData],
        databaseId: String,
        database: NotionDatabase?
    ) async throws -> ExportResult {
        var successCount = 0
        var failedSales: [String] = []
        
        for (index, sale) in sales.enumerated() {
            currentItem = "Exporting: \(sale.vehicleMake) \(sale.vehicleModel)"
            exportedCount = index + 1
            
            do {
                let properties = filteredProperties(saleToNotionProperties(sale), using: database)
                _ = try await notionService.createPage(databaseId: databaseId, properties: properties)
                successCount += 1
            } catch {
                failedSales.append(sale.id.uuidString)
            }
        }
        
        return ExportResult(
            successCount: successCount,
            failedCount: failedSales.count,
            failedIdentifiers: failedSales,
            databaseUrl: nil
        )
    }
    
    private func vehicleToNotionProperties(_ vehicle: VehicleExportData) -> [String: NotionValue] {
        var properties: [String: NotionValue] = [
            "VIN": .title(vehicle.vin ?? "Unknown"),
            "Make": .richText(vehicle.make),
            "Model": .richText(vehicle.model),
            "Year": .number(Decimal(vehicle.year)),
            "Purchase Price": .number(vehicle.purchasePrice),
            "Purchase Date": .date(vehicle.purchaseDate),
            "Status": .select(vehicle.status),
            "Total Expenses": .number(vehicle.totalExpenses),
            "Holding Cost": .number(vehicle.holdingCostAccumulated),
            "Holding Cost / Day": .number(vehicle.dailyHoldingCost),
            "Aging Bucket": .select(vehicle.agingBucket)
        ]
        
        if let askingPrice = vehicle.askingPrice {
            properties["Asking Price"] = .number(askingPrice)
        }
        
        if let salePrice = vehicle.salePrice {
            properties["Sale Price"] = .number(salePrice)
        }
        
        if let saleDate = vehicle.saleDate {
            properties["Sale Date"] = .date(saleDate)
        }
        
        return properties
    }

    private func filteredProperties(
        _ properties: [String: NotionValue],
        using database: NotionDatabase?
    ) -> [String: NotionValue] {
        guard let database else { return properties }
        
        return properties.filter { key, _ in
            guard let property = database.properties[key] else { return false }
            return property.type != "formula"
        }
    }
    
    private func leadToNotionProperties(_ lead: LeadExportData) -> [String: NotionValue] {
        var properties: [String: NotionValue] = [
            "Name": .title(lead.name),
            "Stage": .select(lead.leadStage),
            "Lead Score": .number(Decimal(lead.leadScore)),
            "Priority": .select(lead.priority),
            "Days Since Created": .number(Decimal(lead.daysSinceCreated)),
            "Interaction Count": .number(Decimal(lead.interactionCount))
        ]
        
        if let phone = lead.phone {
            properties["Phone"] = .phoneNumber(phone)
        }
        
        if let email = lead.email {
            properties["Email"] = .email(email)
        }
        
        if let source = lead.leadSource {
            properties["Source"] = .select(source)
        }
        
        if let estimatedValue = lead.estimatedValue {
            properties["Estimated Value"] = .number(estimatedValue)
        }
        
        if let daysSinceLastContact = lead.daysSinceLastContact {
            properties["Days Since Last Contact"] = .number(Decimal(daysSinceLastContact))
        }
        
        if let nextFollowUpAt = lead.nextFollowUpAt {
            properties["Next Follow-up"] = .date(nextFollowUpAt)
        }
        
        if let notes = lead.notes {
            properties["Notes"] = .richText(notes)
        }
        
        return properties
    }
    
    private func saleToNotionProperties(_ sale: SaleExportData) -> [String: NotionValue] {
        var properties: [String: NotionValue] = [
            "Vehicle": .title("\(sale.vehicleYear) \(sale.vehicleMake) \(sale.vehicleModel)"),
            "Sale Price": .number(sale.salePrice),
            "Sale Date": .date(sale.saleDate),
            "Total Cost": .number(sale.totalCost),
            "Profit": .number(sale.profit),
            "ROI %": .number(sale.roiPercent),
            "Days to Sell": .number(Decimal(sale.daysToSell))
        ]
        
        if let buyerName = sale.buyerName {
            properties["Buyer Name"] = .richText(buyerName)
        }
        
        return properties
    }
}
