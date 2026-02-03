package com.ezcar24.business.data.repository

import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.ExpenseDao
import com.ezcar24.business.data.local.HoldingCostSettings
import com.ezcar24.business.data.local.HoldingCostSettingsDao
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.data.local.VehicleDao
import com.ezcar24.business.data.local.VehicleInventoryStats
import com.ezcar24.business.data.local.VehicleWithExpenses
import com.ezcar24.business.data.local.VehicleWithFinancials
import com.ezcar24.business.util.calculator.HoldingCostCalculator
import com.ezcar24.business.util.calculator.InventoryMetricsCalculator
import com.ezcar24.business.util.calculator.VehicleFinancialsCalculator
import java.math.BigDecimal
import java.util.Date
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map

data class VehicleFinancialSummary(
    val vehicle: Vehicle,
    val expenses: List<Expense>,
    val holdingCost: BigDecimal,
    val totalCost: BigDecimal,
    val daysInInventory: Int,
    val roiPercent: BigDecimal?,
    val profitEstimate: BigDecimal?
)

@Singleton
class VehicleRepository @Inject constructor(
    private val vehicleDao: VehicleDao,
    private val expenseDao: ExpenseDao,
    private val holdingCostSettingsDao: HoldingCostSettingsDao
) {
    fun getActiveVehicles(): Flow<List<Vehicle>> {
        return vehicleDao.getAllActive()
    }

    fun getVehiclesWithFinancials(): Flow<List<VehicleWithFinancials>> {
        return vehicleDao.getAllActiveWithFinancialsFlow()
    }

    suspend fun getVehicleWithExpenses(vehicleId: UUID): VehicleWithExpenses? {
        val vehicle = vehicleDao.getById(vehicleId) ?: return null
        val expenses = expenseDao.getExpensesForVehicleSync(vehicleId)
        return VehicleWithExpenses(vehicle, expenses)
    }

    fun getVehicleWithExpensesFlow(vehicleId: UUID): Flow<VehicleWithExpenses?> {
        return combine(
            flow {
                val vehicle = vehicleDao.getById(vehicleId)
                emit(vehicle)
            },
            expenseDao.getByVehicleId(vehicleId)
        ) { vehicle, expenses ->
            vehicle?.let { VehicleWithExpenses(it, expenses) }
        }
    }

    suspend fun calculateHoldingCostForVehicle(
        vehicleId: UUID,
        asOfDate: Date = Date()
    ): BigDecimal? {
        val vehicle = vehicleDao.getById(vehicleId) ?: return null
        val expenses = expenseDao.getExpensesForVehicleSync(vehicleId)
        val settings = getOrCreateHoldingCostSettings()

        return HoldingCostCalculator.calculateAccumulatedHoldingCost(
            vehicle,
            settings,
            expenses,
            asOfDate
        )
    }

    fun getVehicleFinancialSummaryFlow(vehicleId: UUID): Flow<VehicleFinancialSummary?> {
        return getVehicleWithExpensesFlow(vehicleId).map { vehicleWithExpenses ->
            vehicleWithExpenses?.let { calculateFinancialSummary(it) }
        }
    }

    suspend fun getVehicleFinancialSummary(vehicleId: UUID): VehicleFinancialSummary? {
        val vehicleWithExpenses = getVehicleWithExpenses(vehicleId) ?: return null
        return calculateFinancialSummary(vehicleWithExpenses)
    }

    fun getAllVehiclesWithFinancialSummary(): Flow<List<VehicleFinancialSummary>> {
        return combine(
            vehicleDao.getAllActive(),
            expenseDao.getAll()
        ) { vehicles, allExpenses ->
            val settings = getOrCreateHoldingCostSettings()

            vehicles.map { vehicle ->
                val vehicleExpenses = allExpenses.filter { it.vehicleId == vehicle.id }
                val holdingCost = HoldingCostCalculator.calculateAccumulatedHoldingCost(
                    vehicle,
                    settings,
                    vehicleExpenses
                )
                val totalCost = VehicleFinancialsCalculator.calculateTotalCost(
                    vehicle,
                    vehicleExpenses,
                    holdingCost
                )
                val daysInInventory = HoldingCostCalculator.calculateDaysInInventory(vehicle)

                VehicleFinancialSummary(
                    vehicle = vehicle,
                    expenses = vehicleExpenses,
                    holdingCost = holdingCost,
                    totalCost = totalCost,
                    daysInInventory = daysInInventory,
                    roiPercent = vehicle.salePrice?.let { salePrice ->
                        VehicleFinancialsCalculator.calculateROI(salePrice, totalCost)
                    },
                    profitEstimate = vehicle.askingPrice?.let { askingPrice ->
                        VehicleFinancialsCalculator.calculateProfitEstimate(askingPrice, totalCost)
                    }
                )
            }
        }
    }

    suspend fun calculateInventoryStats(vehicleId: UUID): VehicleInventoryStats? {
        val vehicle = vehicleDao.getById(vehicleId) ?: return null
        val expenses = expenseDao.getExpensesForVehicleSync(vehicleId)
        val settings = getOrCreateHoldingCostSettings()

        return InventoryMetricsCalculator.calculateInventoryStats(vehicle, expenses, settings)
    }

    suspend fun refreshAllInventoryStats(): List<VehicleInventoryStats> {
        val vehicles = vehicleDao.getAllIncludingDeleted().filter { it.deletedAt == null }
        val settings = getOrCreateHoldingCostSettings()

        return vehicles.map { vehicle ->
            val expenses = expenseDao.getExpensesForVehicleSync(vehicle.id)
            InventoryMetricsCalculator.calculateInventoryStats(vehicle, expenses, settings)
        }
    }

    suspend fun getDaysInInventory(vehicleId: UUID): Int? {
        val vehicle = vehicleDao.getById(vehicleId) ?: return null
        return HoldingCostCalculator.calculateDaysInInventory(vehicle)
    }

    suspend fun getCapitalTiedUp(vehicleId: UUID): BigDecimal? {
        val vehicle = vehicleDao.getById(vehicleId) ?: return null
        val expenses = expenseDao.getExpensesForVehicleSync(vehicleId)
        val improvementExpenses = HoldingCostCalculator.getImprovementExpenses(expenses)
        return HoldingCostCalculator.getCapitalTiedUp(vehicle, improvementExpenses)
    }

    suspend fun getRecommendedAskingPrice(vehicleId: UUID, targetROI: BigDecimal = BigDecimal("20.00")): BigDecimal? {
        val vehicle = vehicleDao.getById(vehicleId) ?: return null
        val expenses = expenseDao.getExpensesForVehicleSync(vehicleId)
        val settings = getOrCreateHoldingCostSettings()

        val holdingCost = HoldingCostCalculator.calculateAccumulatedHoldingCost(
            vehicle,
            settings,
            expenses
        )

        return VehicleFinancialsCalculator.calculateRecommendedAskingPrice(
            vehicle,
            expenses,
            holdingCost,
            targetROI
        )
    }

    private suspend fun calculateFinancialSummary(
        vehicleWithExpenses: VehicleWithExpenses
    ): VehicleFinancialSummary {
        val vehicle = vehicleWithExpenses.vehicle
        val expenses = vehicleWithExpenses.expenses
        val settings = getOrCreateHoldingCostSettings()

        val holdingCost = HoldingCostCalculator.calculateAccumulatedHoldingCost(
            vehicle,
            settings,
            expenses
        )
        val totalCost = VehicleFinancialsCalculator.calculateTotalCost(vehicle, expenses, holdingCost)
        val daysInInventory = HoldingCostCalculator.calculateDaysInInventory(vehicle)

        return VehicleFinancialSummary(
            vehicle = vehicle,
            expenses = expenses,
            holdingCost = holdingCost,
            totalCost = totalCost,
            daysInInventory = daysInInventory,
            roiPercent = vehicle.salePrice?.let { salePrice ->
                VehicleFinancialsCalculator.calculateROI(salePrice, totalCost)
            },
            profitEstimate = vehicle.askingPrice?.let { askingPrice ->
                VehicleFinancialsCalculator.calculateProfitEstimate(askingPrice, totalCost)
            }
        )
    }

    private suspend fun getOrCreateHoldingCostSettings(): HoldingCostSettings {
        return holdingCostSettingsDao.getSettings()?.first()
            ?: HoldingCostSettings(
                id = UUID.randomUUID(),
                dealerId = UUID.randomUUID(),
                annualRatePercent = BigDecimal("15.00"),
                createdAt = Date(),
                updatedAt = null
            )
    }
}
