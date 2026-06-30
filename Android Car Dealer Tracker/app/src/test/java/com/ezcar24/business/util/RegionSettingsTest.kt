package com.ezcar24.business.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class RegionSettingsTest {
    @Test
    fun `japan region uses yen and japanese locale`() {
        assertEquals("JPY", AppRegion.JAPAN.currencyCode)
        assertEquals("¥", AppRegion.JAPAN.currencySymbol)
        assertEquals("ja-JP", AppRegion.JAPAN.localeTag)
        assertEquals(0, AppRegion.JAPAN.currencyDecimals)
    }

    @Test
    fun `japanese language option is available`() {
        assertEquals("ja", AppLanguage.JAPANESE.tag)
        assertEquals("日本語", AppLanguage.JAPANESE.nativeName)
        assertFalse(AppLanguage.JAPANESE.isRtl)
    }

    @Test
    fun `uzbek latin language option is available`() {
        assertEquals("uz", AppLanguage.UZBEK.tag)
        assertEquals("Oʻzbekcha", AppLanguage.UZBEK.nativeName)
        assertEquals("🇺🇿", AppLanguage.UZBEK.listIcon)
        assertFalse(AppLanguage.UZBEK.isRtl)
    }

    @Test
    fun `uzbekistan region uses uzs without decimals`() {
        assertEquals("UZS", AppRegion.UZBEKISTAN.currencyCode)
        assertEquals("soʻm", AppRegion.UZBEKISTAN.currencySymbol)
        assertEquals("uz-UZ", AppRegion.UZBEKISTAN.localeTag)
        assertEquals(0, AppRegion.UZBEKISTAN.currencyDecimals)
    }

    @Test
    fun `indonesia region uses rupiah and indonesian locale`() {
        assertEquals("IDR", AppRegion.INDONESIA.currencyCode)
        assertEquals("Rp", AppRegion.INDONESIA.currencySymbol)
        assertEquals("id-ID", AppRegion.INDONESIA.localeTag)
        assertEquals(0, AppRegion.INDONESIA.currencyDecimals)
    }

    @Test
    fun `south africa region uses rand and south african locale`() {
        assertEquals("ZAR", AppRegion.SOUTH_AFRICA.currencyCode)
        assertEquals("R", AppRegion.SOUTH_AFRICA.currencySymbol)
        assertEquals("en-ZA", AppRegion.SOUTH_AFRICA.localeTag)
        assertEquals(2, AppRegion.SOUTH_AFRICA.currencyDecimals)
    }

    @Test
    fun `indonesian language option is available`() {
        assertEquals("id", AppLanguage.INDONESIAN.tag)
        assertEquals("Bahasa Indonesia", AppLanguage.INDONESIAN.nativeName)
        assertFalse(AppLanguage.INDONESIAN.isRtl)
    }

    @Test
    fun `hindi language option matches ios selectable language`() {
        assertEquals("hi", AppLanguage.HINDI.tag)
        assertEquals("हिन्दी", AppLanguage.HINDI.nativeName)
        assertEquals("🇮🇳", AppLanguage.HINDI.listIcon)
        assertFalse(AppLanguage.HINDI.isRtl)
    }
}
