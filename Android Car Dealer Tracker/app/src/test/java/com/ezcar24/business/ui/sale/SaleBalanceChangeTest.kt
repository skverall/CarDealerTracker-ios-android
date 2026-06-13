package com.ezcar24.business.ui.sale

import com.ezcar24.business.data.local.Vehicle
import org.junit.Assert.assertEquals
import org.junit.Test
import java.math.BigDecimal
import java.util.Date
import java.util.UUID

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

    @Test
    fun `sale client crm text uses vehicle title and sale amount`() {
        val vehicle = testSaleVehicle(
            year = 2024,
            make = "Toyota",
            model = "Camry",
            vin = "JTDBCMFE7R3000001"
        )

        assertEquals("Purchased 2024 Toyota Camry", saleClientPurchaseNote(vehicle))
        assertEquals(
            "Purchased 2024 Toyota Camry for 17500",
            saleClientInteractionDetail(vehicle, BigDecimal("17500.00"))
        )
    }

    @Test
    fun `sale client crm text falls back to vin when title is missing`() {
        val vehicle = testSaleVehicle(
            year = null,
            make = null,
            model = null,
            vin = "NO-TITLE-VIN"
        )

        assertEquals("Purchased NO-TITLE-VIN", saleClientPurchaseNote(vehicle))
    }

    private fun testSaleVehicle(
        year: Int?,
        make: String?,
        model: String?,
        vin: String
    ): Vehicle {
        val now = Date()
        return Vehicle(
            id = UUID.randomUUID(),
            vin = vin,
            make = make,
            model = model,
            year = year,
            mileage = 0,
            purchasePrice = BigDecimal("10000.00"),
            purchaseDate = now,
            status = "owned",
            notes = null,
            createdAt = now,
            updatedAt = now,
            deletedAt = null,
            saleDate = null,
            buyerName = null,
            buyerPhone = null,
            paymentMethod = null,
            salePrice = null,
            askingPrice = null,
            reportURL = null,
            photoUrl = null
        )
    }
}
