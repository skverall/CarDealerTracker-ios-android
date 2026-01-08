import Foundation

struct RemoteDealerUser: Codable {
    let id: UUID
    let dealerId: UUID
    let name: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case name
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
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case accountType = "account_type"
        case balance
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteVehicle: Codable {
    let id: UUID
    let dealerId: UUID
    let vin: String
    let make: String?
    let model: String?
    let year: Int?
    let purchasePrice: Decimal
    let purchaseDate: String
    let status: String
    let notes: String?
    let createdAt: Date
    let salePrice: Decimal?
    let saleDate: String?
    let photoURL: String?
    let askingPrice: Decimal?
    let reportURL: String?
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dealerId = "dealer_id"
        case vin
        case make
        case model
        case year
        case purchasePrice = "purchase_price"
        case purchaseDate = "purchase_date"
        case status
        case notes
        case createdAt = "created_at"
        case salePrice = "sale_price"
        case saleDate = "sale_date"
        case photoURL = "photo_url"
        case askingPrice = "asking_price"
        case reportURL = "report_url"
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
    let notes: String?
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
        case notes
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
    }
}

// Core Data extensions removed as they are auto-generated.
