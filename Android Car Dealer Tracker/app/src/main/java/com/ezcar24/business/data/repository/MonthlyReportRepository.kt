package com.ezcar24.business.data.repository

import com.ezcar24.business.data.local.AccountTransaction
import com.ezcar24.business.data.local.ActiveDatabaseProvider
import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.HoldingCostSettings
import com.ezcar24.business.data.local.Part
import com.ezcar24.business.data.local.PartBatch
import com.ezcar24.business.data.local.PartSale
import com.ezcar24.business.data.local.PartSaleLineItem
import com.ezcar24.business.data.local.Sale
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.util.calculator.HoldingCostCalculator
import com.ezcar24.business.util.calculator.VehicleFinancialsCalculator
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import java.math.BigDecimal
import java.net.HttpURLConnection
import java.net.URL
import java.time.ZoneId
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put


@Serializable
data class ReportMonth(
    val year: Int,
    val month: Int
) {
    fun displayTitle(locale: Locale = Locale.getDefault()): String {
        return YearMonth.of(year, month)
            .atDay(1)
            .format(DateTimeFormatter.ofPattern("LLLL yyyy", locale))
    }

    companion object {
        fun previousCalendarMonth(): ReportMonth {
            val previousMonth = YearMonth.now().minusMonths(1)
            return ReportMonth(
                year = previousMonth.year,
                month = previousMonth.monthValue
            )
        }
    }
}

@Serializable
data class MonthlyReportPreferences(
    val version: Int = STORAGE_VERSION,
    val isEnabled: Boolean = false,
    val timezoneIdentifier: String = TimeZone.getDefault().id,
    val deliveryDay: Int = 2,
    val deliveryHour: Int = 9,
    val deliveryMinute: Int = 0
) {
    companion object {
        const val STORAGE_VERSION = 1

        fun default(timezoneIdentifier: String = TimeZone.getDefault().id): MonthlyReportPreferences {
            return MonthlyReportPreferences(
                version = STORAGE_VERSION,
                isEnabled = false,
                timezoneIdentifier = timezoneIdentifier,
                deliveryDay = 2,
                deliveryHour = 9,
                deliveryMinute = 0
            )
        }
    }
}

data class MonthlyReportRecipient(
    val email: String,
    val role: String
)

data class MonthlyReportPreview(
    val organizationName: String,
    val timezone: String,
    val reportMonth: ReportMonth,
    val title: String,
    val periodLabel: String,
    val generatedAt: String,
    val totalRevenue: String,
    val realizedSalesProfit: String,
    val monthlyExpenses: String,
    val netCashMovement: String
)

data class MonthlyReportSnapshot(
    val reportMonth: ReportMonth,
    val periodLabel: String,
    val generatedAt: Date,
    val executiveSummary: MonthlyReportExecutiveSummary,
    val expenseCategories: List<MonthlyReportCategorySummary>,
    val vehicleSales: List<MonthlyReportVehicleSaleSummary>,
    val partSales: List<MonthlyReportPartSaleSummary>,
    val cashMovement: MonthlyReportCashMovementSummary,
    val inventory: MonthlyReportInventorySummary,
    val topProfitableVehicles: List<MonthlyReportVehicleSaleSummary>,
    val lossMakingVehicles: List<MonthlyReportVehicleSaleSummary>
)

data class MonthlyReportExecutiveSummary(
    val totalRevenue: BigDecimal,
    val vehicleRevenue: BigDecimal,
    val partRevenue: BigDecimal,
    val realizedSalesProfit: BigDecimal,
    val vehicleProfit: BigDecimal,
    val partProfit: BigDecimal,
    val monthlyExpenses: BigDecimal,
    val netCashMovement: BigDecimal,
    val vehicleSalesCount: Int,
    val partSalesCount: Int,
    val inventoryCount: Int,
    val inventoryCapital: BigDecimal,
    val partsUnitsInStock: BigDecimal,
    val partsInventoryCost: BigDecimal
)

data class MonthlyReportCategorySummary(
    val title: String,
    val amount: BigDecimal,
    val count: Int,
    val share: Double
)

data class MonthlyReportVehicleSaleSummary(
    val id: UUID,
    val title: String,
    val buyerName: String,
    val soldAt: Date,
    val revenue: BigDecimal,
    val purchasePrice: BigDecimal,
    val vehicleExpenses: BigDecimal,
    val holdingCost: BigDecimal,
    val realizedProfit: BigDecimal
)

data class MonthlyReportPartSaleSummary(
    val id: UUID,
    val soldAt: Date,
    val buyerName: String,
    val summary: String,
    val revenue: BigDecimal,
    val costOfGoodsSold: BigDecimal,
    val realizedProfit: BigDecimal
)

data class MonthlyReportCashMovementSummary(
    val depositsTotal: BigDecimal,
    val withdrawalsTotal: BigDecimal,
    val netMovement: BigDecimal,
    val transactionCount: Int
)

data class MonthlyReportInventorySummary(
    val vehicleCount: Int,
    val vehicleCapital: BigDecimal,
    val partsCount: Int,
    val partsUnitsInStock: BigDecimal,
    val partsInventoryCost: BigDecimal
)

@Serializable
private data class MonthlyReportDispatchRequest(
    val mode: String,
    val organizationId: String,
    val month: ReportMonth
)

@Serializable
private data class MonthlyReportDispatchResponse(
    val success: Boolean = false,
    val status: String? = null,
    val reason: String? = null,
    val error: String? = null
)

@Serializable
private data class MonthlyReportPreviewResponse(
    val success: Boolean = false,
    val error: String? = null,
    val organizationName: String? = null,
    val timezone: String? = null,
    val reportMonth: ReportMonth? = null,
    val preview: MonthlyReportPreviewPayload? = null
)

@Serializable
private data class MonthlyReportPreviewPayload(
    val title: String,
    val periodLabel: String,
    val generatedAt: String,
    val metrics: MonthlyReportPreviewMetricsPayload
)

@Serializable
private data class MonthlyReportPreviewMetricsPayload(
    val totalRevenue: String,
    val realizedSalesProfit: String,
    val monthlyExpenses: String,
    val netCashMovement: String
)

@Serializable
private data class MonthlyReportFunctionErrorPayload(
    val error: String? = null
)

@Singleton
class MonthlyReportRepository @Inject constructor(
    private val accountRepository: AccountRepository,
    private val client: SupabaseClient,
    private val databaseProvider: ActiveDatabaseProvider
) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun loadPreferences(organizationId: UUID): MonthlyReportPreferences = withContext(Dispatchers.IO) {
        val params = buildJsonObject {
            put("p_organization_id", organizationId.toString())
        }
        val result = client.postgrest.rpc("get_monthly_report_preferences", params)
        json.decodeFromString<MonthlyReportPreferences>(result.data)
    }

    suspend fun savePreferences(
        organizationId: UUID,
        preferences: MonthlyReportPreferences
    ): MonthlyReportPreferences = withContext(Dispatchers.IO) {
        val params = buildJsonObject {
            put("p_organization_id", organizationId.toString())
            put("p_version", preferences.version)
            put("p_is_enabled", preferences.isEnabled)
            put("p_timezone_identifier", preferences.timezoneIdentifier)
            put("p_delivery_day", preferences.deliveryDay)
            put("p_delivery_hour", preferences.deliveryHour)
            put("p_delivery_minute", preferences.deliveryMinute)
        }
        val result = client.postgrest.rpc("upsert_monthly_report_preferences", params)
        json.decodeFromString<MonthlyReportPreferences>(result.data)
    }

    suspend fun resolveRecipients(organizationId: UUID): List<MonthlyReportRecipient> = withContext(Dispatchers.IO) {
        accountRepository.fetchTeamMembers(organizationId)
            .asSequence()
            .mapNotNull { member ->
                val role = member.role.trim().lowercase(Locale.US)
                val email = member.email?.trim().orEmpty()
                if ((role == "owner" || role == "admin") && email.isNotEmpty()) {
                    MonthlyReportRecipient(email = email, role = role)
                } else {
                    null
                }
            }
            .sortedWith(
                compareBy<MonthlyReportRecipient> { it.role != "owner" }
                    .thenBy { it.email.lowercase(Locale.US) }
            )
            .toList()
    }

    suspend fun loadPreview(
        organizationId: UUID,
        month: ReportMonth
    ): MonthlyReportPreview = withContext(Dispatchers.IO) {
        val response = invokeDispatch<MonthlyReportPreviewResponse>(
            mode = "preview",
            organizationId = organizationId,
            month = month
        )
        if (!response.success) {
            throw IllegalStateException(response.error ?: "Unable to load the monthly report preview.")
        }

        val preview = response.preview
            ?: throw IllegalStateException("Monthly report preview is unavailable right now.")
        val reportMonth = response.reportMonth ?: month

        MonthlyReportPreview(
            organizationName = response.organizationName ?: "Organization",
            timezone = response.timezone ?: TimeZone.getDefault().id,
            reportMonth = reportMonth,
            title = preview.title,
            periodLabel = preview.periodLabel,
            generatedAt = preview.generatedAt,
            totalRevenue = preview.metrics.totalRevenue,
            realizedSalesProfit = preview.metrics.realizedSalesProfit,
            monthlyExpenses = preview.metrics.monthlyExpenses,
            netCashMovement = preview.metrics.netCashMovement
        )
    }

    suspend fun sendTestReport(
        organizationId: UUID,
        month: ReportMonth
    ): String = withContext(Dispatchers.IO) {
        val response = invokeDispatch<MonthlyReportDispatchResponse>(
            mode = "test",
            organizationId = organizationId,
            month = month
        )

        if (!response.success) {
            throw IllegalStateException(response.error ?: "Unable to send the monthly report test email.")
        }

        when (response.status?.trim()?.lowercase(Locale.US)) {
            "sent" -> "Test report request submitted."
            "skipped" -> response.reason ?: "Test report request submitted."
            else -> response.reason ?: "Test report request submitted."
        }
    }

    suspend fun loadLocalSnapshot(month: ReportMonth): MonthlyReportSnapshot = withContext(Dispatchers.IO) {
        buildLocalSnapshot(month = month, interval = month.dateInterval())
    }

    suspend fun loadLocalSnapshot(startDate: Date, endDate: Date): MonthlyReportSnapshot = withContext(Dispatchers.IO) {
        val interval = dateRangeInterval(startDate, endDate)
        buildLocalSnapshot(month = interval.first.reportMonth(), interval = interval)
    }

    private suspend fun buildLocalSnapshot(
        month: ReportMonth,
        interval: Pair<Date, Date>
    ): MonthlyReportSnapshot {
        val db = databaseProvider.currentDatabase()
        val allVehicles = db.vehicleDao().getAllIncludingDeleted().filter { it.deletedAt == null }
        val vehiclesById = allVehicles.associateBy { it.id }
        val allExpenses = db.expenseDao().getAllIncludingDeleted().filter { it.deletedAt == null }
        val allSales = db.saleDao().getAllIncludingDeleted().filter { it.deletedAt == null }
        val allPartSales = db.partSaleDao().getAllIncludingDeleted().filter { it.deletedAt == null }
        val allPartLineItems = db.partSaleLineItemDao().getAllIncludingDeleted().filter { it.deletedAt == null }
        val allParts = db.partDao().getAllIncludingDeleted().filter { it.deletedAt == null }
        val allPartBatches = db.partBatchDao().getAllIncludingDeleted().filter { it.deletedAt == null }
        val allTransactions = db.accountTransactionDao().getAllIncludingDeleted().filter { it.deletedAt == null }
        val settings = CloudSyncEnvironment.currentDealerId?.let { dealerId ->
            db.holdingCostSettingsDao().getByDealerId(dealerId)
        } ?: db.holdingCostSettingsDao().getAllIncludingDeleted().maxByOrNull { it.updatedAt ?: it.createdAt }

        val expensesInMonth = allExpenses.filter { it.date.inRange(interval) }
        val vehicleSales = allSales
            .filter { (it.date ?: vehiclesById[it.vehicleId]?.saleDate)?.inRange(interval) == true }
            .map { sale -> sale.toVehicleSaleSummary(vehiclesById[sale.vehicleId], allExpenses, settings) }
            .sortedByDescending { it.soldAt }
        val lineItemsBySale = allPartLineItems.groupBy { it.saleId }
        val partsById = allParts.associateBy { it.id }
        val partSales = allPartSales
            .filter { it.date.inRange(interval) }
            .map { sale -> sale.toPartSaleSummary(lineItemsBySale[sale.id].orEmpty(), partsById) }
            .sortedByDescending { it.soldAt }
        val transactionsInMonth = allTransactions.filter { it.date.inRange(interval) }
        val expenseCategories = expensesInMonth.toExpenseCategories()
        val cashMovement = transactionsInMonth.toCashMovementSummary()
        val inventory = makeInventorySummary(
            vehicles = allVehicles,
            expenses = allExpenses,
            parts = allParts,
            partBatches = allPartBatches
        )
        val vehicleRevenue = vehicleSales.sumMoney { it.revenue }
        val partRevenue = partSales.sumMoney { it.revenue }
        val vehicleProfit = vehicleSales.sumMoney { it.realizedProfit }
        val partProfit = partSales.sumMoney { it.realizedProfit }
        val sortedByProfit = vehicleSales.sortedWith(
            compareByDescending<MonthlyReportVehicleSaleSummary> { it.realizedProfit }
                .thenByDescending { it.soldAt }
        )

        return MonthlyReportSnapshot(
            reportMonth = month,
            periodLabel = interval.periodLabel(),
            generatedAt = Date(),
            executiveSummary = MonthlyReportExecutiveSummary(
                totalRevenue = vehicleRevenue + partRevenue,
                vehicleRevenue = vehicleRevenue,
                partRevenue = partRevenue,
                realizedSalesProfit = vehicleProfit + partProfit,
                vehicleProfit = vehicleProfit,
                partProfit = partProfit,
                monthlyExpenses = expensesInMonth.sumMoney { it.amount },
                netCashMovement = cashMovement.netMovement,
                vehicleSalesCount = vehicleSales.size,
                partSalesCount = partSales.size,
                inventoryCount = inventory.vehicleCount,
                inventoryCapital = inventory.vehicleCapital,
                partsUnitsInStock = inventory.partsUnitsInStock,
                partsInventoryCost = inventory.partsInventoryCost
            ),
            expenseCategories = expenseCategories,
            vehicleSales = vehicleSales,
            partSales = partSales,
            cashMovement = cashMovement,
            inventory = inventory,
            topProfitableVehicles = sortedByProfit.filter { it.realizedProfit > BigDecimal.ZERO }.take(5),
            lossMakingVehicles = sortedByProfit.reversed().filter { it.realizedProfit < BigDecimal.ZERO }.take(5)
        )
    }

    private suspend inline fun <reified T> invokeDispatch(
        mode: String,
        organizationId: UUID,
        month: ReportMonth
    ): T = withContext(Dispatchers.IO) {
        val accessToken = client.auth.currentAccessTokenOrNull()
            ?: throw IllegalStateException("Please sign in again and try again.")

        val connection = (URL("${CloudSyncEnvironment.SUPABASE_URL}/functions/v1/monthly_report_dispatch")
            .openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doInput = true
            doOutput = true
            connectTimeout = 15_000
            readTimeout = 15_000
            setRequestProperty("Authorization", "Bearer $accessToken")
            setRequestProperty("Content-Type", "application/json")
        }

        try {
            val payload = MonthlyReportDispatchRequest(
                mode = mode,
                organizationId = organizationId.toString(),
                month = month
            )
            connection.outputStream.bufferedWriter().use { writer ->
                writer.write(json.encodeToString(payload))
            }

            val statusCode = connection.responseCode
            val body = (if (statusCode in 200..299) connection.inputStream else connection.errorStream)
                ?.bufferedReader()
                ?.use { it.readText() }
                .orEmpty()

            if (statusCode !in 200..299) {
                throw IllegalStateException(parseFunctionError(body))
            }

            try {
                json.decodeFromString<T>(body)
            } catch (_: Exception) {
                throw IllegalStateException(parseFunctionError(body))
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun parseFunctionError(body: String): String {
        val trimmed = body.trim()
        if (trimmed.isEmpty()) {
            return "Unable to reach the server right now. Try again in a moment."
        }

        runCatching {
            json.decodeFromString<MonthlyReportFunctionErrorPayload>(trimmed).error
        }.getOrNull()?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }

        runCatching {
            json.decodeFromString<MonthlyReportDispatchResponse>(trimmed).error
        }.getOrNull()?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }

        return trimmed
    }

    private fun ReportMonth.dateInterval(): Pair<Date, Date> {
        val zone = ZoneId.systemDefault()
        val start = YearMonth.of(year, month).atDay(1).atStartOfDay(zone).toInstant()
        val end = YearMonth.of(year, month).plusMonths(1).atDay(1).atStartOfDay(zone).toInstant()
        return Date.from(start) to Date.from(end)
    }

    private fun dateRangeInterval(startDate: Date, endDate: Date): Pair<Date, Date> {
        val zone = ZoneId.systemDefault()
        val start = startDate.toInstant().atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()
        val end = endDate.toInstant().atZone(zone).toLocalDate().plusDays(1).atStartOfDay(zone).toInstant()
        val startValue = Date.from(start)
        val endValue = Date.from(end)
        require(endValue.after(startValue)) { "Start date must be before end date." }
        return startValue to endValue
    }

    private fun Date.reportMonth(): ReportMonth {
        val zone = ZoneId.systemDefault()
        val localDate = toInstant().atZone(zone).toLocalDate()
        return ReportMonth(year = localDate.year, month = localDate.monthValue)
    }

    private fun Date.inRange(interval: Pair<Date, Date>): Boolean {
        return !before(interval.first) && before(interval.second)
    }

    private fun Pair<Date, Date>.periodLabel(): String {
        val formatter = DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.getDefault())
        val zone = ZoneId.systemDefault()
        val start = first.toInstant().atZone(zone).toLocalDate()
        val end = second.toInstant().atZone(zone).toLocalDate().minusDays(1)
        return "${formatter.format(start)} - ${formatter.format(end)}"
    }

    private fun Sale.toVehicleSaleSummary(
        vehicle: Vehicle?,
        allExpenses: List<Expense>,
        settings: HoldingCostSettings?
    ): MonthlyReportVehicleSaleSummary {
        val soldAt = date ?: vehicle?.saleDate ?: Date()
        val vehicleExpenses = vehicle?.let { currentVehicle ->
            allExpenses
                .filter { it.vehicleId == currentVehicle.id && !it.date.after(soldAt) }
                .sumMoney { it.amount }
        } ?: BigDecimal.ZERO
        val holdingCost = if (vehicle != null && settings != null) {
            HoldingCostCalculator.calculateAccumulatedHoldingCost(
                vehicle = vehicle,
                settings = settings,
                allExpenses = allExpenses.filter { it.vehicleId == vehicle.id && !it.date.after(soldAt) },
                asOfDate = soldAt
            )
        } else {
            BigDecimal.ZERO
        }
        val revenue = amount ?: BigDecimal.ZERO
        val purchasePrice = vehicle?.purchasePrice ?: BigDecimal.ZERO
        val totalCost = vehicle?.let { currentVehicle ->
            VehicleFinancialsCalculator.calculateTotalCost(
                vehicle = currentVehicle,
                allExpenses = allExpenses.filter { it.vehicleId == currentVehicle.id && !it.date.after(soldAt) },
                holdingCost = holdingCost
            )
        } ?: BigDecimal.ZERO

        return MonthlyReportVehicleSaleSummary(
            id = id,
            title = vehicleTitle(vehicle),
            buyerName = buyerName.trimmedOr("Walk-in buyer"),
            soldAt = soldAt,
            revenue = revenue,
            purchasePrice = purchasePrice,
            vehicleExpenses = vehicleExpenses,
            holdingCost = holdingCost,
            realizedProfit = if (vehicle != null) {
                VehicleFinancialsCalculator.calculateActualProfit(revenue, totalCost)
            } else {
                revenue
            }
        )
    }

    private fun PartSale.toPartSaleSummary(
        lineItems: List<PartSaleLineItem>,
        partsById: Map<UUID, Part>
    ): MonthlyReportPartSaleSummary {
        val costOfGoodsSold = lineItems.sumMoney { it.unitCost * it.quantity }
        return MonthlyReportPartSaleSummary(
            id = id,
            soldAt = date,
            buyerName = buyerName.trimmedOr("Walk-in buyer"),
            summary = partSaleSummary(lineItems, partsById),
            revenue = amount,
            costOfGoodsSold = costOfGoodsSold,
            realizedProfit = amount - costOfGoodsSold
        )
    }

    private fun List<Expense>.toExpenseCategories(): List<MonthlyReportCategorySummary> {
        val total = sumMoney { it.amount }
        return groupBy { it.category.trim().ifEmpty { "Other" } }
            .map { (title, rows) ->
                val amount = rows.sumMoney { it.amount }
                MonthlyReportCategorySummary(
                    title = title.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString() },
                    amount = amount,
                    count = rows.size,
                    share = if (total > BigDecimal.ZERO) amount.toDouble() / total.toDouble() else 0.0
                )
            }
            .sortedWith(compareByDescending<MonthlyReportCategorySummary> { it.amount }.thenBy { it.title })
    }

    private fun List<AccountTransaction>.toCashMovementSummary(): MonthlyReportCashMovementSummary {
        val deposits = filter { it.transactionType.lowercase(Locale.US) == "deposit" }.sumMoney { it.amount }
        val withdrawals = filter { it.transactionType.lowercase(Locale.US) == "withdrawal" }.sumMoney { it.amount }
        return MonthlyReportCashMovementSummary(
            depositsTotal = deposits,
            withdrawalsTotal = withdrawals,
            netMovement = deposits - withdrawals,
            transactionCount = size
        )
    }

    private fun makeInventorySummary(
        vehicles: List<Vehicle>,
        expenses: List<Expense>,
        parts: List<Part>,
        partBatches: List<PartBatch>
    ): MonthlyReportInventorySummary {
        val inventoryVehicles = vehicles.filter { it.status != "sold" }
        val expensesByVehicle = expenses.groupBy { it.vehicleId }
        val vehicleCapital = inventoryVehicles.sumMoney { vehicle ->
            vehicle.purchasePrice + expensesByVehicle[vehicle.id].orEmpty().sumMoney { it.amount }
        }
        val activePartIds = parts.map { it.id }.toSet()
        val activeBatches = partBatches.filter { it.partId in activePartIds && it.quantityRemaining > BigDecimal.ZERO }
        val partsUnitsInStock = activeBatches.sumMoney { it.quantityRemaining }
        val partsInventoryCost = activeBatches.sumMoney { it.quantityRemaining * it.unitCost }

        return MonthlyReportInventorySummary(
            vehicleCount = inventoryVehicles.size,
            vehicleCapital = vehicleCapital,
            partsCount = activeBatches.map { it.partId }.distinct().size,
            partsUnitsInStock = partsUnitsInStock,
            partsInventoryCost = partsInventoryCost
        )
    }

    private fun vehicleTitle(vehicle: Vehicle?): String {
        return listOfNotNull(vehicle?.make, vehicle?.model)
            .joinToString(" ")
            .trim()
            .ifEmpty { vehicle?.vin?.takeIf { it.isNotBlank() } ?: "Vehicle" }
    }

    private fun partSaleSummary(
        lineItems: List<PartSaleLineItem>,
        partsById: Map<UUID, Part>
    ): String {
        val titles = lineItems.mapNotNull { item ->
            partsById[item.partId]?.name?.trim()?.takeIf { it.isNotEmpty() }
        }
        return when {
            titles.isEmpty() -> "Parts sale"
            titles.size == 1 -> titles.first()
            else -> "${titles.first()} + ${titles.size - 1} more"
        }
    }

    private fun String?.trimmedOr(fallback: String): String {
        return this?.trim()?.takeIf { it.isNotEmpty() } ?: fallback
    }

    private inline fun <T> Iterable<T>.sumMoney(selector: (T) -> BigDecimal): BigDecimal {
        return fold(BigDecimal.ZERO) { total, item -> total + selector(item) }
    }
}
