package com.ezcar24.business.util

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.core.os.LocaleListCompat
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import java.math.BigDecimal
import java.text.DecimalFormat
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.roundToInt
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class AppRegion(
    val displayName: String,
    val currencyCode: String,
    val currencySymbol: String,
    val localeTag: String,
    val usesKilometers: Boolean,
    val currencyDecimals: Int
) {
    UAE("UAE", "AED", "AED", "en-AE", true, 2),
    USA("USA", "USD", "$", "en-US", false, 2),
    CANADA("Canada", "CAD", "CA$", "en-CA", true, 2),
    UK("UK", "GBP", "£", "en-GB", false, 2),
    EUROPE("Europe", "EUR", "€", "en-IE", true, 2),
    RUSSIA("Russia", "RUB", "₽", "ru-RU", true, 2),
    TURKEY("Turkey", "TRY", "₺", "tr-TR", true, 2),
    JAPAN("Japan", "JPY", "¥", "ja-JP", true, 0),
    INDIA("India", "INR", "₹", "en-IN", true, 2),
    KOREA("Korea", "KRW", "₩", "ko-KR", true, 0);

    val locale: Locale
        get() = Locale.forLanguageTag(localeTag)
}

enum class AppLanguage(
    val tag: String,
    val nativeName: String,
    val isRtl: Boolean
) {
    ENGLISH("en", "English", false),
    RUSSIAN("ru", "Русский", false),
    ARABIC("ar", "العربية", true),
    KOREAN("ko", "한국어", false)
}

data class RegionSettingsState(
    val selectedRegion: AppRegion = AppRegion.UAE,
    val selectedLanguage: AppLanguage = AppLanguage.ENGLISH,
    val hasSelectedRegion: Boolean = false
)

@Singleton
class RegionSettingsManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    private val _state = MutableStateFlow(loadState())
    val state: StateFlow<RegionSettingsState> = _state.asStateFlow()

    fun initialize() {
        applyLanguage(_state.value.selectedLanguage)
    }

    fun updateRegion(region: AppRegion) {
        preferences.edit()
            .putString(REGION_KEY, region.name)
            .putBoolean(HAS_SELECTED_REGION_KEY, true)
            .apply()
        _state.value = _state.value.copy(
            selectedRegion = region,
            hasSelectedRegion = true
        )
    }

    fun updateLanguage(language: AppLanguage) {
        preferences.edit()
            .putString(LANGUAGE_KEY, language.name)
            .apply()
        applyLanguage(language)
        _state.value = _state.value.copy(selectedLanguage = language)
    }

    fun formatCurrency(value: BigDecimal?): String {
        return value?.let { formatterFor(_state.value.selectedRegion, _state.value.selectedRegion.currencyDecimals).format(it) } ?: "-"
    }

    fun formatCurrencyCompact(value: BigDecimal?): String {
        return value?.let { formatterFor(_state.value.selectedRegion, 0).format(it) } ?: "-"
    }

    fun formatMileage(valueInKilometers: Int): String {
        val displayValue = displayMileageFromKilometers(valueInKilometers)
        val unit = if (_state.value.selectedRegion.usesKilometers) "km" else "mi"
        return "${numberFormatterFor(_state.value.selectedRegion).format(displayValue)} $unit"
    }

    fun mileageInputLabel(): String {
        return if (_state.value.selectedRegion.usesKilometers) "Mileage (km)" else "Mileage (mi)"
    }

    fun displayMileageFromKilometers(valueInKilometers: Int): Int {
        return if (_state.value.selectedRegion.usesKilometers) {
            valueInKilometers
        } else {
            (valueInKilometers * KILOMETERS_TO_MILES).roundToInt()
        }
    }

    fun kilometersFromInput(inputValue: Int): Int {
        return if (_state.value.selectedRegion.usesKilometers) {
            inputValue
        } else {
            (inputValue / KILOMETERS_TO_MILES).roundToInt()
        }
    }

    private fun loadState(): RegionSettingsState {
        val storedRegion = preferences.getString(REGION_KEY, null)
            ?.let { runCatching { AppRegion.valueOf(it) }.getOrNull() }
            ?: AppRegion.UAE
        val storedLanguage = preferences.getString(LANGUAGE_KEY, null)
            ?.let { runCatching { AppLanguage.valueOf(it) }.getOrNull() }
            ?: AppLanguage.ENGLISH
        val hasSelectedRegion = preferences.getBoolean(HAS_SELECTED_REGION_KEY, false)
        return RegionSettingsState(
            selectedRegion = storedRegion,
            selectedLanguage = storedLanguage,
            hasSelectedRegion = hasSelectedRegion
        )
    }

    private fun applyLanguage(language: AppLanguage) {
        AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(language.tag))
    }

    private fun formatterFor(region: AppRegion, fractionDigits: Int): NumberFormat {
        return (NumberFormat.getCurrencyInstance(region.locale) as DecimalFormat).apply {
            currency = Currency.getInstance(region.currencyCode)
            decimalFormatSymbols = decimalFormatSymbols.apply {
                currencySymbol = "${region.currencySymbol} "
            }
            maximumFractionDigits = fractionDigits
            minimumFractionDigits = fractionDigits
        }
    }

    private fun numberFormatterFor(region: AppRegion): NumberFormat {
        return NumberFormat.getIntegerInstance(region.locale)
    }

    private companion object {
        private const val PREFERENCES_NAME = "ezcar24_region_settings"
        private const val REGION_KEY = "app_selected_region"
        private const val LANGUAGE_KEY = "app_selected_language"
        private const val HAS_SELECTED_REGION_KEY = "app_has_selected_region"
        private const val KILOMETERS_TO_MILES = 0.621371
    }
}

@EntryPoint
@InstallIn(SingletonComponent::class)
interface RegionSettingsEntryPoint {
    fun regionSettingsManager(): RegionSettingsManager
}

@Composable
fun rememberRegionSettingsManager(): RegionSettingsManager {
    val applicationContext = LocalContext.current.applicationContext
    return remember(applicationContext) {
        EntryPointAccessors.fromApplication(
            applicationContext,
            RegionSettingsEntryPoint::class.java
        ).regionSettingsManager()
    }
}
