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
}
