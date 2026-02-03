package com.ezcar24.business.util.calculator

import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.ExpenseCategoryType
import com.ezcar24.business.data.local.HoldingCostSettings
import com.ezcar24.business.data.local.Vehicle
import org.junit.Assert.assertEquals
import org.junit.Test
import java.math.BigDecimal
import java.util.Date
import java.util.UUID
import java.util.Calendar

class HoldingCostCalculatorTest {

    private fun createVehicle(
        purchasePrice: BigDecimal = BigDecimal("50000.00"),
        purchaseDate: Date = Date()
    ): Vehicle {
        return Vehicle(
            id = UUID.randomUUID(),
            vin = "TEST123",
            make = "Toyota",
            model = "Camry",
            year = 2023,
            purchasePrice = purchasePrice,
            purchaseDate = purchaseDate,
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
        expenseType: ExpenseCategoryType = ExpenseCategoryType.IMPROVEMENT,
        vehicleId: UUID? = null
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
            vehicleId = vehicleId,
            userId = null,
            accountId = null,
            expenseType = expenseType
        )
    }

    private fun createSettings(
        annualRatePercent: BigDecimal = BigDecimal("15.00"),
        isEnabled: Boolean = true
    ): HoldingCostSettings {
        return HoldingCostSettings(
            id = UUID.randomUUID(),
            dealerId = UUID.randomUUID(),
            annualRatePercent = annualRatePercent,
            isEnabled = isEnabled,
            createdAt = Date(),
            updatedAt = null
        )
    }

    private fun dateDaysAgo(days: Int): Date {
        val calendar = Calendar.getInstance()
        calendar.add(Calendar.DAY_OF_YEAR, -days)
        return calendar.time
    }

    @Test
    fun `calculateDaysInInventory returns correct days`() {
        val vehicle = createVehicle(purchaseDate = dateDaysAgo(45))
        val days = HoldingCostCalculator.calculateDaysInInventory(vehicle)
        assertEquals(45, days)
    }

    @Test
    fun `calculateDaysInInventory returns 0 for future purchase date`() {
        val calendar = Calendar.getInstance()
        calendar.add(Calendar.DAY_OF_YEAR, 5)
        val vehicle = createVehicle(purchaseDate = calendar.time)
        val days = HoldingCostCalculator.calculateDaysInInventory(vehicle)
        assertEquals(0, days)
    }

    @Test
    fun `calculateDaysInInventory uses saleDate when available`() {
        val purchaseDate = dateDaysAgo(100)
        val saleDate = dateDaysAgo(30)
        val vehicle = createVehicle(purchaseDate = purchaseDate).copy(saleDate = saleDate)
        val days = HoldingCostCalculator.calculateDaysInInventory(vehicle)
        assertEquals(70, days)
    }

    @Test
    fun `getImprovementExpenses filters only improvement type`() {
        val vehicleId = UUID.randomUUID()
        val expenses = listOf(
            createExpense(expenseType = ExpenseCategoryType.IMPROVEMENT, vehicleId = vehicleId),
            createExpense(expenseType = ExpenseCategoryType.IMPROVEMENT, vehicleId = vehicleId),
            createExpense(expenseType = ExpenseCategoryType.HOLDING_COST, vehicleId = vehicleId),
            createExpense(expenseType = ExpenseCategoryType.OPERATIONAL, vehicleId = vehicleId)
        )
        val improvements = HoldingCostCalculator.getImprovementExpenses(expenses)
        assertEquals(2, improvements.size)
    }

    @Test
    fun `getImprovementExpenses excludes deleted expenses`() {
        val vehicleId = UUID.randomUUID()
        val expenses = listOf(
            createExpense(expenseType = ExpenseCategoryType.IMPROVEMENT, vehicleId = vehicleId),
            createExpense(expenseType = ExpenseCategoryType.IMPROVEMENT, vehicleId = vehicleId).copy(
                deletedAt = Date()
            )
        )
        val improvements = HoldingCostCalculator.getImprovementExpenses(expenses)
        assertEquals(1, improvements.size)
    }

    @Test
    fun `getCapitalTiedUp sums purchase price and improvements`() {
        val vehicle = createVehicle(purchasePrice = BigDecimal("50000.00"))
        val improvements = listOf(
            createExpense(amount = BigDecimal("2000.00")),
            createExpense(amount = BigDecimal("1500.00"))
        )
        val capital = HoldingCostCalculator.getCapitalTiedUp(vehicle, improvements)
        assertEquals(BigDecimal("53500.0000"), capital)
    }

    @Test
    fun `calculateDailyHoldingCost returns zero when disabled`() {
        val vehicle = createVehicle()
        val settings = createSettings(isEnabled = false)
        val improvements = emptyList<Expense>()
        val dailyCost = HoldingCostCalculator.calculateDailyHoldingCost(vehicle, settings, improvements)
        assertEquals(BigDecimal.ZERO.setScale(2), dailyCost)
    }

    @Test
    fun `calculateDailyHoldingCost calculates correctly`() {
        val vehicle = createVehicle(purchasePrice = BigDecimal("36500.00"))
        val settings = createSettings(annualRatePercent = BigDecimal("10.00"))
        val improvements = emptyList<Expense>()
        val dailyCost = HoldingCostCalculator.calculateDailyHoldingCost(vehicle, settings, improvements)
        // 36500 * 0.10 / 365 = 10.00
        assertEquals(BigDecimal("10.00"), dailyCost)
    }

    @Test
    fun `calculateAccumulatedHoldingCost returns zero when disabled`() {
        val vehicle = createVehicle(purchaseDate = dateDaysAgo(30))
        val settings = createSettings(isEnabled = false)
        val expenses = emptyList<Expense>()
        val accumulatedCost = HoldingCostCalculator.calculateAccumulatedHoldingCost(
            vehicle, settings, expenses
        )
        assertEquals(BigDecimal.ZERO.setScale(2), accumulatedCost)
    }

    @Test
    fun `calculateAccumulatedHoldingCost calculates correctly`() {
        val vehicle = createVehicle(purchasePrice = BigDecimal("36500.00"), purchaseDate = dateDaysAgo(30))
        val settings = createSettings(annualRatePercent = BigDecimal("10.00"))
        val expenses = emptyList<Expense>()
        val accumulatedCost = HoldingCostCalculator.calculateAccumulatedHoldingCost(
            vehicle, settings, expenses
        )
        // Daily cost = 10.00, 30 days = 300.00
        assertEquals(BigDecimal("300.00"), accumulatedCost)
    }

    @Test
    fun `calculateAccumulatedHoldingCost includes improvement expenses`() {
        val vehicle = createVehicle(purchasePrice = BigDecimal("36500.00"), purchaseDate = dateDaysAgo(30))
        val settings = createSettings(annualRatePercent = BigDecimal("10.00"))
        val expenses = listOf(
            createExpense(amount = BigDecimal("3650.00"), expenseType = ExpenseCategoryType.IMPROVEMENT)
        )
        val accumulatedCost = HoldingCostCalculator.calculateAccumulatedHoldingCost(
            vehicle, settings, expenses
        )
        // Capital = 40150, Daily cost = 11.00, 30 days = 330.00
        assertEquals(BigDecimal("330.00"), accumulatedCost)
    }

    @Test
    fun `calculateDailyRateFromAnnual converts correctly`() {
        val annualRate = BigDecimal("15.00")
        val dailyRate = HoldingCostCalculator.calculateDailyRateFromAnnual(annualRate)
        // 15% / 365 = 0.04109589% daily
        assertEquals(BigDecimal("0.00041096"), dailyRate)
    }

    @Test
    fun `calculateAnnualRateFromDaily converts correctly`() {
        val dailyRate = BigDecimal("0.0004109589")
        val annualRate = HoldingCostCalculator.calculateAnnualRateFromDaily(dailyRate)
        assertEquals(BigDecimal("15.0000"), annualRate)
    }
}
