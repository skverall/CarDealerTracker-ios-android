package com.ezcar24.business.ui.sale

import org.junit.Assert.assertEquals
import org.junit.Test
import java.math.BigDecimal

class SaleBalanceChangeTest {
    @Test
    fun `sale adds amount to account and deletion reverses it`() {
        val amount = BigDecimal("9000.00")

        assertEquals(BigDecimal("9000.00"), saleAccountBalanceChange(amount))
        assertEquals(BigDecimal("-9000.00"), saleDeletionAccountBalanceChange(amount))
    }

    @Test
    fun `missing sale amount does not change account balance`() {
        assertEquals(BigDecimal.ZERO, saleAccountBalanceChange(null))
        assertEquals(BigDecimal.ZERO, saleDeletionAccountBalanceChange(null))
    }

    @Test
    fun `sale preview uses purchase price plus expenses for total cost`() {
        val totalCost = saleTotalCost(
            purchasePrice = BigDecimal("12000.00"),
            expenseAmounts = listOf(BigDecimal("700.50"), BigDecimal("299.50"))
        )

        assertEquals(BigDecimal("13000.00"), totalCost)
        assertEquals(BigDecimal("2500.00"), saleEstimatedProfit(BigDecimal("15500.00"), totalCost))
    }

    @Test
    fun `sale preview treats missing sale price as zero`() {
        assertEquals(BigDecimal("-13000.00"), saleEstimatedProfit(null, BigDecimal("13000.00")))
    }
}
