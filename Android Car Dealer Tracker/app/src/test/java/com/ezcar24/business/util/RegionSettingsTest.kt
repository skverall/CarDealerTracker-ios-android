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
        assertFalse(AppLanguage.UZBEK.isRtl)
    }

    @Test
    fun `indonesia region uses rupiah and indonesian locale`() {
        assertEquals("IDR", AppRegion.INDONESIA.currencyCode)
        assertEquals("Rp", AppRegion.INDONESIA.currencySymbol)
        assertEquals("id-ID", AppRegion.INDONESIA.localeTag)
        assertEquals(0, AppRegion.INDONESIA.currencyDecimals)
    }

    @Test
    fun `indonesian language option is available`() {
        assertEquals("id", AppLanguage.INDONESIAN.tag)
        assertEquals("Bahasa Indonesia", AppLanguage.INDONESIAN.nativeName)
        assertFalse(AppLanguage.INDONESIAN.isRtl)
    }
}
