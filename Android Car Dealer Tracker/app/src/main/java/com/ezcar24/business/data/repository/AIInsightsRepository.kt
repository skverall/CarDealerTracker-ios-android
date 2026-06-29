package com.ezcar24.business.data.repository

import android.content.Context
import com.ezcar24.business.BuildConfig
import com.ezcar24.business.data.local.ActiveDatabaseProvider
import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.Sale
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.ui.dashboard.DashboardTimeRange
import com.ezcar24.business.util.BigDecimalSerializer
import com.ezcar24.business.util.RegionSettingsManager
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import java.math.BigDecimal
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Date
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

data class AIInsightsPreparedState(
    val cachedEntry: AIInsightsCacheEntry?,
    val fingerprint: String,
    val hasData: Boolean
)

@Serializable
data class AIInsightsResponse(
    val summary: String,
    val insights: List<String>,
    val recommendations: List<String>,
    val reportId: String? = null,
    val generatedAt: String? = null,
    val usage: AIInsightsUsage? = null,
    val history: List<AIInsightsReport>? = null
)

@Serializable
data class AIInsightsUsage(
    val used: Int,
    val limit: Int,
    val remaining: Int,
    val resetsAt: String? = null
) {
    val progress: Float
        get() = if (limit <= 0) 0f else (used.toFloat() / limit.toFloat()).coerceIn(0f, 1f)
}

@Serializable
data class AIInsightsReport(
    val id: String,
    val period: String,
    val language: String? = null,
    val summary: String,
    val insights: List<String>,
    val recommendations: List<String>,
    val createdAt: String
) {
    fun response(): AIInsightsResponse {
        return AIInsightsResponse(
            summary = summary,
            insights = insights,
            recommendations = recommendations,
            reportId = id,
            generatedAt = createdAt
        )
    }
}

@Serializable
data class AIInsightsCacheEntry(
    val response: AIInsightsResponse,
    val generatedAtMillis: Long,
    val fingerprint: String
)

@Serializable
private data class AIInsightsRequest(
    val mode: String = "generate",
    val sales: List<AIInsightSalePayload>,
    val expenses: List<AIInsightExpensePayload>,
    val inventory: List<AIInsightInventoryPayload>,
    val metadata: AIInsightMetadata,
    val forceRefresh: Boolean? = null,
    val fingerprint: String? = null
) {
    fun applying(fingerprint: String, forceRefresh: Boolean): AIInsightsRequest {
        return copy(fingerprint = fingerprint, forceRefresh = forceRefresh)
    }
}

@Serializable
private data class AIInsightsHistoryRequest(
    val mode: String = "history",
    val metadata: AIInsightMetadata
)

@Serializable
private data class AIInsightsHistoryEnvelope(
    val reports: List<AIInsightsReport> = emptyList(),
    val usage: AIInsightsUsage? = null
)

@Serializable
data class AIInsightsErrorResponse(
    val error: String,
    val code: String? = null,
    val usage: AIInsightsUsage? = null
)

@Serializable
private data class AIInsightSalePayload(
    val make: String,
    val model: String,
    @Serializable(with = BigDecimalSerializer::class) val purchasePrice: BigDecimal,
    @Serializable(with = BigDecimalSerializer::class) val salePrice: BigDecimal,
    val date: String
)

@Serializable
private data class AIInsightExpensePayload(
    val category: String,
    @Serializable(with = BigDecimalSerializer::class) val amount: BigDecimal,
    val date: String
)

@Serializable
private data class AIInsightInventoryPayload(
    val make: String,
    val model: String,
    @Serializable(with = BigDecimalSerializer::class) val purchasePrice: BigDecimal,
    @Serializable(with = BigDecimalSerializer::class) val askingPrice: BigDecimal? = null,
    val status: String,
    val purchaseDate: String,
    val daysInInventory: Int
)

@Serializable
private data class AIInsightMetadata(
    val language: String,
    val promptVersion: Int,
    val currencyCode: String,
    val region: String,
    val period: String,
    val organizationId: String?,
    val periodStart: String?,
    val periodEnd: String?
)

@Singleton
class AIInsightsRepository @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val client: SupabaseClient,
    private val databaseProvider: ActiveDatabaseProvider,
    private val regionSettingsManager: RegionSettingsManager
) {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    fun isSignedIn(): Boolean {
        return client.auth.currentUserOrNull() != null
    }

    suspend fun prepare(range: DashboardTimeRange): AIInsightsPreparedState = withContext(Dispatchers.IO) {
        val request = makeRequest(range)
        val fingerprint = fingerprintFor(request)
        AIInsightsPreparedState(
            cachedEntry = cachedEntry(range, fingerprint),
            fingerprint = fingerprint,
            hasData = request.sales.isNotEmpty() || request.expenses.isNotEmpty() || request.inventory.isNotEmpty()
        )
    }

    suspend fun loadHistory(range: DashboardTimeRange): Pair<List<AIInsightsReport>, AIInsightsUsage?> = withContext(Dispatchers.IO) {
        val metadata = makeMetadata(range)
        val envelope: AIInsightsHistoryEnvelope = invokeFunction(
            body = AIInsightsHistoryRequest(metadata = metadata)
        )
        filterReports(envelope.reports, metadata.language) to envelope.usage
    }

    suspend fun generate(range: DashboardTimeRange, forceRefresh: Boolean): Pair<AIInsightsResponse, AIInsightsCacheEntry> = withContext(Dispatchers.IO) {
        val baseRequest = makeRequest(range)
        require(baseRequest.sales.isNotEmpty() || baseRequest.expenses.isNotEmpty() || baseRequest.inventory.isNotEmpty()) {
            "No dealer data found for AI analysis."
        }

        val fingerprint = fingerprintFor(baseRequest)
        if (!forceRefresh) {
            cachedEntry(range, fingerprint)?.let { cached ->
                return@withContext cached.response to cached
            }
        }

        val request = baseRequest.applying(fingerprint = fingerprint, forceRefresh = forceRefresh)
        val response: AIInsightsResponse = invokeFunction(body = request)
        val entry = AIInsightsCacheEntry(
            response = response,
            generatedAtMillis = parseInstantMillis(response.generatedAt) ?: System.currentTimeMillis(),
            fingerprint = fingerprint
        )
        saveCachedEntry(range, entry)
        response to entry
    }

    private suspend inline fun <reified B, reified T> invokeFunction(body: B): T {
        val accessToken = client.auth.currentAccessTokenOrNull()
            ?: throw IllegalStateException("Please sign in again and try again.")

        val connection = (URL("${BuildConfig.SUPABASE_URL}/functions/v1/ai-insights")
            .openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doInput = true
            doOutput = true
            connectTimeout = 20_000
            readTimeout = 60_000
            setRequestProperty("Authorization", "Bearer $accessToken")
            setRequestProperty("Content-Type", "application/json")
        }

        try {
            connection.outputStream.bufferedWriter().use { writer ->
                writer.write(json.encodeToString(body))
            }

            val statusCode = connection.responseCode
            val responseBody = (if (statusCode in 200..299) connection.inputStream else connection.errorStream)
                ?.bufferedReader()
                ?.use { it.readText() }
                .orEmpty()

            if (statusCode !in 200..299) {
                throw AIInsightsHttpException(parseError(responseBody))
            }

            return json.decodeFromString(responseBody)
        } finally {
            connection.disconnect()
        }
    }

    private suspend fun makeRequest(range: DashboardTimeRange): AIInsightsRequest {
        val db = databaseProvider.currentDatabase()
        val vehicles = db.vehicleDao().getAllIncludingDeleted().filter { it.deletedAt == null }
        val vehiclesById = vehicles.associateBy { it.id }
        val interval = range.dateInterval()
        val sales = db.saleDao().getAllIncludingDeleted()
            .filter { it.deletedAt == null }
            .filter { sale -> sale.reportDate(vehiclesById[sale.vehicleId]).inInterval(interval) }
            .sortedByDescending { it.reportDate(vehiclesById[it.vehicleId]) }
            .mapNotNull { it.toPayload(vehiclesById[it.vehicleId]) }
            .take(200)
        val expenses = db.expenseDao().getAllIncludingDeleted()
            .filter { it.deletedAt == null }
            .filter { it.date.inInterval(interval) }
            .sortedByDescending { it.date }
            .map { it.toPayload() }
            .take(500)
        val inventory = vehicles
            .filter { !it.status.equals("sold", ignoreCase = true) }
            .sortedByDescending { it.purchaseDate }
            .map { it.toInventoryPayload() }
            .take(300)

        return AIInsightsRequest(
            sales = sales,
            expenses = expenses,
            inventory = inventory,
            metadata = makeMetadata(range)
        )
    }

    private fun makeMetadata(range: DashboardTimeRange): AIInsightMetadata {
        val regionState = regionSettingsManager.state.value
        val interval = range.dateInterval()
        return AIInsightMetadata(
            language = normalizeLanguage(regionState.selectedLanguage.tag),
            promptVersion = PROMPT_VERSION,
            currencyCode = regionState.selectedRegion.currencyCode,
            region = regionState.selectedRegion.name.lowercase(Locale.US),
            period = range.periodValue,
            organizationId = CloudSyncEnvironment.currentDealerId?.toString(),
            periodStart = interval.start?.dateString(),
            periodEnd = interval.end?.dateString()
        )
    }

    private fun cachedEntry(range: DashboardTimeRange, fingerprint: String): AIInsightsCacheEntry? {
        val raw = preferences.getString(cacheKey(range), null) ?: return null
        return runCatching { json.decodeFromString<AIInsightsCacheEntry>(raw) }
            .getOrNull()
            ?.takeIf { it.fingerprint == fingerprint }
    }

    private fun saveCachedEntry(range: DashboardTimeRange, entry: AIInsightsCacheEntry) {
        preferences.edit()
            .putString(cacheKey(range), json.encodeToString(entry))
            .apply()
    }

    private fun cacheKey(range: DashboardTimeRange): String {
        val dealerId = CloudSyncEnvironment.currentDealerId?.toString() ?: "local"
        val language = normalizeLanguage(regionSettingsManager.state.value.selectedLanguage.tag)
        return "ai_insights_cache_v${PROMPT_VERSION}_${dealerId}_${language}_${range.periodValue}"
    }

    private fun parseError(body: String): AIInsightsErrorResponse {
        return runCatching { json.decodeFromString<AIInsightsErrorResponse>(body) }
            .getOrElse { AIInsightsErrorResponse(error = body.ifBlank { "Unable to generate AI insights right now." }) }
    }

    private fun fingerprintFor(request: AIInsightsRequest): String {
        val bytes = json.encodeToString(request).toByteArray(Charsets.UTF_8)
        return MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }
    }

    private fun filterReports(reports: List<AIInsightsReport>, language: String): List<AIInsightsReport> {
        return reports.filter { normalizeLanguage(it.language) == normalizeLanguage(language) }
    }

    private fun Sale.toPayload(vehicle: Vehicle?): AIInsightSalePayload? {
        val currentVehicle = vehicle ?: return null
        return AIInsightSalePayload(
            make = currentVehicle.make.clean("Unknown"),
            model = currentVehicle.model.clean("Vehicle"),
            purchasePrice = currentVehicle.purchasePrice,
            salePrice = amount ?: currentVehicle.salePrice ?: BigDecimal.ZERO,
            date = reportDate(currentVehicle).dateString()
        )
    }

    private fun Expense.toPayload(): AIInsightExpensePayload {
        return AIInsightExpensePayload(
            category = category.clean("Other"),
            amount = amount,
            date = date.dateString()
        )
    }

    private fun Vehicle.toInventoryPayload(): AIInsightInventoryPayload {
        return AIInsightInventoryPayload(
            make = make.clean("Unknown"),
            model = model.clean("Vehicle"),
            purchasePrice = purchasePrice,
            askingPrice = askingPrice,
            status = status.clean("owned"),
            purchaseDate = purchaseDate.dateString(),
            daysInInventory = daysBetween(purchaseDate, Date()).coerceAtLeast(0)
        )
    }

    private fun Sale.reportDate(vehicle: Vehicle?): Date {
        return date ?: vehicle?.saleDate ?: Date()
    }

    private fun Date.inInterval(interval: DateInterval): Boolean {
        val afterStart = interval.start == null || !before(interval.start)
        val beforeEnd = interval.end == null || before(interval.end)
        return afterStart && beforeEnd
    }

    private fun DashboardTimeRange.dateInterval(): DateInterval {
        val zone = ZoneId.systemDefault()
        val today = java.time.LocalDate.now(zone)
        return when (this) {
            DashboardTimeRange.ONE_DAY -> DateInterval(
                start = Date.from(today.atStartOfDay(zone).toInstant()),
                end = Date.from(today.plusDays(1).atStartOfDay(zone).toInstant())
            )
            DashboardTimeRange.ONE_WEEK -> DateInterval(
                start = Date.from(today.minusDays(6).atStartOfDay(zone).toInstant()),
                end = Date()
            )
            DashboardTimeRange.ONE_MONTH -> DateInterval(
                start = Date.from(today.minusDays(30).atStartOfDay(zone).toInstant()),
                end = Date()
            )
            DashboardTimeRange.THREE_MONTHS -> DateInterval(
                start = Date.from(today.minusMonths(3).atStartOfDay(zone).toInstant()),
                end = Date()
            )
            DashboardTimeRange.SIX_MONTHS -> DateInterval(
                start = Date.from(today.minusMonths(6).atStartOfDay(zone).toInstant()),
                end = Date()
            )
            DashboardTimeRange.ALL_TIME -> DateInterval(start = null, end = null)
        }
    }

    private fun Date.dateString(): String {
        return toInstant()
            .atZone(ZoneId.systemDefault())
            .toLocalDate()
            .format(DateTimeFormatter.ISO_LOCAL_DATE)
    }

    private fun daysBetween(start: Date, end: Date): Int {
        val zone = ZoneId.systemDefault()
        val startDate = start.toInstant().atZone(zone).toLocalDate()
        val endDate = end.toInstant().atZone(zone).toLocalDate()
        return java.time.temporal.ChronoUnit.DAYS.between(startDate, endDate).toInt()
    }

    private fun parseInstantMillis(value: String?): Long? {
        if (value.isNullOrBlank()) return null
        return runCatching { Instant.parse(value).toEpochMilli() }.getOrNull()
    }

    private fun normalizeLanguage(value: String?): String {
        val code = value.orEmpty()
            .trim()
            .lowercase(Locale.US)
            .split("-", "_")
            .firstOrNull()
            .orEmpty()
        return if (code in ALLOWED_LANGUAGES) code else "en"
    }

    private fun String?.clean(fallback: String): String {
        return this?.trim()?.takeIf { it.isNotEmpty() } ?: fallback
    }

    private data class DateInterval(val start: Date?, val end: Date?)

    private companion object {
        private const val PREFERENCES_NAME = "ezcar24_ai_insights"
        private const val PROMPT_VERSION = 5
        private val ALLOWED_LANGUAGES = setOf("en", "ru", "ar", "ja", "ko", "uz", "hi", "pt", "id")
    }
}

class AIInsightsHttpException(
    val response: AIInsightsErrorResponse
) : Exception(response.error)
