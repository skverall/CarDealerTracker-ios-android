import Foundation

@MainActor
class NotionAPIService {
    static let shared = NotionAPIService()
    
    private let baseURL = NotionConfig.apiBaseURL
    private let notionVersion = NotionConfig.notionVersion
    private let rateLimiter = NotionRateLimiter()
    
    private var token: String? {
        NotionAuthManager.shared.accessToken
    }
    
    private var headers: [String: String] {
        [
            "Authorization": "Bearer \(token ?? "")",
            "Notion-Version": notionVersion,
            "Content-Type": "application/json"
        ]
    }
    
    // MARK: - Database Operations
    
    func listDatabases() async throws -> [NotionDatabase] {
        try await rateLimiter.waitForPermission()
        
        guard token != nil else {
            throw NotionError.notAuthenticated
        }
        
        let url = URL(string: "\(baseURL)/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        
        let body: [String: Any] = [
            "filter": ["value": "database", "property": "object"],
            "page_size": 100
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw NotionError.rateLimited
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NotionError.invalidResponse
        }
        
        let searchResponse = try JSONDecoder().decode(NotionSearchResponse.self, from: data)
        return searchResponse.results
    }
    
    func createDatabase(name: String, properties: [String: NotionPropertyDefinition], parentPageId: String) async throws -> NotionDatabase {
        try await rateLimiter.waitForPermission()
        
        guard token != nil else {
            throw NotionError.notAuthenticated
        }
        
        let url = URL(string: "\(baseURL)/databases")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        
        // titleContent initialization removed as it was unused

        let propertyDict = properties.reduce(into: [String: Any]()) { result, pair in
            result[pair.key] = encodePropertyDefinition(pair.value)
        }
        
        let body: [String: Any] = [
            "parent": ["page_id": parentPageId],
            "title": [["text": ["content": name]]],
            "properties": propertyDict
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw NotionError.rateLimited
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NotionError.exportFailed
        }
        
        return try JSONDecoder().decode(NotionDatabase.self, from: data)
    }
    
    // MARK: - Page/Entry Operations
    
    func createPage(databaseId: String, properties: [String: NotionValue]) async throws -> NotionPage {
        try await rateLimiter.waitForPermission()
        
        guard token != nil else {
            throw NotionError.notAuthenticated
        }
        
        let url = URL(string: "\(baseURL)/pages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        
        let notionProperties = properties.reduce(into: [String: Any]()) { result, pair in
            result[pair.key] = pair.value.notionProperty
        }
        
        let body: [String: Any] = [
            "parent": ["database_id": databaseId],
            "properties": notionProperties
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw NotionError.rateLimited
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NotionError.exportFailed
        }
        
        return try JSONDecoder().decode(NotionPage.self, from: data)
    }
    
    func createPages(databaseId: String, pages: [[String: NotionValue]]) async throws -> [NotionPage] {
        var createdPages: [NotionPage] = []
        
        for pageProperties in pages {
            do {
                let page = try await createPage(databaseId: databaseId, properties: pageProperties)
                createdPages.append(page)
            } catch {
                throw error
            }
        }
        
        return createdPages
    }
    
    // MARK: - Export Operations
    
    func exportVehiclesToNotion(databaseId: String, vehicles: [VehicleExportData]) async throws -> ExportResult {
        var successCount = 0
        var failedVehicles: [String] = []
        
        for vehicle in vehicles {
            do {
                let properties = vehicleToNotionProperties(vehicle)
                _ = try await createPage(databaseId: databaseId, properties: properties)
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
    
    func exportLeadsToNotion(databaseId: String, leads: [LeadExportData]) async throws -> ExportResult {
        var successCount = 0
        var failedLeads: [String] = []
        
        for lead in leads {
            do {
                let properties = leadToNotionProperties(lead)
                _ = try await createPage(databaseId: databaseId, properties: properties)
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
    
    func exportSalesToNotion(databaseId: String, sales: [SaleExportData]) async throws -> ExportResult {
        var successCount = 0
        var failedSales: [String] = []
        
        for sale in sales {
            do {
                let properties = saleToNotionProperties(sale)
                _ = try await createPage(databaseId: databaseId, properties: properties)
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
    
    // MARK: - Property Mapping
    
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
    
    private func encodePropertyDefinition(_ definition: NotionPropertyDefinition) -> [String: Any] {
        var result: [String: Any] = [:]
        
        switch definition.type {
        case "title":
            result["title"] = [:]
        case "rich_text":
            result["rich_text"] = [:]
        case "number":
            if let format = definition.number?.format {
                result["number"] = ["format": format]
            } else {
                result["number"] = [:]
            }
        case "select":
            if let options = definition.select?.options {
                result["select"] = ["options": options.map { ["name": $0.name, "color": $0.color ?? "default"] }]
            } else {
                result["select"] = [:]
            }
        case "date":
            result["date"] = [:]
        case "formula":
            if let expression = definition.formula?.expression {
                result["formula"] = ["expression": expression]
            }
        case "checkbox":
            result["checkbox"] = [:]
        case "email":
            result["email"] = [:]
        case "phone_number":
            result["phone_number"] = [:]
        case "url":
            result["url"] = [:]
        default:
            break
        }
        
        return result
    }
}

// MARK: - Rate Limiter

actor NotionRateLimiter {
    private var lastRequestTime: Date = .distantPast
    private let minimumInterval: TimeInterval = 0.35
    
    func waitForPermission() async throws {
        let now = Date()
        let timeSinceLastRequest = now.timeIntervalSince(lastRequestTime)
        
        if timeSinceLastRequest < minimumInterval {
            let waitTime = minimumInterval - timeSinceLastRequest
            try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }
        
        lastRequestTime = Date()
    }
}
