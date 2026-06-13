package com.ezcar24.business.data.repository

import android.content.Context
import com.ezcar24.business.util.AppRegion
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import java.math.BigDecimal
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

private const val DEAL_DESK_PREFS = "ezcar24_deal_desk"
private const val DEAL_DESK_SETTINGS_CACHE_PREFIX = "dealDeskSettingsCache_v1"

@Serializable
enum class DealDeskBusinessRegionCode(val displayName: String) {
    @SerialName("USA")
    USA("USA"),

    @SerialName("Canada")
    CANADA("Canada"),

    @SerialName("generic")
    GENERIC("Other");

    val defaultTemplateCode: DealDeskTemplateCode
        get() = when (this) {
            USA -> DealDeskTemplateCode.USA
            CANADA -> DealDeskTemplateCode.CANADA
            GENERIC -> DealDeskTemplateCode.GENERIC
        }

    val isEnabledByDefaultForNewDealer: Boolean
        get() = when (this) {
            USA, CANADA -> true
            GENERIC -> false
        }

    val rpcValue: String
        get() = when (this) {
            USA -> "USA"
            CANADA -> "Canada"
            GENERIC -> "generic"
        }
}

@Serializable
enum class DealDeskTemplateCode(val displayName: String) {
    @SerialName("usa")
    USA("USA"),

    @SerialName("canada")
    CANADA("Canada"),

    @SerialName("generic")
    GENERIC("Generic");

    val rpcValue: String
        get() = when (this) {
            USA -> "usa"
            CANADA -> "canada"
            GENERIC -> "generic"
        }
}

@Serializable
enum class DealDeskJurisdictionType {
    @SerialName("state")
    STATE,

    @SerialName("province")
    PROVINCE,

    @SerialName("generic")
    GENERIC
}

@Serializable
enum class DealDeskLineCalculationType(val labelSource: String) {
    @SerialName("fixed_amount")
    FIXED_AMOUNT("Fixed amount"),

    @SerialName("percent_of_sale_price")
    PERCENT_OF_SALE_PRICE("% of sale price")
}

@Serializable
data class DealDeskLine(
    val id: String = UUID.randomUUID().toString(),
    val lineCode: String,
    val title: String,
    val calculationType: DealDeskLineCalculationType,
    @Serializable(with = DealDeskDecimalSerializer::class) val value: BigDecimal = BigDecimal.ZERO
)

data class DealDeskJurisdictionOption(
    val code: String,
    val title: String
)

@Serializable
data class DealDeskPaymentPlan(
    val methodCode: String,
    @Serializable(with = DealDeskDecimalSerializer::class) val downPayment: BigDecimal,
    @Serializable(with = DealDeskDecimalSerializer::class) val aprPercent: BigDecimal? = null,
    val termMonths: Int? = null
)

@Serializable
data class DealDeskTotals(
    @Serializable(with = DealDeskDecimalSerializer::class) val salePrice: BigDecimal,
    @Serializable(with = DealDeskDecimalSerializer::class) val taxTotal: BigDecimal,
    @Serializable(with = DealDeskDecimalSerializer::class) val feeTotal: BigDecimal,
    @Serializable(with = DealDeskDecimalSerializer::class) val outTheDoorTotal: BigDecimal,
    @Serializable(with = DealDeskDecimalSerializer::class) val cashReceivedNow: BigDecimal,
    @Serializable(with = DealDeskDecimalSerializer::class) val amountFinanced: BigDecimal,
    @Serializable(with = DealDeskDecimalSerializer::class) val monthlyPaymentEstimate: BigDecimal? = null
)

@Serializable
data class DealDeskSnapshot(
    val version: Int = 1,
    val templateCode: String,
    val templateVersion: Int,
    val jurisdictionType: DealDeskJurisdictionType,
    val jurisdictionCode: String,
    val taxLines: List<DealDeskLine>,
    val feeLines: List<DealDeskLine>,
    val paymentPlan: DealDeskPaymentPlan,
    val totals: DealDeskTotals
)

@Serializable
data class DealDeskSettings(
    val isEnabled: Boolean = false,
    val businessRegionCode: DealDeskBusinessRegionCode = DealDeskBusinessRegionCode.GENERIC,
    val defaultTemplateCode: DealDeskTemplateCode = DealDeskTemplateCode.GENERIC,
    val templateVersion: Int = 1,
    val taxOverrides: List<DealDeskLine> = emptyList(),
    val feeOverrides: List<DealDeskLine> = emptyList()
) {
    val seededTaxLines: List<DealDeskLine>
        get() = DealDeskTemplateCatalog.mergedTaxLines(this)

    val seededFeeLines: List<DealDeskLine>
        get() = DealDeskTemplateCatalog.mergedFeeLines(this)
}

object DealDeskTemplateCatalog {
    private val usJurisdictions = listOf(
        DealDeskJurisdictionOption("US-XX", "Unspecified"),
        DealDeskJurisdictionOption("US-AL", "Alabama"),
        DealDeskJurisdictionOption("US-AK", "Alaska"),
        DealDeskJurisdictionOption("US-AZ", "Arizona"),
        DealDeskJurisdictionOption("US-AR", "Arkansas"),
        DealDeskJurisdictionOption("US-CA", "California"),
        DealDeskJurisdictionOption("US-CO", "Colorado"),
        DealDeskJurisdictionOption("US-CT", "Connecticut"),
        DealDeskJurisdictionOption("US-DE", "Delaware"),
        DealDeskJurisdictionOption("US-FL", "Florida"),
        DealDeskJurisdictionOption("US-GA", "Georgia"),
        DealDeskJurisdictionOption("US-HI", "Hawaii"),
        DealDeskJurisdictionOption("US-ID", "Idaho"),
        DealDeskJurisdictionOption("US-IL", "Illinois"),
        DealDeskJurisdictionOption("US-IN", "Indiana"),
        DealDeskJurisdictionOption("US-IA", "Iowa"),
        DealDeskJurisdictionOption("US-KS", "Kansas"),
        DealDeskJurisdictionOption("US-KY", "Kentucky"),
        DealDeskJurisdictionOption("US-LA", "Louisiana"),
        DealDeskJurisdictionOption("US-ME", "Maine"),
        DealDeskJurisdictionOption("US-MD", "Maryland"),
        DealDeskJurisdictionOption("US-MA", "Massachusetts"),
        DealDeskJurisdictionOption("US-MI", "Michigan"),
        DealDeskJurisdictionOption("US-MN", "Minnesota"),
        DealDeskJurisdictionOption("US-MS", "Mississippi"),
        DealDeskJurisdictionOption("US-MO", "Missouri"),
        DealDeskJurisdictionOption("US-MT", "Montana"),
        DealDeskJurisdictionOption("US-NE", "Nebraska"),
        DealDeskJurisdictionOption("US-NV", "Nevada"),
        DealDeskJurisdictionOption("US-NH", "New Hampshire"),
        DealDeskJurisdictionOption("US-NJ", "New Jersey"),
        DealDeskJurisdictionOption("US-NM", "New Mexico"),
        DealDeskJurisdictionOption("US-NY", "New York"),
        DealDeskJurisdictionOption("US-NC", "North Carolina"),
        DealDeskJurisdictionOption("US-ND", "North Dakota"),
        DealDeskJurisdictionOption("US-OH", "Ohio"),
        DealDeskJurisdictionOption("US-OK", "Oklahoma"),
        DealDeskJurisdictionOption("US-OR", "Oregon"),
        DealDeskJurisdictionOption("US-PA", "Pennsylvania"),
        DealDeskJurisdictionOption("US-RI", "Rhode Island"),
        DealDeskJurisdictionOption("US-SC", "South Carolina"),
        DealDeskJurisdictionOption("US-SD", "South Dakota"),
        DealDeskJurisdictionOption("US-TN", "Tennessee"),
        DealDeskJurisdictionOption("US-TX", "Texas"),
        DealDeskJurisdictionOption("US-UT", "Utah"),
        DealDeskJurisdictionOption("US-VT", "Vermont"),
        DealDeskJurisdictionOption("US-VA", "Virginia"),
        DealDeskJurisdictionOption("US-WA", "Washington"),
        DealDeskJurisdictionOption("US-WV", "West Virginia"),
        DealDeskJurisdictionOption("US-WI", "Wisconsin"),
        DealDeskJurisdictionOption("US-WY", "Wyoming"),
        DealDeskJurisdictionOption("US-DC", "District of Columbia")
    )

    private val canadaJurisdictions = listOf(
        DealDeskJurisdictionOption("CA-XX", "Unspecified"),
        DealDeskJurisdictionOption("CA-AB", "Alberta"),
        DealDeskJurisdictionOption("CA-BC", "British Columbia"),
        DealDeskJurisdictionOption("CA-MB", "Manitoba"),
        DealDeskJurisdictionOption("CA-NB", "New Brunswick"),
        DealDeskJurisdictionOption("CA-NL", "Newfoundland and Labrador"),
        DealDeskJurisdictionOption("CA-NS", "Nova Scotia"),
        DealDeskJurisdictionOption("CA-NT", "Northwest Territories"),
        DealDeskJurisdictionOption("CA-NU", "Nunavut"),
        DealDeskJurisdictionOption("CA-ON", "Ontario"),
        DealDeskJurisdictionOption("CA-PE", "Prince Edward Island"),
        DealDeskJurisdictionOption("CA-QC", "Quebec"),
        DealDeskJurisdictionOption("CA-SK", "Saskatchewan"),
        DealDeskJurisdictionOption("CA-YT", "Yukon")
    )

    fun defaultSettings(
        businessRegionCode: DealDeskBusinessRegionCode,
        isEnabled: Boolean? = null,
        appRegion: AppRegion? = null
    ): DealDeskSettings {
        return DealDeskSettings(
            isEnabled = isEnabled ?: businessRegionCode.isEnabledByDefaultForNewDealer,
            businessRegionCode = businessRegionCode,
            defaultTemplateCode = businessRegionCode.defaultTemplateCode,
            templateVersion = 1,
            taxOverrides = defaultTaxLines(businessRegionCode.defaultTemplateCode, appRegion),
            feeOverrides = defaultFeeLines(businessRegionCode.defaultTemplateCode, appRegion)
        )
    }

    fun defaultTaxLines(
        templateCode: DealDeskTemplateCode,
        appRegion: AppRegion? = null
    ): List<DealDeskLine> {
        return when (templateCode) {
            DealDeskTemplateCode.USA -> listOf(
                DealDeskLine(
                    lineCode = "sales_tax",
                    title = "Sales tax",
                    calculationType = DealDeskLineCalculationType.PERCENT_OF_SALE_PRICE
                )
            )

            DealDeskTemplateCode.CANADA -> listOf(
                DealDeskLine(
                    lineCode = "gst",
                    title = "GST",
                    calculationType = DealDeskLineCalculationType.PERCENT_OF_SALE_PRICE
                ),
                DealDeskLine(
                    lineCode = "hst",
                    title = "HST",
                    calculationType = DealDeskLineCalculationType.PERCENT_OF_SALE_PRICE
                ),
                DealDeskLine(
                    lineCode = "pst",
                    title = "PST",
                    calculationType = DealDeskLineCalculationType.PERCENT_OF_SALE_PRICE
                ),
                DealDeskLine(
                    lineCode = "qst",
                    title = "QST",
                    calculationType = DealDeskLineCalculationType.PERCENT_OF_SALE_PRICE
                )
            )

            DealDeskTemplateCode.GENERIC -> {
                if (appRegion == AppRegion.JAPAN) {
                    listOf(
                        DealDeskLine(
                            lineCode = "consumption_tax",
                            title = "Consumption Tax (10%)",
                            calculationType = DealDeskLineCalculationType.PERCENT_OF_SALE_PRICE,
                            value = BigDecimal("10")
                        )
                    )
                } else {
                    listOf(
                        DealDeskLine(
                            lineCode = "tax",
                            title = "VAT / Tax",
                            calculationType = DealDeskLineCalculationType.PERCENT_OF_SALE_PRICE
                        )
                    )
                }
            }
        }
    }

    fun defaultFeeLines(
        templateCode: DealDeskTemplateCode,
        appRegion: AppRegion? = null
    ): List<DealDeskLine> {
        return when (templateCode) {
            DealDeskTemplateCode.USA -> listOf(
                DealDeskLine(
                    lineCode = "doc_fee",
                    title = "Doc fee",
                    calculationType = DealDeskLineCalculationType.FIXED_AMOUNT
                ),
                DealDeskLine(
                    lineCode = "title",
                    title = "Title",
                    calculationType = DealDeskLineCalculationType.FIXED_AMOUNT
                ),
                DealDeskLine(
                    lineCode = "registration",
                    title = "Registration",
                    calculationType = DealDeskLineCalculationType.FIXED_AMOUNT
                ),
                DealDeskLine(
                    lineCode = "license",
                    title = "License",
                    calculationType = DealDeskLineCalculationType.FIXED_AMOUNT
                )
            )

            DealDeskTemplateCode.CANADA -> listOf(
                DealDeskLine(
                    lineCode = "admin_fee",
                    title = "Admin fee",
                    calculationType = DealDeskLineCalculationType.FIXED_AMOUNT
                ),
                DealDeskLine(
                    lineCode = "licensing",
                    title = "Licensing",
                    calculationType = DealDeskLineCalculationType.FIXED_AMOUNT
                )
            )

            DealDeskTemplateCode.GENERIC -> {
                if (appRegion == AppRegion.JAPAN) {
                    listOf(
                        DealDeskLine(
                            lineCode = "registration",
                            title = "Plate / Registration",
                            calculationType = DealDeskLineCalculationType.FIXED_AMOUNT
                        ),
                        DealDeskLine(
                            lineCode = "inspection_shaken",
                            title = "Inspection / Shaken",
                            calculationType = DealDeskLineCalculationType.FIXED_AMOUNT
                        )
                    )
                } else {
                    listOf(
                        DealDeskLine(
                            lineCode = "fees",
                            title = "Fees",
                            calculationType = DealDeskLineCalculationType.FIXED_AMOUNT
                        )
                    )
                }
            }
        }
    }

    fun defaultJurisdictionType(templateCode: DealDeskTemplateCode): DealDeskJurisdictionType {
        return when (templateCode) {
            DealDeskTemplateCode.USA -> DealDeskJurisdictionType.STATE
            DealDeskTemplateCode.CANADA -> DealDeskJurisdictionType.PROVINCE
            DealDeskTemplateCode.GENERIC -> DealDeskJurisdictionType.GENERIC
        }
    }

    fun defaultJurisdictionCode(templateCode: DealDeskTemplateCode): String {
        return when (templateCode) {
            DealDeskTemplateCode.USA -> "US-XX"
            DealDeskTemplateCode.CANADA -> "CA-XX"
            DealDeskTemplateCode.GENERIC -> "GENERIC"
        }
    }

    fun jurisdictionOptions(templateCode: DealDeskTemplateCode): List<DealDeskJurisdictionOption> {
        return when (templateCode) {
            DealDeskTemplateCode.USA -> usJurisdictions
            DealDeskTemplateCode.CANADA -> canadaJurisdictions
            DealDeskTemplateCode.GENERIC -> listOf(DealDeskJurisdictionOption("GENERIC", "Generic"))
        }
    }

    fun mergedTaxLines(settings: DealDeskSettings): List<DealDeskLine> {
        return mergedLines(
            defaults = defaultTaxLines(settings.defaultTemplateCode),
            overrides = settings.taxOverrides
        )
    }

    fun mergedFeeLines(settings: DealDeskSettings): List<DealDeskLine> {
        return mergedLines(
            defaults = defaultFeeLines(settings.defaultTemplateCode),
            overrides = settings.feeOverrides
        )
    }

    fun setupGuidanceMessage(
        templateCode: DealDeskTemplateCode,
        taxLines: List<DealDeskLine>,
        feeLines: List<DealDeskLine>
    ): String? {
        val missingTaxes = taxLines.isNotEmpty() && taxLines.all { it.value.compareTo(BigDecimal.ZERO) == 0 }
        val missingFees = feeLines.isNotEmpty() && feeLines.all { it.value.compareTo(BigDecimal.ZERO) == 0 }

        if (!missingTaxes && !missingFees) return null

        return when (templateCode) {
            DealDeskTemplateCode.USA, DealDeskTemplateCode.CANADA -> {
                val regionName = templateCode.displayName
                when {
                    missingTaxes && missingFees -> "$regionName template lines are placeholders until you enter your local taxes and fees."
                    missingTaxes -> "$regionName tax lines are placeholders until you enter your local rates."
                    else -> "$regionName fee lines are placeholders until you enter your local amounts."
                }
            }

            DealDeskTemplateCode.GENERIC -> when {
                missingTaxes && missingFees -> "Generic template starts empty. Add only the taxes and fees you actually collect."
                missingTaxes -> "Generic tax line is optional. Enter it only if you collect tax."
                else -> "Generic fee line is optional. Enter it only if you collect fees."
            }
        }
    }

    private fun mergedLines(
        defaults: List<DealDeskLine>,
        overrides: List<DealDeskLine>
    ): List<DealDeskLine> {
        if (overrides.isEmpty()) return defaults
        val overrideMap = overrides.associateBy { it.lineCode }
        val mergedDefaults = defaults.map { overrideMap[it.lineCode] ?: it }
        val extraOverrides = overrides.filter { override ->
            defaults.none { it.lineCode == override.lineCode }
        }
        return mergedDefaults + extraOverrides
    }
}

private val dealDeskSnapshotJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
}

fun DealDeskSnapshot.toJsonString(): String {
    return dealDeskSnapshotJson.encodeToString(this)
}

@Singleton
class DealDeskRepository @Inject constructor(
    @ApplicationContext context: Context,
    private val client: SupabaseClient
) {
    private val prefs = context.getSharedPreferences(DEAL_DESK_PREFS, Context.MODE_PRIVATE)
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }
    private val lineListSerializer = ListSerializer(DealDeskLine.serializer())

    suspend fun loadSettings(organizationId: UUID): DealDeskSettings = withContext(Dispatchers.IO) {
        val cached = cachedSettings(organizationId)
        runCatching {
            val params = buildJsonObject {
                put("p_organization_id", organizationId.toString())
            }
            val result = client.postgrest.rpc("get_organization_deal_desk_settings", params)
            json.decodeFromString<DealDeskSettings>(result.data).also {
                cacheSettings(organizationId, it)
            }
        }.getOrElse { error ->
            cached ?: throw error
        }
    }

    suspend fun saveSettings(
        organizationId: UUID,
        settings: DealDeskSettings
    ): DealDeskSettings = withContext(Dispatchers.IO) {
        val params = buildJsonObject {
            put("p_organization_id", organizationId.toString())
            put("p_is_enabled", settings.isEnabled)
            put("p_business_region_code", settings.businessRegionCode.rpcValue)
            put("p_default_template_code", settings.defaultTemplateCode.rpcValue)
            put("p_template_version", settings.templateVersion.coerceAtLeast(1))
            put("p_tax_overrides", json.encodeToJsonElement(lineListSerializer, settings.taxOverrides))
            put("p_fee_overrides", json.encodeToJsonElement(lineListSerializer, settings.feeOverrides))
        }
        val result = client.postgrest.rpc("upsert_organization_deal_desk_settings", params)
        json.decodeFromString<DealDeskSettings>(result.data).also {
            cacheSettings(organizationId, it)
        }
    }

    fun cachedSettings(organizationId: UUID): DealDeskSettings? {
        val key = cacheKey(organizationId) ?: return null
        val raw = prefs.getString(key, null) ?: return null
        return runCatching { json.decodeFromString<DealDeskSettings>(raw) }.getOrNull()
    }

    private fun cacheSettings(organizationId: UUID, settings: DealDeskSettings) {
        val key = cacheKey(organizationId) ?: return
        prefs.edit()
            .putString(key, json.encodeToString(settings))
            .apply()
    }

    private fun cacheKey(organizationId: UUID): String? {
        val userId = client.auth.currentUserOrNull()?.id?.lowercase() ?: return null
        return "${DEAL_DESK_SETTINGS_CACHE_PREFIX}_${userId}_${organizationId.toString().lowercase()}"
    }
}

object DealDeskDecimalSerializer : KSerializer<BigDecimal> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("DealDeskDecimal", PrimitiveKind.DOUBLE)

    override fun serialize(encoder: Encoder, value: BigDecimal) {
        if (encoder is JsonEncoder) {
            encoder.encodeJsonElement(JsonPrimitive(value.stripTrailingZeros()))
        } else {
            encoder.encodeString(value.toPlainString())
        }
    }

    override fun deserialize(decoder: Decoder): BigDecimal {
        return if (decoder is JsonDecoder) {
            runCatching { BigDecimal(decoder.decodeJsonElement().jsonPrimitive.content) }
                .getOrDefault(BigDecimal.ZERO)
        } else {
            runCatching { BigDecimal(decoder.decodeString()) }
                .getOrDefault(BigDecimal.ZERO)
        }
    }
}
