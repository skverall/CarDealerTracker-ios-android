package com.ezcar24.business.data.repository

import com.ezcar24.business.data.sync.CloudSyncEnvironment
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import java.net.HttpURLConnection
import java.net.URL
import java.time.YearMonth
import java.time.format.DateTimeFormatter
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
    private val client: SupabaseClient
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
}
