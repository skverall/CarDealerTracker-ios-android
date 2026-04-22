package com.ezcar24.business.util.calculator

import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.ExpenseCategoryType
import com.ezcar24.business.data.local.HoldingCostSettings
import com.ezcar24.business.data.local.Vehicle
import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Date
import java.util.concurrent.TimeUnit

object HoldingCostCalculator {

    private const val INTERMEDIATE_SCALE = 4
    private const val RATE_SCALE = 8
    private const val DISPLAY_SCALE = 2
    private const val DAYS_IN_YEAR = 365

    fun calculateDailyHoldingCost(
        vehicle: Vehicle,
        settings: HoldingCostSettings,
        improvementExpenses: List<Expense>
    ): BigDecimal {
        if (!settings.isEnabled) {
            return BigDecimal.ZERO.setScale(DISPLAY_SCALE, RoundingMode.HALF_UP)
        }

        val capitalTiedUp = getCapitalTiedUp(vehicle, improvementExpenses)
        val dailyRate = calculateDailyRateFromAnnual(settings.annualRatePercent)

        return capitalTiedUp
            .multiply(dailyRate)
            .setScale(DISPLAY_SCALE, RoundingMode.HALF_UP)
    }

    fun calculateAccumulatedHoldingCost(
        vehicle: Vehicle,
        settings: HoldingCostSettings,
        allExpenses: List<Expense>,
        asOfDate: Date = Date()
    ): BigDecimal {
        if (!settings.isEnabled) {
            return BigDecimal.ZERO.setScale(DISPLAY_SCALE, RoundingMode.HALF_UP)
        }

        val daysInInventory = calculateDaysInInventory(vehicle, asOfDate)
        if (daysInInventory <= 0) {
            return BigDecimal.ZERO.setScale(DISPLAY_SCALE, RoundingMode.HALF_UP)
        }

        val improvementExpenses = getImprovementExpenses(allExpenses)
        val dailyHoldingCost = calculateDailyHoldingCost(vehicle, settings, improvementExpenses)

        return dailyHoldingCost
            .multiply(BigDecimal(daysInInventory))
            .setScale(DISPLAY_SCALE, RoundingMode.HALF_UP)
    }

    fun calculateDaysInInventory(vehicle: Vehicle, asOfDate: Date = Date()): Int {
        val startDate = vehicle.purchaseDate
        val endDate = vehicle.saleDate ?: asOfDate

        val diffInMillis = endDate.time - startDate.time
        val days = TimeUnit.MILLISECONDS.toDays(diffInMillis).toInt()

        return maxOf(0, days)
    }

    fun getImprovementExpenses(allExpenses: List<Expense>): List<Expense> {
        return allExpenses.filter { expense ->
            expense.deletedAt == null && expense.expenseType == ExpenseCategoryType.IMPROVEMENT
        }
    }

    fun getCapitalTiedUp(vehicle: Vehicle, improvementExpenses: List<Expense>): BigDecimal {
        val improvementsTotal = improvementExpenses
            .filter { it.deletedAt == null }
            .map { it.amount }
            .fold(BigDecimal.ZERO) { acc, amount -> acc.add(amount) }

        return vehicle.purchasePrice
            .add(improvementsTotal)
            .setScale(INTERMEDIATE_SCALE, RoundingMode.HALF_UP)
    }

    fun calculateDailyRateFromAnnual(annualRatePercent: BigDecimal): BigDecimal {
        return annualRatePercent
            .divide(BigDecimal(DAYS_IN_YEAR), RATE_SCALE, RoundingMode.HALF_UP)
            .divide(BigDecimal(100), RATE_SCALE, RoundingMode.HALF_UP)
    }

    fun calculateAnnualRateFromDaily(dailyRatePercent: BigDecimal): BigDecimal {
        return dailyRatePercent
            .multiply(BigDecimal(DAYS_IN_YEAR))
            .multiply(BigDecimal(100))
            .setScale(INTERMEDIATE_SCALE, RoundingMode.HALF_UP)
    }
}
