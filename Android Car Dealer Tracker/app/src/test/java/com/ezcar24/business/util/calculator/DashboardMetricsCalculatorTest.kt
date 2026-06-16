package com.ezcar24.business.util.calculator

import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.ExpenseCategoryType
import com.ezcar24.business.data.local.HoldingCostSettings
import com.ezcar24.business.data.local.PartSale
import com.ezcar24.business.data.local.PartSaleLineItem
import com.ezcar24.business.data.local.Sale
import com.ezcar24.business.data.local.Vehicle
import org.junit.Assert.assertEquals
import org.junit.Test
import java.math.BigDecimal
import java.util.Date
import java.util.UUID
import java.util.concurrent.TimeUnit

class DashboardMetricsCalculatorTest {

    @Test
    fun `calculateTotalRevenue includes vehicle and part sales only`() {
        val activeSale = createSale(amount = BigDecimal("1000.00"))
        val deletedSale = createSale(amount = BigDecimal("9000.00")).copy(deletedAt = Date())
        val activePartSale = createPartSale(amount = BigDecimal("250.00"))
        val deletedPartSale = createPartSale(amount = BigDecimal("750.00")).copy(deletedAt = Date())

        val revenue = DashboardMetricsCalculator.calculateTotalRevenue(
            sales = listOf(activeSale, deletedSale),
            partSales = listOf(activePartSale, deletedPartSale)
        )

        assertEquals(BigDecimal("1250.00"), revenue)
    }

    @Test
    fun `calculateSalesProfit matches iOS combined vehicle and parts formula`() {
        val vehicleId = UUID.randomUUID()
        val saleId = UUID.randomUUID()
        val partSaleId = UUID.randomUUID()
        val purchaseDate = Date(1_700_000_000_000)
        val saleDate = Date(purchaseDate.time + TimeUnit.DAYS.toMillis(10))
        val vehicle = createVehicle(
            id = vehicleId,
            purchasePrice = BigDecimal("10000.00"),
            purchaseDate = purchaseDate
        )
        val sale = createSale(
            id = saleId,
            amount = BigDecimal("15000.00"),
            vehicleId = vehicleId,
            date = saleDate,
            vatRefundAmount = BigDecimal("200.00")
        )
        val expense = createExpense(
            amount = BigDecimal("500.00"),
            vehicleId = vehicleId,
            expenseType = ExpenseCategoryType.HOLDING_COST
        )
        val partSale = createPartSale(id = partSaleId, amount = BigDecimal("800.00"))
        val partLineItem = createPartSaleLineItem(
            saleId = partSaleId,
            quantity = BigDecimal("2.00"),
            unitCost = BigDecimal("100.00")
        )
        val settings = createHoldingSettings(annualRatePercent = BigDecimal("36.50"))

        val profit = DashboardMetricsCalculator.calculateSalesProfit(
            sales = listOf(sale),
            vehicles = listOf(vehicle),
            allExpenses = listOf(expense),
            partSales = listOf(partSale),
            partSaleLineItems = listOf(partLineItem),
            holdingCostSettings = settings
        )

        assertEquals(0, BigDecimal("5200.00").compareTo(profit))
    }

    private fun createVehicle(
        id: UUID = UUID.randomUUID(),
        purchasePrice: BigDecimal = BigDecimal("10000.00"),
        purchaseDate: Date = Date()
    ): Vehicle {
        return Vehicle(
            id = id,
            vin = "TESTVIN",
            make = "Toyota",
            model = "Camry",
            year = 2023,
            purchasePrice = purchasePrice,
            purchaseDate = purchaseDate,
            status = "sold",
            notes = null,
            createdAt = Date(),
            updatedAt = null,
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

    private fun createSale(
        id: UUID = UUID.randomUUID(),
        amount: BigDecimal = BigDecimal("1000.00"),
        vehicleId: UUID? = UUID.randomUUID(),
        date: Date = Date(),
        vatRefundAmount: BigDecimal? = null
    ): Sale {
        return Sale(
            id = id,
            amount = amount,
            date = date,
            buyerName = "Buyer",
            buyerPhone = "+10000000000",
            paymentMethod = "Cash",
            createdAt = Date(),
            updatedAt = null,
            deletedAt = null,
            vehicleId = vehicleId,
            accountId = null,
            vatRefundPercent = null,
            vatRefundAmount = vatRefundAmount
        )
    }

    private fun createExpense(
        amount: BigDecimal,
        vehicleId: UUID,
        expenseType: ExpenseCategoryType
    ): Expense {
        return Expense(
            id = UUID.randomUUID(),
            amount = amount,
            date = Date(),
            expenseDescription = "Expense",
            category = "General",
            createdAt = Date(),
            updatedAt = null,
            deletedAt = null,
            vehicleId = vehicleId,
            userId = null,
            accountId = null,
            expenseType = expenseType
        )
    }

    private fun createPartSale(
        id: UUID = UUID.randomUUID(),
        amount: BigDecimal = BigDecimal("800.00")
    ): PartSale {
        return PartSale(
            id = id,
            amount = amount,
            date = Date(),
            buyerName = "Parts Buyer",
            buyerPhone = "+10000000000",
            paymentMethod = "Cash",
            accountId = null,
            notes = null,
            createdAt = Date(),
            updatedAt = null,
            deletedAt = null
        )
    }

    private fun createPartSaleLineItem(
        saleId: UUID,
        quantity: BigDecimal,
        unitCost: BigDecimal
    ): PartSaleLineItem {
        return PartSaleLineItem(
            id = UUID.randomUUID(),
            saleId = saleId,
            partId = UUID.randomUUID(),
            batchId = UUID.randomUUID(),
            quantity = quantity,
            unitPrice = BigDecimal.ZERO,
            unitCost = unitCost,
            createdAt = Date(),
            updatedAt = null,
            deletedAt = null
        )
    }

    private fun createHoldingSettings(
        annualRatePercent: BigDecimal
    ): HoldingCostSettings {
        return HoldingCostSettings(
            id = UUID.randomUUID(),
            dealerId = UUID.randomUUID(),
            annualRatePercent = annualRatePercent,
            isEnabled = true,
            createdAt = Date(),
            updatedAt = null
        )
    }
}
