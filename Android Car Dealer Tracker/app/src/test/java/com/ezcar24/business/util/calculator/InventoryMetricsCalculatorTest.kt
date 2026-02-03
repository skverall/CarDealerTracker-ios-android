package com.ezcar24.business.util.calculator

import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.ExpenseCategoryType
import com.ezcar24.business.data.local.HoldingCostSettings
import com.ezcar24.business.data.local.InventoryAlertType
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.data.local.VehicleInventoryStats
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigDecimal
import java.util.Calendar
import java.util.Date
import java.util.UUID

class InventoryMetricsCalculatorTest {

    private fun createVehicle(
        purchasePrice: BigDecimal = BigDecimal("50000.00"),
        purchaseDate: Date = Date(),
        salePrice: BigDecimal? = null,
        askingPrice: BigDecimal? = null,
        saleDate: Date? = null
    ): Vehicle {
        return Vehicle(
            id = UUID.randomUUID(),
            vin = "TEST123",
            make = "Toyota",
            model = "Camry",
            year = 2023,
            purchasePrice = purchasePrice,
            purchaseDate = purchaseDate,
            status = if (saleDate != null) "sold" else "owned",
            notes = null,
            createdAt = Date(),
            updatedAt = null,
            deletedAt = null,
            saleDate = saleDate,
            buyerName = null,
            buyerPhone = null,
            paymentMethod = null,
            salePrice = salePrice,
            askingPrice = askingPrice,
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
    fun `calculateAgingBucket returns 0-30 for 15 days`() {
        assertEquals("0-30", InventoryMetricsCalculator.calculateAgingBucket(15))
    }

    @Test
    fun `calculateAgingBucket returns 31-60 for 45 days`() {
        assertEquals("31-60", InventoryMetricsCalculator.calculateAgingBucket(45))
    }

    @Test
    fun `calculateAgingBucket returns 61-90 for 75 days`() {
        assertEquals("61-90", InventoryMetricsCalculator.calculateAgingBucket(75))
    }

    @Test
    fun `calculateAgingBucket returns 90+ for 100 days`() {
        assertEquals("90+", InventoryMetricsCalculator.calculateAgingBucket(100))
    }

    @Test
    fun `calculateAgingBucket handles boundary values`() {
        assertEquals("0-30", InventoryMetricsCalculator.calculateAgingBucket(0))
        assertEquals("0-30", InventoryMetricsCalculator.calculateAgingBucket(30))
        assertEquals("31-60", InventoryMetricsCalculator.calculateAgingBucket(31))
        assertEquals("31-60", InventoryMetricsCalculator.calculateAgingBucket(60))
        assertEquals("61-90", InventoryMetricsCalculator.calculateAgingBucket(61))
        assertEquals("61-90", InventoryMetricsCalculator.calculateAgingBucket(90))
        assertEquals("90+", InventoryMetricsCalculator.calculateAgingBucket(91))
    }

    @Test
    fun `calculateInventoryStats computes all fields correctly`() {
        val vehicle = createVehicle(
            purchasePrice = BigDecimal("36500.00"),
            purchaseDate = dateDaysAgo(30),
            askingPrice = BigDecimal("45000.00")
        )
        val expenses = listOf(
            createExpense(amount = BigDecimal("2000.00"), expenseType = ExpenseCategoryType.IMPROVEMENT),
            createExpense(amount = BigDecimal("1000.00"), expenseType = ExpenseCategoryType.HOLDING_COST)
        )
        val settings = createSettings(annualRatePercent = BigDecimal("10.00"))

        val stats = InventoryMetricsCalculator.calculateInventoryStats(vehicle, expenses, settings)

        assertEquals(vehicle.id, stats.vehicleId)
        assertEquals(30, stats.daysInInventory)
        assertEquals("0-30", stats.agingBucket)
        assertTrue(stats.totalCost.compareTo(BigDecimal.ZERO) > 0)
        assertTrue(stats.holdingCostAccumulated.compareTo(BigDecimal.ZERO) > 0)
        assertTrue(stats.profitEstimate != null)
    }

    @Test
    fun `calculateInventoryStats when disabled returns zero holding cost`() {
        val vehicle = createVehicle(
            purchasePrice = BigDecimal("36500.00"),
            purchaseDate = dateDaysAgo(30)
        )
        val expenses = emptyList<Expense>()
        val settings = createSettings(isEnabled = false)

        val stats = InventoryMetricsCalculator.calculateInventoryStats(vehicle, expenses, settings)

        assertEquals(BigDecimal.ZERO.setScale(2), stats.holdingCostAccumulated)
    }

    @Test
    fun `generateInventoryAlerts creates aging 90 days alert`() {
        val vehicle = createVehicle(purchaseDate = dateDaysAgo(95))
        val stats = VehicleInventoryStats(
            id = UUID.randomUUID(),
            vehicleId = vehicle.id,
            daysInInventory = 95,
            agingBucket = "90+",
            totalCost = BigDecimal("50000.00"),
            holdingCostAccumulated = BigDecimal("1000.00"),
            roiPercent = BigDecimal("15.00"),
            profitEstimate = BigDecimal("5000.00"),
            lastCalculatedAt = Date(),
            createdAt = Date(),
            updatedAt = Date()
        )

        val alerts = InventoryMetricsCalculator.generateInventoryAlerts(stats, vehicle)

        assertTrue(alerts.any { it.alertType == InventoryAlertType.aging_90_days })
        assertTrue(alerts.any { it.severity == "high" })
    }

    @Test
    fun `generateInventoryAlerts creates aging 60 days alert`() {
        val vehicle = createVehicle(purchaseDate = dateDaysAgo(65))
        val stats = VehicleInventoryStats(
            id = UUID.randomUUID(),
            vehicleId = vehicle.id,
            daysInInventory = 65,
            agingBucket = "61-90",
            totalCost = BigDecimal("50000.00"),
            holdingCostAccumulated = BigDecimal("1000.00"),
            roiPercent = BigDecimal("15.00"),
            profitEstimate = BigDecimal("5000.00"),
            lastCalculatedAt = Date(),
            createdAt = Date(),
            updatedAt = Date()
        )

        val alerts = InventoryMetricsCalculator.generateInventoryAlerts(stats, vehicle)

        assertTrue(alerts.any { it.alertType == InventoryAlertType.aging_60_days })
    }

    @Test
    fun `generateInventoryAlerts creates low ROI alert`() {
        val vehicle = createVehicle(purchaseDate = dateDaysAgo(30))
        val stats = VehicleInventoryStats(
            id = UUID.randomUUID(),
            vehicleId = vehicle.id,
            daysInInventory = 30,
            agingBucket = "0-30",
            totalCost = BigDecimal("50000.00"),
            holdingCostAccumulated = BigDecimal("1000.00"),
            roiPercent = BigDecimal("5.00"),
            profitEstimate = BigDecimal("2500.00"),
            lastCalculatedAt = Date(),
            createdAt = Date(),
            updatedAt = Date()
        )

        val alerts = InventoryMetricsCalculator.generateInventoryAlerts(stats, vehicle)

        assertTrue(alerts.any { it.alertType == InventoryAlertType.low_roi })
    }

    @Test
    fun `generateInventoryAlerts creates high holding cost alert`() {
        val vehicle = createVehicle(purchaseDate = dateDaysAgo(30))
        val stats = VehicleInventoryStats(
            id = UUID.randomUUID(),
            vehicleId = vehicle.id,
            daysInInventory = 30,
            agingBucket = "0-30",
            totalCost = BigDecimal("50000.00"),
            holdingCostAccumulated = BigDecimal("8000.00"),
            roiPercent = BigDecimal("20.00"),
            profitEstimate = BigDecimal("10000.00"),
            lastCalculatedAt = Date(),
            createdAt = Date(),
            updatedAt = Date()
        )

        val alerts = InventoryMetricsCalculator.generateInventoryAlerts(stats, vehicle)

        assertTrue(alerts.any { it.alertType == InventoryAlertType.high_holding_cost })
    }

    @Test
    fun `generateInventoryAlerts no alerts for healthy vehicle`() {
        val vehicle = createVehicle(purchaseDate = dateDaysAgo(20))
        val stats = VehicleInventoryStats(
            id = UUID.randomUUID(),
            vehicleId = vehicle.id,
            daysInInventory = 20,
            agingBucket = "0-30",
            totalCost = BigDecimal("50000.00"),
            holdingCostAccumulated = BigDecimal("500.00"),
            roiPercent = BigDecimal("25.00"),
            profitEstimate = BigDecimal("12500.00"),
            lastCalculatedAt = Date(),
            createdAt = Date(),
            updatedAt = Date()
        )

        val alerts = InventoryMetricsCalculator.generateInventoryAlerts(stats, vehicle)

        assertEquals(0, alerts.size)
    }

    @Test
    fun `calculateInventoryHealthScore returns 100 for empty inventory`() {
        val score = InventoryMetricsCalculator.calculateInventoryHealthScore(emptyList(), emptyList())
        assertEquals(100, score)
    }

    @Test
    fun `calculateInventoryHealthScore calculates for healthy vehicles`() {
        val vehicles = listOf(createVehicle())
        val stats = listOf(
            VehicleInventoryStats(
                id = UUID.randomUUID(),
                vehicleId = vehicles[0].id,
                daysInInventory = 15,
                agingBucket = "0-30",
                totalCost = BigDecimal("50000.00"),
                holdingCostAccumulated = BigDecimal("500.00"),
                roiPercent = BigDecimal("25.00"),
                profitEstimate = BigDecimal("12500.00"),
                lastCalculatedAt = Date(),
                createdAt = Date(),
                updatedAt = Date()
            )
        )

        val score = InventoryMetricsCalculator.calculateInventoryHealthScore(vehicles, stats)
        assertTrue(score > 80)
    }

    @Test
    fun `calculateAgingDistribution groups correctly`() {
        val stats = listOf(
            createStats(agingBucket = "0-30"),
            createStats(agingBucket = "0-30"),
            createStats(agingBucket = "31-60"),
            createStats(agingBucket = "90+")
        )

        val distribution = InventoryMetricsCalculator.calculateAgingDistribution(stats)

        assertEquals(2, distribution["0-30"])
        assertEquals(1, distribution["31-60"])
        assertEquals(1, distribution["90+"])
    }

    @Test
    fun `calculateAverageDaysInInventory returns correct average`() {
        val stats = listOf(
            createStats(daysInInventory = 10),
            createStats(daysInInventory = 20),
            createStats(daysInInventory = 30)
        )

        val average = InventoryMetricsCalculator.calculateAverageDaysInInventory(stats)
        assertEquals(20, average)
    }

    @Test
    fun `calculateAverageDaysInInventory returns 0 for empty list`() {
        val average = InventoryMetricsCalculator.calculateAverageDaysInInventory(emptyList())
        assertEquals(0, average)
    }

    @Test
    fun `calculateTotalHoldingCost sums correctly`() {
        val stats = listOf(
            createStats(holdingCost = BigDecimal("1000.00")),
            createStats(holdingCost = BigDecimal("2000.00")),
            createStats(holdingCost = BigDecimal("1500.00"))
        )

        val total = InventoryMetricsCalculator.calculateTotalHoldingCost(stats)
        assertEquals(BigDecimal("4500.00"), total)
    }

    @Test
    fun `calculateTotalInventoryValue sums correctly`() {
        val stats = listOf(
            createStats(totalCost = BigDecimal("50000.00")),
            createStats(totalCost = BigDecimal("60000.00"))
        )

        val total = InventoryMetricsCalculator.calculateTotalInventoryValue(stats)
        assertEquals(BigDecimal("110000.00"), total)
    }

    private fun createStats(
        daysInInventory: Int = 30,
        agingBucket: String = "0-30",
        holdingCost: BigDecimal = BigDecimal("1000.00"),
        totalCost: BigDecimal = BigDecimal("50000.00")
    ): VehicleInventoryStats {
        return VehicleInventoryStats(
            id = UUID.randomUUID(),
            vehicleId = UUID.randomUUID(),
            daysInInventory = daysInInventory,
            agingBucket = agingBucket,
            totalCost = totalCost,
            holdingCostAccumulated = holdingCost,
            roiPercent = BigDecimal("15.00"),
            profitEstimate = BigDecimal("5000.00"),
            lastCalculatedAt = Date(),
            createdAt = Date(),
            updatedAt = Date()
        )
    }
}
