package com.ezcar24.business.data.local

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.math.BigDecimal
import java.util.Date
import java.util.UUID

enum class ExpenseCategoryType {
    HOLDING_COST,
    IMPROVEMENT,
    OPERATIONAL
}

enum class LeadStage {
    new,
    contacted,
    qualified,
    negotiation,
    offer,
    test_drive,
    closed_won,
    closed_lost
}

enum class LeadSource {
    facebook,
    dubizzle,
    instagram,
    referral,
    walk_in,
    phone,
    website,
    other
}

enum class InventoryAlertType {
    aging_60_days,
    aging_90_days,
    low_roi,
    high_holding_cost,
    price_reduction_needed
}

@Entity(tableName = "users")
data class User(
    @PrimaryKey val id: UUID,
    val name: String,
    val createdAt: Date,
    val updatedAt: Date,
    val deletedAt: Date? = null
)

@Entity(tableName = "vehicles")
data class Vehicle(
    @PrimaryKey val id: UUID,
    val vin: String,
    val make: String?,
    val model: String?,
    val year: Int?,
    val mileage: Int = 0,
    val purchasePrice: BigDecimal,
    val purchaseDate: Date,
    val status: String = "owned",
    val notes: String?,
    val createdAt: Date,
    val updatedAt: Date?,
    val deletedAt: Date? = null,
    val saleDate: Date?,
    val buyerName: String?,
    val buyerPhone: String?,
    val paymentMethod: String?,
    val salePrice: BigDecimal?,
    val askingPrice: BigDecimal?,
    val reportURL: String?,
    val photoUrl: String? = null
)

@Entity(
    tableName = "financial_accounts", 
    indices = [Index("deletedAt")]
)
data class FinancialAccount(
    @PrimaryKey val id: UUID,
    val accountType: String,
    val balance: BigDecimal = BigDecimal.ZERO,
    val updatedAt: Date,
    val deletedAt: Date? = null
)

@Entity(
    tableName = "expenses",
    foreignKeys = [
        ForeignKey(entity = Vehicle::class, parentColumns = ["id"], childColumns = ["vehicleId"], onDelete = ForeignKey.CASCADE),
        ForeignKey(entity = User::class, parentColumns = ["id"], childColumns = ["userId"], onDelete = ForeignKey.SET_NULL),
        ForeignKey(entity = FinancialAccount::class, parentColumns = ["id"], childColumns = ["accountId"], onDelete = ForeignKey.SET_NULL)
    ],
    indices = [Index("vehicleId"), Index("userId"), Index("accountId")]
)
data class Expense(
    @PrimaryKey val id: UUID,
    val amount: BigDecimal = BigDecimal.ZERO,
    val date: Date,
    val expenseDescription: String?,
    val category: String,
    val createdAt: Date,
    val updatedAt: Date?,
    val deletedAt: Date? = null,
    val vehicleId: UUID?,
    val userId: UUID?,
    val accountId: UUID?,
    val receiptPath: String? = null,
    val expenseType: ExpenseCategoryType = ExpenseCategoryType.HOLDING_COST
)

@Entity(
    tableName = "sales",
    foreignKeys = [
        ForeignKey(entity = Vehicle::class, parentColumns = ["id"], childColumns = ["vehicleId"], onDelete = ForeignKey.SET_NULL),
        ForeignKey(entity = FinancialAccount::class, parentColumns = ["id"], childColumns = ["accountId"], onDelete = ForeignKey.SET_NULL)
    ],
    indices = [Index("vehicleId"), Index("accountId")]
)
data class Sale(
    @PrimaryKey val id: UUID,
    val amount: BigDecimal?,
    val date: Date?,
    val buyerName: String?,
    val buyerPhone: String?,
    val paymentMethod: String?,
    val createdAt: Date?,
    val updatedAt: Date?,
    val deletedAt: Date? = null,
    val vehicleId: UUID?,
    val accountId: UUID?
)

@Entity(
    tableName = "clients",
    foreignKeys = [
        ForeignKey(entity = Vehicle::class, parentColumns = ["id"], childColumns = ["vehicleId"], onDelete = ForeignKey.SET_NULL)
    ],
    indices = [Index("vehicleId"), Index("leadStage"), Index("assignedUserId")]
)
data class Client(
    @PrimaryKey val id: UUID,
    val name: String,
    val phone: String?,
    val email: String?,
    val notes: String?,
    val requestDetails: String?,
    val preferredDate: Date?,
    val status: String? = "new",
    val createdAt: Date,
    val updatedAt: Date?,
    val deletedAt: Date? = null,
    val vehicleId: UUID?,
    val leadStage: LeadStage = LeadStage.new,
    val leadSource: LeadSource? = null,
    val assignedUserId: UUID? = null,
    val estimatedValue: BigDecimal? = null,
    val priority: Int = 0,
    val leadCreatedAt: Date? = null,
    val lastContactAt: Date? = null,
    val nextFollowUpAt: Date? = null
)

@Entity(
    tableName = "client_interactions",
    foreignKeys = [
        ForeignKey(entity = Client::class, parentColumns = ["id"], childColumns = ["clientId"], onDelete = ForeignKey.CASCADE)
    ],
    indices = [Index("clientId")]
)
data class ClientInteraction(
    @PrimaryKey val id: UUID,
    val title: String?,
    val detail: String?,
    val occurredAt: Date,
    val stage: String? = "update",
    val value: BigDecimal?,
    val clientId: UUID?,
    val interactionType: String? = null,
    val outcome: String? = null,
    val durationMinutes: Int? = null,
    val isFollowUpRequired: Boolean = false,
    val createdAt: Date = Date(),
    val updatedAt: Date? = null,
    val deletedAt: Date? = null
)

@Entity(
    tableName = "client_reminders",
    foreignKeys = [
        ForeignKey(entity = Client::class, parentColumns = ["id"], childColumns = ["clientId"], onDelete = ForeignKey.CASCADE)
    ],
    indices = [Index("clientId")]
)
data class ClientReminder(
    @PrimaryKey val id: UUID,
    val title: String,
    val notes: String?,
    val dueDate: Date,
    val isCompleted: Boolean = false,
    val createdAt: Date,
    val clientId: UUID?
)

@Entity(
    tableName = "expense_templates",
    foreignKeys = [
        ForeignKey(entity = Vehicle::class, parentColumns = ["id"], childColumns = ["vehicleId"], onDelete = ForeignKey.SET_NULL),
        ForeignKey(entity = User::class, parentColumns = ["id"], childColumns = ["userId"], onDelete = ForeignKey.SET_NULL),
        ForeignKey(entity = FinancialAccount::class, parentColumns = ["id"], childColumns = ["accountId"], onDelete = ForeignKey.SET_NULL)
    ],
    indices = [Index("vehicleId"), Index("userId"), Index("accountId")]
)
data class ExpenseTemplate(
    @PrimaryKey val id: UUID,
    val name: String,
    val category: String?,
    val defaultDescription: String?,
    val defaultAmount: BigDecimal?,
    val updatedAt: Date?,
    val deletedAt: Date? = null,
    val vehicleId: UUID?,
    val userId: UUID?,
    val accountId: UUID?
)

@Entity(tableName = "parts")
data class Part(
    @PrimaryKey val id: UUID,
    val name: String,
    val code: String?,
    val category: String?,
    val notes: String?,
    val createdAt: Date,
    val updatedAt: Date?,
    val deletedAt: Date? = null
)

@Entity(
    tableName = "part_batches",
    foreignKeys = [
        ForeignKey(entity = Part::class, parentColumns = ["id"], childColumns = ["partId"], onDelete = ForeignKey.CASCADE),
        ForeignKey(entity = FinancialAccount::class, parentColumns = ["id"], childColumns = ["purchaseAccountId"], onDelete = ForeignKey.SET_NULL)
    ],
    indices = [Index("partId"), Index("purchaseAccountId")]
)
data class PartBatch(
    @PrimaryKey val id: UUID,
    val partId: UUID,
    val batchLabel: String?,
    val quantityReceived: BigDecimal = BigDecimal.ZERO,
    val quantityRemaining: BigDecimal = BigDecimal.ZERO,
    val unitCost: BigDecimal = BigDecimal.ZERO,
    val purchaseDate: Date,
    val purchaseAccountId: UUID?,
    val notes: String?,
    val createdAt: Date,
    val updatedAt: Date?,
    val deletedAt: Date? = null
)

@Entity(
    tableName = "part_sales",
    foreignKeys = [
        ForeignKey(entity = FinancialAccount::class, parentColumns = ["id"], childColumns = ["accountId"], onDelete = ForeignKey.SET_NULL)
    ],
    indices = [Index("accountId")]
)
data class PartSale(
    @PrimaryKey val id: UUID,
    val amount: BigDecimal = BigDecimal.ZERO,
    val date: Date,
    val buyerName: String?,
    val buyerPhone: String?,
    val paymentMethod: String?,
    val accountId: UUID?,
    val notes: String?,
    val createdAt: Date,
    val updatedAt: Date?,
    val deletedAt: Date? = null
)

@Entity(
    tableName = "part_sale_line_items",
    foreignKeys = [
        ForeignKey(entity = PartSale::class, parentColumns = ["id"], childColumns = ["saleId"], onDelete = ForeignKey.CASCADE),
        ForeignKey(entity = Part::class, parentColumns = ["id"], childColumns = ["partId"], onDelete = ForeignKey.CASCADE),
        ForeignKey(entity = PartBatch::class, parentColumns = ["id"], childColumns = ["batchId"], onDelete = ForeignKey.CASCADE)
    ],
    indices = [Index("saleId"), Index("partId"), Index("batchId")]
)
data class PartSaleLineItem(
    @PrimaryKey val id: UUID,
    val saleId: UUID,
    val partId: UUID,
    val batchId: UUID,
    val quantity: BigDecimal = BigDecimal.ZERO,
    val unitPrice: BigDecimal = BigDecimal.ZERO,
    val unitCost: BigDecimal = BigDecimal.ZERO,
    val createdAt: Date,
    val updatedAt: Date?,
    val deletedAt: Date? = null
)

@Entity(
    tableName = "debts"
)
data class Debt(
    @PrimaryKey val id: UUID,
    val counterpartyName: String,
    val counterpartyPhone: String?,
    val direction: String = "owed_to_me",
    val amount: BigDecimal = BigDecimal.ZERO,
    val notes: String?,
    val dueDate: Date?,
    val createdAt: Date,
    val updatedAt: Date?,
    val deletedAt: Date? = null
)

@Entity(
    tableName = "debt_payments",
    foreignKeys = [
        ForeignKey(entity = Debt::class, parentColumns = ["id"], childColumns = ["debtId"], onDelete = ForeignKey.CASCADE),
        ForeignKey(entity = FinancialAccount::class, parentColumns = ["id"], childColumns = ["accountId"], onDelete = ForeignKey.SET_NULL)
    ],
    indices = [Index("debtId"), Index("accountId")]
)
data class DebtPayment(
    @PrimaryKey val id: UUID,
    val amount: BigDecimal = BigDecimal.ZERO,
    val date: Date,
    val note: String?,
    val paymentMethod: String?,
    val createdAt: Date,
    val updatedAt: Date?,
    val deletedAt: Date? = null,
    val debtId: UUID?,
    val accountId: UUID?
)

@Entity(
    tableName = "account_transactions",
    foreignKeys = [
        ForeignKey(entity = FinancialAccount::class, parentColumns = ["id"], childColumns = ["accountId"], onDelete = ForeignKey.SET_NULL)
    ],
    indices = [Index("accountId")]
)
data class AccountTransaction(
    @PrimaryKey val id: UUID,
    val amount: BigDecimal = BigDecimal.ZERO,
    val date: Date,
    val transactionType: String = "deposit",
    val note: String?,
    val createdAt: Date,
    val updatedAt: Date?,
    val deletedAt: Date? = null,
    val accountId: UUID?
)

@Entity(tableName = "sync_queue")
data class SyncQueueItem(
    @PrimaryKey val id: UUID,
    val entityType: String, // vehicle, expense, etc.
    val operation: String, // upsert, delete
    val payload: String, // JSON payload
    val dealerId: UUID, // To prevent cross-user leaks
    val createdAt: Date
)

@Entity(
    tableName = "holding_cost_settings",
    indices = [Index("dealerId")]
)
data class HoldingCostSettings(
    @PrimaryKey val id: UUID,
    val dealerId: UUID,
    val annualRatePercent: BigDecimal = BigDecimal("15.00"),
    val dailyRatePercent: BigDecimal = BigDecimal("0.04109589"),
    val isEnabled: Boolean = true,
    val createdAt: Date,
    val updatedAt: Date?
)

@Entity(
    tableName = "vehicle_inventory_stats",
    foreignKeys = [
        ForeignKey(entity = Vehicle::class, parentColumns = ["id"], childColumns = ["vehicleId"], onDelete = ForeignKey.CASCADE)
    ],
    indices = [Index("vehicleId")]
)
data class VehicleInventoryStats(
    @PrimaryKey val id: UUID,
    val vehicleId: UUID,
    val daysInInventory: Int,
    val agingBucket: String,
    val totalCost: BigDecimal,
    val holdingCostAccumulated: BigDecimal,
    val roiPercent: BigDecimal?,
    val profitEstimate: BigDecimal?,
    val lastCalculatedAt: Date,
    val createdAt: Date,
    val updatedAt: Date?
)

@Entity(
    tableName = "inventory_alerts",
    foreignKeys = [
        ForeignKey(entity = Vehicle::class, parentColumns = ["id"], childColumns = ["vehicleId"], onDelete = ForeignKey.CASCADE)
    ],
    indices = [Index("vehicleId"), Index("alertType"), Index("isRead")]
)
data class InventoryAlert(
    @PrimaryKey val id: UUID,
    val vehicleId: UUID,
    val alertType: InventoryAlertType,
    val severity: String,
    val message: String,
    val isRead: Boolean = false,
    val createdAt: Date,
    val dismissedAt: Date?
)
