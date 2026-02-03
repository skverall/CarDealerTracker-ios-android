package com.ezcar24.business.util.calculator

import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.ExpenseCategoryType
import com.ezcar24.business.data.local.Vehicle
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigDecimal
import java.util.Date
import java.util.UUID

class VehicleFinancialsCalculatorTest {

    private fun createVehicle(purchasePrice: BigDecimal = BigDecimal("50000.00")): Vehicle {
        return Vehicle(
            id = UUID.randomUUID(),
            vin = "TEST123",
            make = "Toyota",
            model = "Camry",
            year = 2023,
            purchasePrice = purchasePrice,
            purchaseDate = Date(),
            status = "owned",
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

    private fun createExpense(
        amount: BigDecimal = BigDecimal("1000.00"),
        expenseType: ExpenseCategoryType = ExpenseCategoryType.HOLDING_COST
    ): Expense {
        return Expense(
            id = UUID.randomUUID(),
            amount = amount,
            date = Date(),
            expenseDescription = "Test expense",
            category = "test",
            createdAt = Date(),
            updatedAt = null,
            deletedAt = null,
            vehicleId = UUID.randomUUID(),
            userId = null,
            accountId = null,
            expenseType = expenseType
        )
    }

    @Test
    fun `calculateTotalCost sums purchase price expenses and holding cost`() {
        val vehicle = createVehicle(purchasePrice = BigDecimal("50000.00"))
        val expenses = listOf(
            createExpense(amount = BigDecimal("2000.00")),
            createExpense(amount = BigDecimal("1500.00"))
        )
        val holdingCost = BigDecimal("500.00")
        val totalCost = VehicleFinancialsCalculator.calculateTotalCost(vehicle, expenses, holdingCost)
        assertEquals(BigDecimal("54000.00"), totalCost)
    }

    @Test
    fun `calculateTotalCost handles empty expenses`() {
        val vehicle = createVehicle(purchasePrice = BigDecimal("50000.00"))
        val expenses = emptyList<Expense>()
        val holdingCost = BigDecimal("0.00")
        val totalCost = VehicleFinancialsCalculator.calculateTotalCost(vehicle, expenses, holdingCost)
        assertEquals(BigDecimal("50000.00"), totalCost)
    }

    @Test
    fun `calculateTotalCost excludes deleted expenses`() {
        val vehicle = createVehicle(purchasePrice = BigDecimal("50000.00"))
        val expenses = listOf(
            createExpense(amount = BigDecimal("2000.00")),
            createExpense(amount = BigDecimal("1500.00")).copy(deletedAt = Date())
        )
        val holdingCost = BigDecimal("0.00")
        val totalCost = VehicleFinancialsCalculator.calculateTotalCost(vehicle, expenses, holdingCost)
        assertEquals(BigDecimal("52000.00"), totalCost)
    }

    @Test
    fun `calculateROI returns correct percentage`() {
        val salePrice = BigDecimal("60000.00")
        val totalCost = BigDecimal("50000.00")
        val roi = VehicleFinancialsCalculator.calculateROI(salePrice, totalCost)
        assertEquals(BigDecimal("20.00"), roi)
    }

    @Test
    fun `calculateROI returns null for zero total cost`() {
        val salePrice = BigDecimal("60000.00")
        val totalCost = BigDecimal.ZERO
        val roi = VehicleFinancialsCalculator.calculateROI(salePrice, totalCost)
        assertNull(roi)
    }

    @Test
    fun `calculateROI returns negative for loss`() {
        val salePrice = BigDecimal("40000.00")
        val totalCost = BigDecimal("50000.00")
        val roi = VehicleFinancialsCalculator.calculateROI(salePrice, totalCost)
        assertEquals(BigDecimal("-20.00"), roi)
    }

    @Test
    fun `calculateProfitEstimate returns correct amount`() {
        val askingPrice = BigDecimal("60000.00")
        val totalCost = BigDecimal("50000.00")
        val profit = VehicleFinancialsCalculator.calculateProfitEstimate(askingPrice, totalCost)
        assertEquals(BigDecimal("10000.00"), profit)
    }

    @Test
    fun `calculateActualProfit returns correct amount`() {
        val salePrice = BigDecimal("60000.00")
        val totalCost = BigDecimal("50000.00")
        val profit = VehicleFinancialsCalculator.calculateActualProfit(salePrice, totalCost)
        assertEquals(BigDecimal("10000.00"), profit)
    }

    @Test
    fun `calculateHoldingCostPercentage returns correct percentage`() {
        val holdingCost = BigDecimal("5000.00")
        val totalCost = BigDecimal("50000.00")
        val percentage = VehicleFinancialsCalculator.calculateHoldingCostPercentage(holdingCost, totalCost)
        assertEquals(BigDecimal("10.00"), percentage)
    }

    @Test
    fun `calculateHoldingCostPercentage returns null for zero total cost`() {
        val holdingCost = BigDecimal("5000.00")
        val totalCost = BigDecimal.ZERO
        val percentage = VehicleFinancialsCalculator.calculateHoldingCostPercentage(holdingCost, totalCost)
        assertNull(percentage)
    }

    @Test
    fun `calculateExpenseBreakdown groups by type`() {
        val expenses = listOf(
            createExpense(amount = BigDecimal("1000.00"), expenseType = ExpenseCategoryType.HOLDING_COST),
            createExpense(amount = BigDecimal("2000.00"), expenseType = ExpenseCategoryType.HOLDING_COST),
            createExpense(amount = BigDecimal("1500.00"), expenseType = ExpenseCategoryType.IMPROVEMENT),
            createExpense(amount = BigDecimal("500.00"), expenseType = ExpenseCategoryType.OPERATIONAL)
        )
        val breakdown = VehicleFinancialsCalculator.calculateExpenseBreakdown(expenses)
        assertEquals(BigDecimal("3000.00"), breakdown[ExpenseCategoryType.HOLDING_COST])
        assertEquals(BigDecimal("1500.00"), breakdown[ExpenseCategoryType.IMPROVEMENT])
        assertEquals(BigDecimal("500.00"), breakdown[ExpenseCategoryType.OPERATIONAL])
    }

    @Test
    fun `calculateBreakEvenPrice returns total cost for zero target ROI`() {
        val vehicle = createVehicle(purchasePrice = BigDecimal("50000.00"))
        val expenses = listOf(createExpense(amount = BigDecimal("5000.00")))
        val holdingCost = BigDecimal("500.00")
        val breakEven = VehicleFinancialsCalculator.calculateBreakEvenPrice(vehicle, expenses, holdingCost, BigDecimal.ZERO)
        assertEquals(BigDecimal("55500.00"), breakEven)
    }

    @Test
    fun `calculateBreakEvenPrice includes target ROI`() {
        val vehicle = createVehicle(purchasePrice = BigDecimal("50000.00"))
        val expenses = emptyList<Expense>()
        val holdingCost = BigDecimal("0.00")
        val breakEven = VehicleFinancialsCalculator.calculateBreakEvenPrice(
            vehicle, expenses, holdingCost, BigDecimal("20.00")
        )
        // 50000 * 1.20 = 60000
        assertEquals(BigDecimal("60000.00"), breakEven)
    }

    @Test
    fun `calculateRecommendedAskingPrice uses 20 percent default ROI`() {
        val vehicle = createVehicle(purchasePrice = BigDecimal("50000.00"))
        val expenses = emptyList<Expense>()
        val holdingCost = BigDecimal("0.00")
        val recommendedPrice = VehicleFinancialsCalculator.calculateRecommendedAskingPrice(
            vehicle, expenses, holdingCost
        )
        assertEquals(BigDecimal("60000.00"), recommendedPrice)
    }

    @Test
    fun `isProfitable returns true when sale price exceeds total cost`() {
        assertTrue(VehicleFinancialsCalculator.isProfitable(BigDecimal("60000"), BigDecimal("50000")))
    }

    @Test
    fun `isProfitable returns false when sale price equals total cost`() {
        assertFalse(VehicleFinancialsCalculator.isProfitable(BigDecimal("50000"), BigDecimal("50000")))
    }

    @Test
    fun `isProfitable returns false when sale price is less than total cost`() {
        assertFalse(VehicleFinancialsCalculator.isProfitable(BigDecimal("40000"), BigDecimal("50000")))
    }

    @Test
    fun `getProfitStatus returns LOSS for negative profit`() {
        val status = VehicleFinancialsCalculator.getProfitStatus(BigDecimal("40000"), BigDecimal("50000"))
        assertEquals(VehicleFinancialsCalculator.ProfitStatus.LOSS, status)
    }

    @Test
    fun `getProfitStatus returns BREAK_EVEN for zero profit`() {
        val status = VehicleFinancialsCalculator.getProfitStatus(BigDecimal("50000"), BigDecimal("50000"))
        assertEquals(VehicleFinancialsCalculator.ProfitStatus.BREAK_EVEN, status)
    }

    @Test
    fun `getProfitStatus returns PROFIT for positive ROI below 20 percent`() {
        val status = VehicleFinancialsCalculator.getProfitStatus(BigDecimal("55000"), BigDecimal("50000"))
        assertEquals(VehicleFinancialsCalculator.ProfitStatus.PROFIT, status)
    }

    @Test
    fun `getProfitStatus returns HIGH_PROFIT for ROI at or above 20 percent`() {
        val status = VehicleFinancialsCalculator.getProfitStatus(BigDecimal("60000"), BigDecimal("50000"))
        assertEquals(VehicleFinancialsCalculator.ProfitStatus.HIGH_PROFIT, status)
    }
}
