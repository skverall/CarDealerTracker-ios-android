package com.ezcar24.business.util.calculator

import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.ExpenseCategoryType
import com.ezcar24.business.data.local.Vehicle
import java.math.BigDecimal
import java.math.RoundingMode

object VehicleFinancialsCalculator {

    private const val INTERMEDIATE_SCALE = 4
    private const val DISPLAY_SCALE = 2
    private const val PERCENTAGE_SCALE = 2

    fun calculateTotalCost(
        vehicle: Vehicle,
        allExpenses: List<Expense>,
        holdingCost: BigDecimal
    ): BigDecimal {
        val purchasePrice = vehicle.purchasePrice

        val expensesTotal = allExpenses
            .filter { it.deletedAt == null }
            .map { it.amount }
            .fold(BigDecimal.ZERO) { acc, amount -> acc.add(amount) }

        return purchasePrice
            .add(expensesTotal)
            .add(holdingCost)
            .setScale(DISPLAY_SCALE, RoundingMode.HALF_UP)
    }

    fun calculateTotalExpensesOnly(
        vehicle: Vehicle,
        allExpenses: List<Expense>
    ): BigDecimal {
        val expensesTotal = allExpenses
            .filter { it.deletedAt == null }
            .map { it.amount }
            .fold(BigDecimal.ZERO) { acc, amount -> acc.add(amount) }

        return vehicle.purchasePrice
            .add(expensesTotal)
            .setScale(DISPLAY_SCALE, RoundingMode.HALF_UP)
    }

    fun calculateROI(salePrice: BigDecimal, totalCost: BigDecimal): BigDecimal? {
        if (totalCost.compareTo(BigDecimal.ZERO) == 0) {
            return null
        }

        val profit = salePrice.subtract(totalCost)
        return profit
            .divide(totalCost, INTERMEDIATE_SCALE, RoundingMode.HALF_UP)
            .multiply(BigDecimal(100))
            .setScale(PERCENTAGE_SCALE, RoundingMode.HALF_UP)
    }

    fun calculateProfitEstimate(askingPrice: BigDecimal, totalCost: BigDecimal): BigDecimal? {
        return askingPrice
            .subtract(totalCost)
            .setScale(DISPLAY_SCALE, RoundingMode.HALF_UP)
    }

    fun calculateActualProfit(salePrice: BigDecimal, totalCost: BigDecimal): BigDecimal {
        return salePrice
            .subtract(totalCost)
            .setScale(DISPLAY_SCALE, RoundingMode.HALF_UP)
    }

    fun calculateHoldingCostPercentage(
        holdingCost: BigDecimal,
        totalCost: BigDecimal
    ): BigDecimal? {
        if (totalCost.compareTo(BigDecimal.ZERO) == 0) {
            return null
        }

        return holdingCost
            .divide(totalCost, INTERMEDIATE_SCALE, RoundingMode.HALF_UP)
            .multiply(BigDecimal(100))
            .setScale(PERCENTAGE_SCALE, RoundingMode.HALF_UP)
    }

    fun calculateExpenseBreakdown(expenses: List<Expense>): Map<ExpenseCategoryType, BigDecimal> {
        return expenses
            .filter { it.deletedAt == null }
            .groupBy { it.expenseType }
            .mapValues { (_, expenses) ->
                expenses
                    .map { it.amount }
                    .fold(BigDecimal.ZERO) { acc, amount -> acc.add(amount) }
                    .setScale(DISPLAY_SCALE, RoundingMode.HALF_UP)
            }
    }

    fun calculateBreakEvenPrice(
        vehicle: Vehicle,
        allExpenses: List<Expense>,
        holdingCost: BigDecimal,
        targetROI: BigDecimal = BigDecimal.ZERO
    ): BigDecimal {
        val totalCost = calculateTotalCost(vehicle, allExpenses, holdingCost)

        if (targetROI.compareTo(BigDecimal.ZERO) == 0) {
            return totalCost
        }

        val roiMultiplier = targetROI
            .divide(BigDecimal(100), INTERMEDIATE_SCALE, RoundingMode.HALF_UP)
            .add(BigDecimal.ONE)

        return totalCost
            .multiply(roiMultiplier)
            .setScale(DISPLAY_SCALE, RoundingMode.HALF_UP)
    }

    fun calculateRecommendedAskingPrice(
        vehicle: Vehicle,
        allExpenses: List<Expense>,
        holdingCost: BigDecimal,
        targetROI: BigDecimal = BigDecimal("20.00")
    ): BigDecimal {
        return calculateBreakEvenPrice(vehicle, allExpenses, holdingCost, targetROI)
    }

    fun isProfitable(salePrice: BigDecimal, totalCost: BigDecimal): Boolean {
        return salePrice.compareTo(totalCost) > 0
    }

    fun getProfitStatus(
        salePrice: BigDecimal,
        totalCost: BigDecimal
    ): ProfitStatus {
        val profit = salePrice.subtract(totalCost)
        val roi = calculateROI(salePrice, totalCost)

        return when {
            profit.compareTo(BigDecimal.ZERO) < 0 -> ProfitStatus.LOSS
            profit.compareTo(BigDecimal.ZERO) == 0 -> ProfitStatus.BREAK_EVEN
            roi != null && roi.compareTo(BigDecimal("20")) >= 0 -> ProfitStatus.HIGH_PROFIT
            else -> ProfitStatus.PROFIT
        }
    }

    enum class ProfitStatus {
        LOSS,
        BREAK_EVEN,
        PROFIT,
        HIGH_PROFIT
    }
}
