package com.ezcar24.business.util.calculator

import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.HoldingCostSettings
import com.ezcar24.business.data.local.PartSale
import com.ezcar24.business.data.local.PartSaleLineItem
import com.ezcar24.business.data.local.Sale
import com.ezcar24.business.data.local.Vehicle
import java.math.BigDecimal
import java.util.Date

object DashboardMetricsCalculator {

    fun calculateTotalRevenue(
        sales: List<Sale>,
        partSales: List<PartSale>
    ): BigDecimal {
        val vehicleRevenue = sales
            .filter { it.deletedAt == null }
            .mapNotNull { it.amount }
            .fold(BigDecimal.ZERO) { total, amount -> total.add(amount) }

        val partRevenue = partSales
            .filter { it.deletedAt == null }
            .fold(BigDecimal.ZERO) { total, sale -> total.add(sale.amount) }

        return vehicleRevenue.add(partRevenue)
    }

    fun calculateSalesProfit(
        sales: List<Sale>,
        vehicles: List<Vehicle>,
        allExpenses: List<Expense>,
        partSales: List<PartSale>,
        partSaleLineItems: List<PartSaleLineItem>,
        holdingCostSettings: HoldingCostSettings?
    ): BigDecimal {
        val vehicleProfit = sales
            .filter { it.deletedAt == null }
            .fold(BigDecimal.ZERO) { total, sale ->
                val vehicle = sale.vehicleId?.let { vehicleId -> vehicles.find { it.id == vehicleId } }
                val saleAmount = sale.amount ?: BigDecimal.ZERO
                val purchasePrice = vehicle?.purchasePrice ?: BigDecimal.ZERO
                val vehicleExpenses = vehicle?.let { currentVehicle ->
                    allExpenses
                        .filter { it.deletedAt == null && it.vehicleId == currentVehicle.id }
                        .fold(BigDecimal.ZERO) { expenseTotal, expense -> expenseTotal.add(expense.amount) }
                } ?: BigDecimal.ZERO
                val saleDate = sale.date ?: vehicle?.saleDate ?: Date()
                val holdingCost = if (vehicle != null && holdingCostSettings?.isEnabled == true) {
                    HoldingCostCalculator.calculateAccumulatedHoldingCost(
                        vehicle = vehicle.copy(saleDate = saleDate),
                        settings = holdingCostSettings,
                        allExpenses = allExpenses.filter { it.vehicleId == vehicle.id },
                        asOfDate = saleDate
                    )
                } else {
                    BigDecimal.ZERO
                }
                val vatRefund = sale.vatRefundAmount ?: BigDecimal.ZERO

                total.add(
                    saleAmount
                        .subtract(purchasePrice)
                        .subtract(vehicleExpenses)
                        .subtract(holdingCost)
                        .add(vatRefund)
                )
            }

        val lineItemsBySale = partSaleLineItems
            .filter { it.deletedAt == null }
            .groupBy { it.saleId }

        val partProfit = partSales
            .filter { it.deletedAt == null }
            .fold(BigDecimal.ZERO) { total, sale ->
                val costOfGoods = lineItemsBySale[sale.id].orEmpty().fold(BigDecimal.ZERO) { costTotal, item ->
                    costTotal.add(item.unitCost.multiply(item.quantity))
                }
                total.add(sale.amount.subtract(costOfGoods))
            }

        return vehicleProfit.add(partProfit)
    }
}
