package com.ezcar24.business.data.local

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.math.BigDecimal
import java.util.Date
import java.util.UUID

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
    val accountId: UUID?
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
    indices = [Index("vehicleId")]
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
    val vehicleId: UUID?
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
    val clientId: UUID?
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

