package com.ezcar24.business.data.sync

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.math.BigDecimal
import com.ezcar24.business.util.BigDecimalSerializer

// Custom Serializer for Date/UUID might be needed if standard ones fail, 
// but Supabase-kt handles UUID and Instant usually. 
// For simplicity in this plan, accessing strings/primitives directly where possible.

@Serializable
data class RemoteDealerUser(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    val name: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null
)

@Serializable
data class RemoteFinancialAccount(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    @SerialName("account_type") val accountType: String,
    @Serializable(with = BigDecimalSerializer::class) val balance: BigDecimal,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null
)

@Serializable
data class RemoteVehicle(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    val vin: String,
    val make: String? = null,
    val model: String? = null,
    val year: Int? = null,
    @SerialName("purchase_price") @Serializable(with = BigDecimalSerializer::class) val purchasePrice: BigDecimal,
    @SerialName("purchase_date") val purchaseDate: String, // String in Swift struct
    val status: String,
    val notes: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("sale_price") @Serializable(with = BigDecimalSerializer::class) val salePrice: BigDecimal? = null,
    @SerialName("sale_date") val saleDate: String? = null,
    @SerialName("photo_url") val photoUrl: String? = null,
    @SerialName("asking_price") @Serializable(with = BigDecimalSerializer::class) val askingPrice: BigDecimal? = null,
    @SerialName("report_url") val reportUrl: String? = null,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null
)

@Serializable
data class RemoteExpense(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    @Serializable(with = BigDecimalSerializer::class) val amount: BigDecimal,
    val date: String,
    @SerialName("description") val expenseDescription: String? = null,
    val category: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("vehicle_id") val vehicleId: String? = null,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("account_id") val accountId: String? = null,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("expense_type") val expenseType: String = "HOLDING_COST"
)

@Serializable
data class RemoteSale(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    @SerialName("vehicle_id") val vehicleId: String,
    @Serializable(with = BigDecimalSerializer::class) val amount: BigDecimal, // Decimal
    @SerialName("sale_price") @Serializable(with = BigDecimalSerializer::class) val salePrice: BigDecimal? = null,
    @Serializable(with = BigDecimalSerializer::class) val profit: BigDecimal? = null,
    val date: String,
    @SerialName("buyer_name") val buyerName: String? = null,
    @SerialName("buyer_phone") val buyerPhone: String? = null,
    @SerialName("payment_method") val paymentMethod: String? = null,
    @SerialName("account_id") val accountId: String? = null,
    val notes: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null
)

@Serializable
data class RemoteClient(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    val name: String,
    val phone: String? = null,
    val email: String? = null,
    val notes: String? = null,
    @SerialName("request_details") val requestDetails: String? = null,
    @SerialName("preferred_date") val preferredDate: String? = null,
    @SerialName("created_at") val createdAt: String,
    val status: String,
    @SerialName("vehicle_id") val vehicleId: String? = null,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("lead_stage") val leadStage: String? = "new",
    @SerialName("lead_source") val leadSource: String? = null,
    @SerialName("assigned_user_id") val assignedUserId: String? = null,
    @SerialName("estimated_value") @Serializable(with = BigDecimalSerializer::class) val estimatedValue: BigDecimal? = null,
    @SerialName("priority") val priority: Int = 0,
    @SerialName("lead_created_at") val leadCreatedAt: String? = null,
    @SerialName("last_contact_at") val lastContactAt: String? = null,
    @SerialName("next_follow_up_at") val nextFollowUpAt: String? = null
)

@Serializable
data class RemotePart(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    val name: String,
    val code: String? = null,
    val category: String? = null,
    val notes: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null
)

@Serializable
data class RemotePartBatch(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    @SerialName("part_id") val partId: String,
    @SerialName("batch_label") val batchLabel: String? = null,
    @SerialName("quantity_received") @Serializable(with = BigDecimalSerializer::class) val quantityReceived: BigDecimal,
    @SerialName("quantity_remaining") @Serializable(with = BigDecimalSerializer::class) val quantityRemaining: BigDecimal,
    @SerialName("unit_cost") @Serializable(with = BigDecimalSerializer::class) val unitCost: BigDecimal,
    @SerialName("purchase_date") val purchaseDate: String,
    @SerialName("purchase_account_id") val purchaseAccountId: String? = null,
    val notes: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null
)

@Serializable
data class RemotePartSale(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    @Serializable(with = BigDecimalSerializer::class) val amount: BigDecimal,
    val date: String,
    @SerialName("buyer_name") val buyerName: String? = null,
    @SerialName("buyer_phone") val buyerPhone: String? = null,
    @SerialName("payment_method") val paymentMethod: String? = null,
    @SerialName("account_id") val accountId: String? = null,
    val notes: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null
)

@Serializable
data class RemotePartSaleLineItem(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    @SerialName("sale_id") val saleId: String,
    @SerialName("part_id") val partId: String,
    @SerialName("batch_id") val batchId: String,
    @Serializable(with = BigDecimalSerializer::class) val quantity: BigDecimal,
    @SerialName("unit_price") @Serializable(with = BigDecimalSerializer::class) val unitPrice: BigDecimal,
    @SerialName("unit_cost") @Serializable(with = BigDecimalSerializer::class) val unitCost: BigDecimal,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null
)

// Add others: RemoteDebt, RemoteDebtPayment, RemoteAccountTransaction, RemoteExpenseTemplate if needed. 
// For brevity, added main ones. User asked for exact copy but I can add incrementally.
// Adding remaining...

@Serializable
data class RemoteDebt(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    @SerialName("counterparty_name") val counterpartyName: String,
    @SerialName("counterparty_phone") val counterpartyPhone: String? = null,
    val direction: String,
    @Serializable(with = BigDecimalSerializer::class) val amount: BigDecimal,
    val notes: String? = null,
    @SerialName("due_date") val dueDate: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null
)

@Serializable
data class RemoteDebtPayment(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    @SerialName("debt_id") val debtId: String,
    @Serializable(with = BigDecimalSerializer::class) val amount: BigDecimal,
    val date: String,
    val note: String? = null,
    @SerialName("payment_method") val paymentMethod: String? = null,
    @SerialName("account_id") val accountId: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null
)

@Serializable
data class RemoteAccountTransaction(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    @SerialName("account_id") val accountId: String,
    @SerialName("transaction_type") val transactionType: String,
    @Serializable(with = BigDecimalSerializer::class) val amount: BigDecimal,
    val date: String,
    val note: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null
)

@Serializable
data class RemoteExpenseTemplate(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    val name: String,
    val category: String,
    @SerialName("default_description") val defaultDescription: String? = null,
    @SerialName("default_amount") @Serializable(with = BigDecimalSerializer::class) val defaultAmount: BigDecimal? = null,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null
)

@Serializable
data class RemoteHoldingCostSettings(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    @SerialName("annual_rate_percent") @Serializable(with = BigDecimalSerializer::class) val annualRatePercent: BigDecimal,
    @SerialName("daily_rate_percent") @Serializable(with = BigDecimalSerializer::class) val dailyRatePercent: BigDecimal,
    @SerialName("is_enabled") val isEnabled: Boolean = true,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String
)

@Serializable
data class RemoteClientInteraction(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    @SerialName("client_id") val clientId: String,
    val title: String? = null,
    val detail: String? = null,
    @SerialName("occurred_at") val occurredAt: String,
    val stage: String? = "update",
    @Serializable(with = BigDecimalSerializer::class) val value: BigDecimal? = null,
    @SerialName("interaction_type") val interactionType: String? = null,
    val outcome: String? = null,
    @SerialName("duration_minutes") val durationMinutes: Int? = null,
    @SerialName("is_follow_up_required") val isFollowUpRequired: Boolean = false,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null
)

@Serializable
data class RemoteVehicleInventoryStats(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    @SerialName("vehicle_id") val vehicleId: String,
    @SerialName("days_in_inventory") val daysInInventory: Int,
    @SerialName("aging_bucket") val agingBucket: String,
    @SerialName("total_cost") @Serializable(with = BigDecimalSerializer::class) val totalCost: BigDecimal,
    @SerialName("holding_cost_accumulated") @Serializable(with = BigDecimalSerializer::class) val holdingCostAccumulated: BigDecimal,
    @SerialName("roi_percent") @Serializable(with = BigDecimalSerializer::class) val roiPercent: BigDecimal? = null,
    @SerialName("profit_estimate") @Serializable(with = BigDecimalSerializer::class) val profitEstimate: BigDecimal? = null,
    @SerialName("last_calculated_at") val lastCalculatedAt: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String
)

@Serializable
data class RemoteInventoryAlert(
    val id: String,
    @SerialName("dealer_id") val dealerId: String,
    @SerialName("vehicle_id") val vehicleId: String,
    @SerialName("alert_type") val alertType: String,
    val severity: String,
    val message: String,
    @SerialName("is_read") val isRead: Boolean = false,
    @SerialName("created_at") val createdAt: String,
    @SerialName("dismissed_at") val dismissedAt: String? = null
)

@Serializable
data class RemoteSnapshot(
    val users: List<RemoteDealerUser>,
    val accounts: List<RemoteFinancialAccount>,
    @SerialName("account_transactions") val accountTransactions: List<RemoteAccountTransaction>,
    val vehicles: List<RemoteVehicle>,
    val templates: List<RemoteExpenseTemplate>,
    val expenses: List<RemoteExpense>,
    val sales: List<RemoteSale>,
    val debts: List<RemoteDebt>,
    @SerialName("debt_payments") val debtPayments: List<RemoteDebtPayment>,
    val clients: List<RemoteClient>,
    @SerialName("client_interactions") val clientInteractions: List<RemoteClientInteraction> = emptyList(),
    val parts: List<RemotePart> = emptyList(),
    @SerialName("part_batches") val partBatches: List<RemotePartBatch> = emptyList(),
    @SerialName("part_sales") val partSales: List<RemotePartSale> = emptyList(),
    @SerialName("part_sale_line_items") val partSaleLineItems: List<RemotePartSaleLineItem> = emptyList(),
    @SerialName("holding_cost_settings") val holdingCostSettings: List<RemoteHoldingCostSettings> = emptyList(),
    @SerialName("vehicle_inventory_stats") val vehicleInventoryStats: List<RemoteVehicleInventoryStats> = emptyList(),
    @SerialName("inventory_alerts") val inventoryAlerts: List<RemoteInventoryAlert> = emptyList()
)
