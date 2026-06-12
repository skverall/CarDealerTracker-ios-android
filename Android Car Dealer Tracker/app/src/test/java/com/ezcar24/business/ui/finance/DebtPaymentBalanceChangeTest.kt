package com.ezcar24.business.ui.finance

import org.junit.Assert.assertEquals
import org.junit.Test
import java.math.BigDecimal

class DebtPaymentBalanceChangeTest {
    @Test
    fun `owed to me payment increases account balance and deletion reverses it`() {
        val amount = BigDecimal("250.00")

        assertEquals(BigDecimal("250.00"), debtPaymentBalanceChange(amount, "owed_to_me"))
        assertEquals(BigDecimal("-250.00"), debtPaymentDeletionBalanceChange(amount, "owed_to_me"))
    }

    @Test
    fun `i owe payment decreases account balance and deletion reverses it`() {
        val amount = BigDecimal("250.00")

        assertEquals(BigDecimal("-250.00"), debtPaymentBalanceChange(amount, "i_owe"))
        assertEquals(BigDecimal("250.00"), debtPaymentDeletionBalanceChange(amount, "i_owe"))
    }
}
