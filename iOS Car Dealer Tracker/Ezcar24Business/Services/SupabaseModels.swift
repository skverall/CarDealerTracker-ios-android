import CoreData
import Foundation

enum DealDeskBusinessRegionCode: String, Codable, CaseIterable, Identifiable {
    case usa = "USA"
    case canada = "Canada"
    case generic = "generic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usa:
            return "USA"
        case .canada:
            return "Canada"
        case .generic:
            return "Other"
        }
    }

    var defaultTemplateCode: DealDeskTemplateCode {
        switch self {
        case .usa:
            return .usa
        case .canada:
            return .canada
        case .generic:
            return .generic
        }
    }

    var isEnabledByDefaultForNewDealer: Bool {
        switch self {
        case .usa, .canada:
            return true
        case .generic:
            return false
        }
    }
}

enum DealDeskTemplateCode: String, Codable, CaseIterable, Identifiable {
    case usa
    case canada
    case generic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usa:
            return "USA"
        case .canada:
            return "Canada"
        case .generic:
            return "Generic"
        }
    }
}

enum DealDeskJurisdictionType: String, Codable, CaseIterable {
    case state
    case province
    case generic
}

enum DealDeskLineCalculationType: String, Codable, CaseIterable {
    case fixedAmount = "fixed_amount"
    case percentOfSalePrice = "percent_of_sale_price"
}

struct DealDeskJurisdictionOption: Identifiable, Equatable {
    let code: String
    let title: String

    var id: String { code }
}

struct DealDeskLine: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var lineCode: String
    var title: String
    var calculationType: DealDeskLineCalculationType
    var value: Decimal

    func resolvedAmount(for salePrice: Decimal) -> Decimal {
        switch calculationType {
        case .fixedAmount:
            return value
        case .percentOfSalePrice:
            return salePrice * value / 100
        }
    }
}

struct DealDeskPaymentPlan: Codable, Equatable {
    var methodCode: String
    var downPayment: Decimal
    var aprPercent: Decimal?
    var termMonths: Int?
}

struct DealDeskTotals: Codable, Equatable {
    var salePrice: Decimal
    var taxTotal: Decimal
    var feeTotal: Decimal
    var outTheDoorTotal: Decimal
    var cashReceivedNow: Decimal
    var amountFinanced: Decimal
    var monthlyPaymentEstimate: Decimal?
}

struct DealDeskSnapshot: Codable, Equatable {
    var version: Int = 1
    var templateCode: String
    var templateVersion: Int
    var jurisdictionType: DealDeskJurisdictionType
    var jurisdictionCode: String
    var taxLines: [DealDeskLine]
    var feeLines: [DealDeskLine]
    var paymentPlan: DealDeskPaymentPlan
    var totals: DealDeskTotals
}

struct DealDeskSettings: Codable, Equatable {
    var isEnabled: Bool
    var businessRegionCode: DealDeskBusinessRegionCode
    var defaultTemplateCode: DealDeskTemplateCode
    var templateVersion: Int
    var taxOverrides: [DealDeskLine]
    var feeOverrides: [DealDeskLine]
}

enum DealDeskTemplateCatalog {
    static func defaultSettings(
        for businessRegionCode: DealDeskBusinessRegionCode,
        isEnabled: Bool? = nil
    ) -> DealDeskSettings {
        DealDeskSettings(
            isEnabled: isEnabled ?? businessRegionCode.isEnabledByDefaultForNewDealer,
            businessRegionCode: businessRegionCode,
            defaultTemplateCode: businessRegionCode.defaultTemplateCode,
            templateVersion: 1,
            taxOverrides: defaultTaxLines(for: businessRegionCode.defaultTemplateCode),
            feeOverrides: defaultFeeLines(for: businessRegionCode.defaultTemplateCode)
        )
    }

    static func defaultTaxLines(for templateCode: DealDeskTemplateCode) -> [DealDeskLine] {
        switch templateCode {
        case .usa:
            return [
                DealDeskLine(lineCode: "sales_tax", title: "Sales tax", calculationType: .percentOfSalePrice, value: 0)
            ]
        case .canada:
            return [
                DealDeskLine(lineCode: "gst", title: "GST", calculationType: .percentOfSalePrice, value: 0),
                DealDeskLine(lineCode: "hst", title: "HST", calculationType: .percentOfSalePrice, value: 0),
                DealDeskLine(lineCode: "pst", title: "PST", calculationType: .percentOfSalePrice, value: 0),
                DealDeskLine(lineCode: "qst", title: "QST", calculationType: .percentOfSalePrice, value: 0)
            ]
        case .generic:
            return [
                DealDeskLine(lineCode: "tax", title: "VAT / Tax", calculationType: .percentOfSalePrice, value: 0)
            ]
        }
    }

    static func defaultFeeLines(for templateCode: DealDeskTemplateCode) -> [DealDeskLine] {
        switch templateCode {
        case .usa:
            return [
                DealDeskLine(lineCode: "doc_fee", title: "Doc fee", calculationType: .fixedAmount, value: 0),
                DealDeskLine(lineCode: "title", title: "Title", calculationType: .fixedAmount, value: 0),
                DealDeskLine(lineCode: "registration", title: "Registration", calculationType: .fixedAmount, value: 0),
                DealDeskLine(lineCode: "license", title: "License", calculationType: .fixedAmount, value: 0)
            ]
        case .canada:
            return [
                DealDeskLine(lineCode: "admin_fee", title: "Admin fee", calculationType: .fixedAmount, value: 0),
                DealDeskLine(lineCode: "licensing", title: "Licensing", calculationType: .fixedAmount, value: 0)
            ]
        case .generic:
            return [
                DealDeskLine(lineCode: "fees", title: "Fees", calculationType: .fixedAmount, value: 0)
            ]
        }
    }

    static func defaultJurisdictionType(for templateCode: DealDeskTemplateCode) -> DealDeskJurisdictionType {
        switch templateCode {
        case .usa:
            return .state
        case .canada:
            return .province
        case .generic:
            return .generic
        }
    }

    static func defaultJurisdictionCode(for templateCode: DealDeskTemplateCode) -> String {
        switch templateCode {
        case .usa:
            return "US-XX"
        case .canada:
            return "CA-XX"
        case .generic:
            return "GENERIC"
        }
    }

    static func jurisdictionOptions(for templateCode: DealDeskTemplateCode) -> [DealDeskJurisdictionOption] {
        switch templateCode {
        case .usa:
            return usJurisdictions
        case .canada:
            return canadaJurisdictions
        case .generic:
            return [DealDeskJurisdictionOption(code: "GENERIC", title: "Generic")]
        }
    }

    static func mergedTaxLines(from settings: DealDeskSettings) -> [DealDeskLine] {
        mergedLines(
            defaults: defaultTaxLines(for: settings.defaultTemplateCode),
            overrides: settings.taxOverrides
        )
    }

    static func mergedFeeLines(from settings: DealDeskSettings) -> [DealDeskLine] {
        mergedLines(
            defaults: defaultFeeLines(for: settings.defaultTemplateCode),
            overrides: settings.feeOverrides
        )
    }

    static func setupGuidanceMessage(
        for templateCode: DealDeskTemplateCode,
        taxLines: [DealDeskLine],
        feeLines: [DealDeskLine]
    ) -> String? {
        let missingTaxes = !taxLines.isEmpty && taxLines.allSatisfy { $0.value == 0 }
        let missingFees = !feeLines.isEmpty && feeLines.allSatisfy { $0.value == 0 }

        guard missingTaxes || missingFees else { return nil }

        switch templateCode {
        case .usa, .canada:
            let regionName = templateCode.displayName
            if missingTaxes && missingFees {
                return "\(regionName) template lines are placeholders until you enter your local taxes and fees."
            }
            if missingTaxes {
                return "\(regionName) tax lines are placeholders until you enter your local rates."
            }
            return "\(regionName) fee lines are placeholders until you enter your local amounts."
        case .generic:
            if missingTaxes && missingFees {
                return "Generic template starts empty. Add only the taxes and fees you actually collect."
            }
            if missingTaxes {
                return "Generic tax line is optional. Enter it only if you collect tax."
            }
            return "Generic fee line is optional. Enter it only if you collect fees."
        }
    }

    private static func mergedLines(defaults: [DealDeskLine], overrides: [DealDeskLine]) -> [DealDeskLine] {
        guard !overrides.isEmpty else { return defaults }
        let overrideMap = Dictionary(uniqueKeysWithValues: overrides.map { ($0.lineCode, $0) })
        let mergedDefaults = defaults.map { overrideMap[$0.lineCode] ?? $0 }
        let extraOverrides = overrides.filter { override in
            defaults.contains(where: { $0.lineCode == override.lineCode }) == false
        }
        return mergedDefaults + extraOverrides
    }

    private static let usJurisdictions: [DealDeskJurisdictionOption] = [
        DealDeskJurisdictionOption(code: "US-XX", title: "Unspecified"),
        DealDeskJurisdictionOption(code: "US-AL", title: "Alabama"),
        DealDeskJurisdictionOption(code: "US-AK", title: "Alaska"),
        DealDeskJurisdictionOption(code: "US-AZ", title: "Arizona"),
        DealDeskJurisdictionOption(code: "US-AR", title: "Arkansas"),
        DealDeskJurisdictionOption(code: "US-CA", title: "California"),
        DealDeskJurisdictionOption(code: "US-CO", title: "Colorado"),
        DealDeskJurisdictionOption(code: "US-CT", title: "Connecticut"),
        DealDeskJurisdictionOption(code: "US-DE", title: "Delaware"),
        DealDeskJurisdictionOption(code: "US-FL", title: "Florida"),
        DealDeskJurisdictionOption(code: "US-GA", title: "Georgia"),
        DealDeskJurisdictionOption(code: "US-HI", title: "Hawaii"),
        DealDeskJurisdictionOption(code: "US-ID", title: "Idaho"),
        DealDeskJurisdictionOption(code: "US-IL", title: "Illinois"),
        DealDeskJurisdictionOption(code: "US-IN", title: "Indiana"),
        DealDeskJurisdictionOption(code: "US-IA", title: "Iowa"),
        DealDeskJurisdictionOption(code: "US-KS", title: "Kansas"),
        DealDeskJurisdictionOption(code: "US-KY", title: "Kentucky"),
        DealDeskJurisdictionOption(code: "US-LA", title: "Louisiana"),
        DealDeskJurisdictionOption(code: "US-ME", title: "Maine"),
        DealDeskJurisdictionOption(code: "US-MD", title: "Maryland"),
        DealDeskJurisdictionOption(code: "US-MA", title: "Massachusetts"),
        DealDeskJurisdictionOption(code: "US-MI", title: "Michigan"),
        DealDeskJurisdictionOption(code: "US-MN", title: "Minnesota"),
        DealDeskJurisdictionOption(code: "US-MS", title: "Mississippi"),
        DealDeskJurisdictionOption(code: "US-MO", title: "Missouri"),
        DealDeskJurisdictionOption(code: "US-MT", title: "Montana"),
        DealDeskJurisdictionOption(code: "US-NE", title: "Nebraska"),
        DealDeskJurisdictionOption(code: "US-NV", title: "Nevada"),
        DealDeskJurisdictionOption(code: "US-NH", title: "New Hampshire"),
        DealDeskJurisdictionOption(code: "US-NJ", title: "New Jersey"),
        DealDeskJurisdictionOption(code: "US-NM", title: "New Mexico"),
        DealDeskJurisdictionOption(code: "US-NY", title: "New York"),
        DealDeskJurisdictionOption(code: "US-NC", title: "North Carolina"),
        DealDeskJurisdictionOption(code: "US-ND", title: "North Dakota"),
        DealDeskJurisdictionOption(code: "US-OH", title: "Ohio"),
        DealDeskJurisdictionOption(code: "US-OK", title: "Oklahoma"),
        DealDeskJurisdictionOption(code: "US-OR", title: "Oregon"),
        DealDeskJurisdictionOption(code: "US-PA", title: "Pennsylvania"),
        DealDeskJurisdictionOption(code: "US-RI", title: "Rhode Island"),
        DealDeskJurisdictionOption(code: "US-SC", title: "South Carolina"),
        DealDeskJurisdictionOption(code: "US-SD", title: "South Dakota"),
        DealDeskJurisdictionOption(code: "US-TN", title: "Tennessee"),
        DealDeskJurisdictionOption(code: "US-TX", title: "Texas"),
        DealDeskJurisdictionOption(code: "US-UT", title: "Utah"),
        DealDeskJurisdictionOption(code: "US-VT", title: "Vermont"),
        DealDeskJurisdictionOption(code: "US-VA", title: "Virginia"),
        DealDeskJurisdictionOption(code: "US-WA", title: "Washington"),
        DealDeskJurisdictionOption(code: "US-WV", title: "West Virginia"),
        DealDeskJurisdictionOption(code: "US-WI", title: "Wisconsin"),
        DealDeskJurisdictionOption(code: "US-WY", title: "Wyoming"),
        DealDeskJurisdictionOption(code: "US-DC", title: "District of Columbia")
    ]

    private static let canadaJurisdictions: [DealDeskJurisdictionOption] = [
        DealDeskJurisdictionOption(code: "CA-XX", title: "Unspecified"),
        DealDeskJurisdictionOption(code: "CA-AB", title: "Alberta"),
        DealDeskJurisdictionOption(code: "CA-BC", title: "British Columbia"),
        DealDeskJurisdictionOption(code: "CA-MB", title: "Manitoba"),
        DealDeskJurisdictionOption(code: "CA-NB", title: "New Brunswick"),
        DealDeskJurisdictionOption(code: "CA-NL", title: "Newfoundland and Labrador"),
        DealDeskJurisdictionOption(code: "CA-NS", title: "Nova Scotia"),
        DealDeskJurisdictionOption(code: "CA-NT", title: "Northwest Territories"),
        DealDeskJurisdictionOption(code: "CA-NU", title: "Nunavut"),
        DealDeskJurisdictionOption(code: "CA-ON", title: "Ontario"),
        DealDeskJurisdictionOption(code: "CA-PE", title: "Prince Edward Island"),
        DealDeskJurisdictionOption(code: "CA-QC", title: "Quebec"),
        DealDeskJurisdictionOption(code: "CA-SK", title: "Saskatchewan"),
        DealDeskJurisdictionOption(code: "CA-YT", title: "Yukon")
    ]
}

extension DealDeskSettings {
    var seededTaxLines: [DealDeskLine] {
        DealDeskTemplateCatalog.mergedTaxLines(from: self)
    }

    var seededFeeLines: [DealDeskLine] {
        DealDeskTemplateCatalog.mergedFeeLines(from: self)
    }
}

extension DealDeskSnapshot {
    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()

    var jsonString: String? {
        guard let data = try? Self.jsonEncoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from jsonString: String?) -> DealDeskSnapshot? {
        guard
            let jsonString,
            let data = jsonString.data(using: .utf8)
        else { return nil }
        return try? Self.jsonDecoder.decode(DealDeskSnapshot.self, from: data)
    }
}

extension Sale {
    var dealDeskSnapshotValue: DealDeskSnapshot? {
        DealDeskSnapshot.decode(from: dealDeskPayload)
    }

    var accountDepositAmount: Decimal {
        cashReceivedNow?.decimalValue ?? amount?.decimalValue ?? 0
    }

    var dealerRevenueAmount: Decimal {
        amount?.decimalValue ?? 0
    }

    var isDealDeskSale: Bool {
        dealDeskSnapshotValue != nil || !(dealDeskTemplateCode?.isEmpty ?? true)
    }

    func applyDealDeskSnapshot(_ snapshot: DealDeskSnapshot?) {
        dealDeskPayload = snapshot?.jsonString
        dealDeskTemplateCode = snapshot?.templateCode
        dealDeskTemplateVersion = Int32(snapshot?.templateVersion ?? 0)
        jurisdictionType = snapshot?.jurisdictionType.rawValue
        jurisdictionCode = snapshot?.jurisdictionCode
        outTheDoorTotal = snapshot.map { NSDecimalNumber(decimal: $0.totals.outTheDoorTotal) }
        cashReceivedNow = snapshot.map { NSDecimalNumber(decimal: $0.totals.cashReceivedNow) }
        amountFinanced = snapshot.map { NSDecimalNumber(decimal: $0.totals.amountFinanced) }
        monthlyPaymentEstimate = snapshot?.totals.monthlyPaymentEstimate.map { NSDecimalNumber(decimal: $0) }
    }

    func clearDealDeskSnapshot() {
        dealDeskPayload = nil
        dealDeskTemplateCode = nil
        dealDeskTemplateVersion = 0
        jurisdictionType = nil
        jurisdictionCode = nil
        outTheDoorTotal = nil
        cashReceivedNow = nil
        amountFinanced = nil
        monthlyPaymentEstimate = nil
    }
}

struct RemoteDealerUser: Codable {
    let id: UUID
    let dealerId: UUID
    let name: String
    let firstName: String?
    let lastName: String?
    let email: String?
    let phone: String?
    let avatarURL: String?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case name
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case phone
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteFinancialAccount: Codable {
    let id: UUID
    let dealerId: UUID
    let accountType: String
    let balance: Decimal
    let openingBalance: Decimal?
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case accountType = "account_type"
        case balance
        case openingBalance = "opening_balance"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteVehicle: Codable {
    let id: UUID
    let dealerId: UUID
    let vin: String
    let inventoryID: String?
    let make: String?
    let model: String?
    let year: Int?
    let purchasePrice: Decimal?
    let purchaseAccountId: UUID?
    let purchaseDate: String
    let status: String
    let notes: String?
    let createdAt: Date
    let salePrice: Decimal?
    let saleDate: String?
    let photoURL: String?
    let askingPrice: Decimal?

    let reportURL: String?
    let mileage: Int?
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case vin
        case inventoryID = "inventory_id"
        case make
        case model
        case year
        case purchasePrice = "purchase_price"
        case purchaseAccountId = "purchase_account_id"
        case purchaseDate = "purchase_date"
        case status
        case notes
        case createdAt = "created_at"
        case salePrice = "sale_price"
        case saleDate = "sale_date"
        case photoURL = "photo_url"
        case askingPrice = "asking_price"
        case reportURL = "report_url"
        case mileage
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteVehiclePhoto: Codable {
    let id: UUID
    let dealerId: UUID
    let vehicleId: UUID
    let storagePath: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case vehicleId = "vehicle_id"
        case storagePath = "storage_path"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteExpenseTemplate: Codable {
    let id: UUID
    let dealerId: UUID
    let name: String
    let category: String
    let defaultDescription: String?
    let defaultAmount: Decimal?
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case name
        case category
        case defaultDescription = "default_description"
        case defaultAmount = "default_amount"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteExpense: Codable {
    let id: UUID
    let dealerId: UUID
    let amount: Decimal
    let date: String
    let expenseDescription: String?
    let category: String
    let receiptPath: String?
    let createdAt: Date
    let vehicleId: UUID?
    let userId: UUID?
    let accountId: UUID?
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case amount
        case date
        case expenseDescription = "description"
        case category
        case receiptPath = "receipt_path"
        case createdAt = "created_at"
        case vehicleId = "vehicle_id"
        case userId = "user_id"
        case accountId = "account_id"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteSale: Codable {
    let id: UUID
    let dealerId: UUID
    let vehicleId: UUID
    let amount: Decimal
    let salePrice: Decimal?
    let profit: Decimal?
    let date: String
    let buyerName: String?
    let buyerPhone: String?
    let paymentMethod: String?
    let accountId: UUID?
    let vatRefundPercent: Decimal?
    let vatRefundAmount: Decimal?
    let notes: String?
    let dealDeskPayload: DealDeskSnapshot?
    let dealDeskTemplateCode: String?
    let dealDeskTemplateVersion: Int?
    let jurisdictionType: String?
    let jurisdictionCode: String?
    let outTheDoorTotal: Decimal?
    let cashReceivedNow: Decimal?
    let amountFinanced: Decimal?
    let monthlyPaymentEstimate: Decimal?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case vehicleId = "vehicle_id"
        case amount
        case salePrice = "sale_price"
        case profit
        case date
        case buyerName = "buyer_name"
        case buyerPhone = "buyer_phone"
        case paymentMethod = "payment_method"
        case accountId = "account_id"
        case vatRefundPercent = "vat_refund_percent"
        case vatRefundAmount = "vat_refund_amount"
        case notes
        case dealDeskPayload = "deal_desk_payload"
        case dealDeskTemplateCode = "deal_desk_template_code"
        case dealDeskTemplateVersion = "deal_desk_template_version"
        case jurisdictionType = "jurisdiction_type"
        case jurisdictionCode = "jurisdiction_code"
        case outTheDoorTotal = "out_the_door_total"
        case cashReceivedNow = "cash_received_now"
        case amountFinanced = "amount_financed"
        case monthlyPaymentEstimate = "monthly_payment_estimate"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteDebt: Codable {
    let id: UUID
    let dealerId: UUID
    let counterpartyName: String
    let counterpartyPhone: String?
    let direction: String
    let amount: Decimal
    let notes: String?
    let dueDate: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case counterpartyName = "counterparty_name"
        case counterpartyPhone = "counterparty_phone"
        case direction
        case amount
        case notes
        case dueDate = "due_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteDebtPayment: Codable {
    let id: UUID
    let dealerId: UUID
    let debtId: UUID
    let amount: Decimal
    let date: String
    let note: String?
    let paymentMethod: String?
    let accountId: UUID?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case debtId = "debt_id"
        case amount
        case date
        case note
        case paymentMethod = "payment_method"
        case accountId = "account_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteAccountTransaction: Codable {
    let id: UUID
    let dealerId: UUID
    let accountId: UUID
    let transactionType: String
    let amount: Decimal
    let date: String
    let note: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case accountId = "account_id"
        case transactionType = "transaction_type"
        case amount
        case date
        case note
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteClient: Codable {
    let id: UUID
    let dealerId: UUID
    let name: String
    let phone: String?
    let email: String?
    let notes: String?
    let requestDetails: String?
    let preferredDate: Date?
    let createdAt: Date
    let status: String
    let vehicleId: UUID?
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case name
        case phone
        case email
        case notes
        case requestDetails = "request_details"
        case preferredDate = "preferred_date"
        case createdAt = "created_at"
        case status
        case vehicleId = "vehicle_id"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteClientInteraction: Codable {
    let id: UUID
    let dealerId: UUID
    let clientId: UUID
    let title: String?
    let detail: String?
    let occurredAt: Date
    let stage: String
    let value: Decimal?
    let interactionType: String?
    let outcome: String?
    let durationMinutes: Int
    let isFollowUpRequired: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case clientId = "client_id"
        case title
        case detail
        case occurredAt = "occurred_at"
        case stage
        case value
        case interactionType = "interaction_type"
        case outcome
        case durationMinutes = "duration_minutes"
        case isFollowUpRequired = "is_follow_up_required"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteClientReminder: Codable {
    let id: UUID
    let dealerId: UUID
    let clientId: UUID
    let title: String
    let notes: String?
    let dueDate: Date
    let isCompleted: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case clientId = "client_id"
        case title
        case notes
        case dueDate = "due_date"
        case isCompleted = "is_completed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemotePart: Codable {
    let id: UUID
    let dealerId: UUID
    let name: String
    let code: String?
    let category: String?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case name
        case code
        case category
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemotePartBatch: Codable {
    let id: UUID
    let dealerId: UUID
    let partId: UUID
    let batchLabel: String?
    let quantityReceived: Decimal
    let quantityRemaining: Decimal
    let unitCost: Decimal
    let purchaseDate: String
    let purchaseAccountId: UUID?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case partId = "part_id"
        case batchLabel = "batch_label"
        case quantityReceived = "quantity_received"
        case quantityRemaining = "quantity_remaining"
        case unitCost = "unit_cost"
        case purchaseDate = "purchase_date"
        case purchaseAccountId = "purchase_account_id"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemotePartSale: Codable {
    let id: UUID
    let dealerId: UUID
    let amount: Decimal
    let date: String
    let buyerName: String?
    let buyerPhone: String?
    let paymentMethod: String?
    let accountId: UUID?
    let clientId: UUID?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case amount
        case date
        case buyerName = "buyer_name"
        case buyerPhone = "buyer_phone"
        case paymentMethod = "payment_method"
        case accountId = "account_id"
        case clientId = "client_id"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemotePartSaleLineItem: Codable {
    let id: UUID
    let dealerId: UUID
    let saleId: UUID
    let partId: UUID
    let batchId: UUID
    let quantity: Decimal
    let unitPrice: Decimal
    let unitCost: Decimal
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case saleId = "sale_id"
        case partId = "part_id"
        case batchId = "batch_id"
        case quantity
        case unitPrice = "unit_price"
        case unitCost = "unit_cost"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteSnapshot: Decodable {
    let users: [RemoteDealerUser]
    let accounts: [RemoteFinancialAccount]
    let accountTransactions: [RemoteAccountTransaction]
    let vehicles: [RemoteVehicle]
    let templates: [RemoteExpenseTemplate]
    let expenses: [RemoteExpense]
    let sales: [RemoteSale]
    let debts: [RemoteDebt]
    let debtPayments: [RemoteDebtPayment]
    let clients: [RemoteClient]
    let clientInteractions: [RemoteClientInteraction]
    let clientReminders: [RemoteClientReminder]
    let parts: [RemotePart]
    let partBatches: [RemotePartBatch]
    let partSales: [RemotePartSale]
    let partSaleLineItems: [RemotePartSaleLineItem]
    let serverNow: Date?

    enum CodingKeys: String, CodingKey {
        case users
        case accounts
        case accountTransactions = "account_transactions"
        case vehicles
        case templates
        case expenses
        case sales
        case debts
        case debtPayments = "debt_payments"
        case clients
        case clientInteractions = "client_interactions"
        case clientReminders = "client_reminders"
        case parts
        case partBatches = "part_batches"
        case partSales = "part_sales"
        case partSaleLineItems = "part_sale_line_items"
        case serverNow = "server_now"
    }

    init(
        users: [RemoteDealerUser],
        accounts: [RemoteFinancialAccount],
        accountTransactions: [RemoteAccountTransaction],
        vehicles: [RemoteVehicle],
        templates: [RemoteExpenseTemplate],
        expenses: [RemoteExpense],
        sales: [RemoteSale],
        debts: [RemoteDebt],
        debtPayments: [RemoteDebtPayment],
        clients: [RemoteClient],
        clientInteractions: [RemoteClientInteraction],
        clientReminders: [RemoteClientReminder],
        parts: [RemotePart],
        partBatches: [RemotePartBatch],
        partSales: [RemotePartSale],
        partSaleLineItems: [RemotePartSaleLineItem],
        serverNow: Date? = nil
    ) {
        self.users = users
        self.accounts = accounts
        self.accountTransactions = accountTransactions
        self.vehicles = vehicles
        self.templates = templates
        self.expenses = expenses
        self.sales = sales
        self.debts = debts
        self.debtPayments = debtPayments
        self.clients = clients
        self.clientInteractions = clientInteractions
        self.clientReminders = clientReminders
        self.parts = parts
        self.partBatches = partBatches
        self.partSales = partSales
        self.partSaleLineItems = partSaleLineItems
        self.serverNow = serverNow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        users = try container.decodeIfPresent([RemoteDealerUser].self, forKey: .users) ?? []
        accounts = try container.decodeIfPresent([RemoteFinancialAccount].self, forKey: .accounts) ?? []
        accountTransactions = try container.decodeIfPresent([RemoteAccountTransaction].self, forKey: .accountTransactions) ?? []
        vehicles = try container.decodeIfPresent([RemoteVehicle].self, forKey: .vehicles) ?? []
        templates = try container.decodeIfPresent([RemoteExpenseTemplate].self, forKey: .templates) ?? []
        expenses = try container.decodeIfPresent([RemoteExpense].self, forKey: .expenses) ?? []
        sales = try container.decodeIfPresent([RemoteSale].self, forKey: .sales) ?? []
        debts = try container.decodeIfPresent([RemoteDebt].self, forKey: .debts) ?? []
        debtPayments = try container.decodeIfPresent([RemoteDebtPayment].self, forKey: .debtPayments) ?? []
        clients = try container.decodeIfPresent([RemoteClient].self, forKey: .clients) ?? []
        clientInteractions = try container.decodeIfPresent([RemoteClientInteraction].self, forKey: .clientInteractions) ?? []
        clientReminders = try container.decodeIfPresent([RemoteClientReminder].self, forKey: .clientReminders) ?? []
        parts = try container.decodeIfPresent([RemotePart].self, forKey: .parts) ?? []
        partBatches = try container.decodeIfPresent([RemotePartBatch].self, forKey: .partBatches) ?? []
        partSales = try container.decodeIfPresent([RemotePartSale].self, forKey: .partSales) ?? []
        partSaleLineItems = try container.decodeIfPresent([RemotePartSaleLineItem].self, forKey: .partSaleLineItems) ?? []
        serverNow = try container.decodeIfPresent(Date.self, forKey: .serverNow)
    }
}

// Core Data extensions removed as they are auto-generated.
