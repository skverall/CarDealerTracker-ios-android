package com.ezcar24.business.util.calculator

import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.HoldingCostSettings
import com.ezcar24.business.data.local.InventoryAlert
import com.ezcar24.business.data.local.InventoryAlertType
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.data.local.VehicleInventoryStats
import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Date
import java.util.UUID

object InventoryMetricsCalculator {

    private const val DISPLAY_SCALE = 2

    private const val AGING_BUCKET_0_30 = "0-30"
    private const val AGING_BUCKET_31_60 = "31-60"
    private const val AGING_BUCKET_61_90 = "61-90"
    private const val AGING_BUCKET_90_PLUS = "90+"

    private const val THRESHOLD_AGING_60 = 60
    private const val THRESHOLD_AGING_90 = 90
    private const val THRESHOLD_LOW_ROI = 10
    private const val THRESHOLD_HIGH_HOLDING_COST_PERCENT = 15

    fun calculateAgingBucket(daysInInventory: Int): String {
        return when {
            daysInInventory <= 30 -> AGING_BUCKET_0_30
            daysInInventory <= 60 -> AGING_BUCKET_31_60
            daysInInventory <= 90 -> AGING_BUCKET_61_90
            else -> AGING_BUCKET_90_PLUS
        }
    }

    fun calculateInventoryStats(
        vehicle: Vehicle,
        expenses: List<Expense>,
        settings: HoldingCostSettings
    ): VehicleInventoryStats {
        val daysInInventory = HoldingCostCalculator.calculateDaysInInventory(vehicle)
        val agingBucket = calculateAgingBucket(daysInInventory)

        val improvementExpenses = HoldingCostCalculator.getImprovementExpenses(expenses)
        val holdingCostAccumulated = HoldingCostCalculator.calculateAccumulatedHoldingCost(
            vehicle,
            settings,
            expenses
        )

        val totalCost = VehicleFinancialsCalculator.calculateTotalCost(
            vehicle,
            expenses,
            holdingCostAccumulated
        )

        val roiPercent = vehicle.salePrice?.let { salePrice ->
            VehicleFinancialsCalculator.calculateROI(salePrice, totalCost)
        }

        val profitEstimate = vehicle.askingPrice?.let { askingPrice ->
            VehicleFinancialsCalculator.calculateProfitEstimate(askingPrice, totalCost)
        }

        val now = Date()

        return VehicleInventoryStats(
            id = UUID.randomUUID(),
            vehicleId = vehicle.id,
            daysInInventory = daysInInventory,
            agingBucket = agingBucket,
            totalCost = totalCost,
            holdingCostAccumulated = holdingCostAccumulated,
            roiPercent = roiPercent,
            profitEstimate = profitEstimate,
            lastCalculatedAt = now,
            createdAt = now,
            updatedAt = now
        )
    }

    fun generateInventoryAlerts(
        stats: VehicleInventoryStats,
        vehicle: Vehicle
    ): List<InventoryAlert> {
        val alerts = mutableListOf<InventoryAlert>()
        val now = Date()

        if (stats.daysInInventory >= THRESHOLD_AGING_90) {
            alerts.add(
                InventoryAlert(
                    id = UUID.randomUUID(),
                    vehicleId = vehicle.id,
                    alertType = InventoryAlertType.aging_90_days,
                    severity = "high",
                    message = "Vehicle has been in inventory for ${stats.daysInInventory} days. Consider aggressive pricing.",
                    isRead = false,
                    createdAt = now,
                    dismissedAt = null
                )
            )
        } else if (stats.daysInInventory >= THRESHOLD_AGING_60) {
            alerts.add(
                InventoryAlert(
                    id = UUID.randomUUID(),
                    vehicleId = vehicle.id,
                    alertType = InventoryAlertType.aging_60_days,
                    severity = "medium",
                    message = "Vehicle has been in inventory for ${stats.daysInInventory} days. Review pricing strategy.",
                    isRead = false,
                    createdAt = now,
                    dismissedAt = null
                )
            )
        }

        stats.roiPercent?.let { roi ->
            if (roi.compareTo(BigDecimal(THRESHOLD_LOW_ROI)) < 0) {
                alerts.add(
                    InventoryAlert(
                        id = UUID.randomUUID(),
                        vehicleId = vehicle.id,
                        alertType = InventoryAlertType.low_roi,
                        severity = "high",
                        message = "Projected ROI is ${roi.setScale(1, RoundingMode.HALF_UP)}%. Consider cost reduction or price increase.",
                        isRead = false,
                        createdAt = now,
                        dismissedAt = null
                    )
                )
            }
        }

        val holdingCostPercentage = VehicleFinancialsCalculator.calculateHoldingCostPercentage(
            stats.holdingCostAccumulated,
            stats.totalCost
        )

        holdingCostPercentage?.let { percentage ->
            if (percentage.compareTo(BigDecimal(THRESHOLD_HIGH_HOLDING_COST_PERCENT)) > 0) {
                alerts.add(
                    InventoryAlert(
                        id = UUID.randomUUID(),
                        vehicleId = vehicle.id,
                        alertType = InventoryAlertType.high_holding_cost,
                        severity = "medium",
                        message = "Holding cost is ${percentage.setScale(1, RoundingMode.HALF_UP)}% of total cost. Consider faster turnover.",
                        isRead = false,
                        createdAt = now,
                        dismissedAt = null
                    )
                )
            }
        }

        if (shouldRecommendPriceReduction(stats, vehicle)) {
            alerts.add(
                InventoryAlert(
                    id = UUID.randomUUID(),
                    vehicleId = vehicle.id,
                    alertType = InventoryAlertType.price_reduction_needed,
                    severity = "medium",
                    message = "Based on aging and market conditions, consider a price reduction to accelerate sale.",
                    isRead = false,
                    createdAt = now,
                    dismissedAt = null
                )
            )
        }

        return alerts
    }

    fun calculateInventoryHealthScore(
        vehicles: List<Vehicle>,
        allStats: List<VehicleInventoryStats>
    ): Int {
        if (vehicles.isEmpty()) {
            return 100
        }

        var totalScore = 0

        allStats.forEach { stats ->
            var vehicleScore = 100

            when (stats.agingBucket) {
                AGING_BUCKET_31_60 -> vehicleScore -= 10
                AGING_BUCKET_61_90 -> vehicleScore -= 25
                AGING_BUCKET_90_PLUS -> vehicleScore -= 40
                else -> {}
            }

            stats.roiPercent?.let { roi ->
                when {
                    roi.compareTo(BigDecimal.ZERO) < 0 -> vehicleScore -= 30
                    roi.compareTo(BigDecimal("10")) < 0 -> vehicleScore -= 15
                    roi.compareTo(BigDecimal("20")) < 0 -> vehicleScore -= 5
                    else -> vehicleScore += 5
                }
            }

            val holdingCostPercentage = stats.holdingCostAccumulated
                .divide(stats.totalCost, 4, RoundingMode.HALF_UP)
                .multiply(BigDecimal(100))

            when {
                holdingCostPercentage.compareTo(BigDecimal("20")) > 0 -> vehicleScore -= 20
                holdingCostPercentage.compareTo(BigDecimal("10")) > 0 -> vehicleScore -= 10
            }

            totalScore += maxOf(0, minOf(100, vehicleScore))
        }

        return totalScore / vehicles.size
    }

    fun calculateAgingDistribution(
        stats: List<VehicleInventoryStats>
    ): Map<String, Int> {
        return stats.groupingBy { it.agingBucket }
            .eachCount()
            .toSortedMap(compareBy { bucket ->
                when (bucket) {
                    AGING_BUCKET_0_30 -> 0
                    AGING_BUCKET_31_60 -> 1
                    AGING_BUCKET_61_90 -> 2
                    AGING_BUCKET_90_PLUS -> 3
                    else -> 4
                }
            })
    }

    fun calculateAverageDaysInInventory(stats: List<VehicleInventoryStats>): Int {
        if (stats.isEmpty()) {
            return 0
        }
        return stats.sumOf { it.daysInInventory } / stats.size
    }

    fun calculateTotalHoldingCost(stats: List<VehicleInventoryStats>): BigDecimal {
        return stats
            .map { it.holdingCostAccumulated }
            .fold(BigDecimal.ZERO) { acc, cost -> acc.add(cost) }
            .setScale(DISPLAY_SCALE, RoundingMode.HALF_UP)
    }

    fun calculateTotalInventoryValue(stats: List<VehicleInventoryStats>): BigDecimal {
        return stats
            .map { it.totalCost }
            .fold(BigDecimal.ZERO) { acc, cost -> acc.add(cost) }
            .setScale(DISPLAY_SCALE, RoundingMode.HALF_UP)
    }

    private fun shouldRecommendPriceReduction(
        stats: VehicleInventoryStats,
        vehicle: Vehicle
    ): Boolean {
        if (vehicle.saleDate != null) {
            return false
        }

        val isAging = stats.daysInInventory >= THRESHOLD_AGING_60

        val hasLowROI = stats.roiPercent?.let { roi ->
            roi.compareTo(BigDecimal("15")) < 0
        } ?: false

        val hasHighHoldingCost = stats.holdingCostAccumulated
            .divide(stats.totalCost, 4, RoundingMode.HALF_UP)
            .multiply(BigDecimal(100))
            .compareTo(BigDecimal("12")) > 0

        return isAging && (hasLowROI || hasHighHoldingCost)
    }
}
