package com.ezcar24.business

import com.ezcar24.business.util.FinancialAccountKind
import com.ezcar24.business.util.composeFinancialAccountType
import com.ezcar24.business.util.financialAccountDisplayTitle
import com.ezcar24.business.util.financialAccountKindFor
import com.ezcar24.business.util.financialAccountShortTitle
import com.ezcar24.business.util.financialAccountSubtitleTitle
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FinancialAccountKindTest {
    @Test
    fun parsesIosAccountKindsAndPrefixes() {
        assertEquals(FinancialAccountKind.CASH, financialAccountKindFor("Cash"))
        assertEquals(FinancialAccountKind.BANK, financialAccountKindFor("Bank - Main"))
        assertEquals(FinancialAccountKind.CREDIT_CARD, financialAccountKindFor("Credit"))
        assertEquals(FinancialAccountKind.CREDIT_CARD, financialAccountKindFor("Credit Card"))
        assertEquals(FinancialAccountKind.CREDIT_CARD, financialAccountKindFor("Credit Card - Visa"))
        assertEquals(FinancialAccountKind.OTHER, financialAccountKindFor("Wallet"))
    }

    @Test
    fun composesIosCompatibleAccountTypes() {
        assertEquals("Cash", composeFinancialAccountType(FinancialAccountKind.CASH, null))
        assertEquals("Bank - Main", composeFinancialAccountType(FinancialAccountKind.BANK, "Main"))
        assertEquals("Credit Card - Visa", composeFinancialAccountType(FinancialAccountKind.CREDIT_CARD, "Visa"))
        assertEquals("Wallet", composeFinancialAccountType(FinancialAccountKind.OTHER, "Wallet"))
    }

    @Test
    fun derivesIosStyleDisplayTitles() {
        assertEquals("Bank - Main", financialAccountDisplayTitle("Bank - Main"))
        assertEquals("Main", financialAccountShortTitle("Bank - Main"))
        assertEquals("Bank", financialAccountSubtitleTitle("Bank - Main"))
        assertEquals("Wallet", financialAccountShortTitle("Wallet"))
        assertNull(financialAccountSubtitleTitle("Wallet"))
    }
}
