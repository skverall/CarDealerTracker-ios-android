package com.ezcar24.business.data.repository

import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.ExpenseCategoryType
import com.ezcar24.business.data.local.ExpenseDao
import java.math.BigDecimal
import java.util.Date
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

data class ExpenseSummary(
    val totalAmount: BigDecimal,
    val count: Int,
    val averageAmount: BigDecimal,
    val byCategory: Map<String, BigDecimal>,
    val byType: Map<ExpenseCategoryType, BigDecimal>
)

data class VehicleExpenseSummary(
    val vehicleId: UUID,
    val totalExpenses: BigDecimal,
    val holdingCosts: BigDecimal,
    val improvementCosts: BigDecimal,
    val operationalCosts: BigDecimal,
    val expenseCount: Int
)

@Singleton
class ExpenseRepository @Inject constructor(
    private val expenseDao: ExpenseDao
) {

    fun getAllExpenses(): Flow<List<Expense>> {
        return expenseDao.getAll()
    }

    fun getExpensesByVehicle(vehicleId: UUID): Flow<List<Expense>> {
        return expenseDao.getByVehicleId(vehicleId)
    }

    suspend fun getExpensesByVehicleSync(vehicleId: UUID): List<Expense> {
        return expenseDao.getExpensesForVehicleSync(vehicleId)
    }

    fun getExpensesByVehicleAndType(
        vehicleId: UUID,
        expenseType: ExpenseCategoryType
    ): Flow<List<Expense>> {
        return expenseDao.getByVehicleId(vehicleId).map { expenses ->
            expenses.filter { it.expenseType == expenseType }
        }
    }

    suspend fun getExpensesByVehicleAndTypeSync(
        vehicleId: UUID,
        expenseType: ExpenseCategoryType
    ): List<Expense> {
        return expenseDao.getExpensesForVehicleSync(vehicleId)
            .filter { it.expenseType == expenseType }
    }

    fun getImprovementExpenses(vehicleId: UUID): Flow<List<Expense>> {
        return expenseDao.getByVehicleId(vehicleId).map { expenses ->
            expenses.filter { it.expenseType == ExpenseCategoryType.IMPROVEMENT }
        }
    }

    suspend fun getImprovementExpensesSync(vehicleId: UUID): List<Expense> {
        return expenseDao.getExpensesForVehicleSync(vehicleId)
            .filter { it.expenseType == ExpenseCategoryType.IMPROVEMENT }
    }

    fun getHoldingCostExpenses(vehicleId: UUID): Flow<List<Expense>> {
        return expenseDao.getByVehicleId(vehicleId).map { expenses ->
            expenses.filter { it.expenseType == ExpenseCategoryType.HOLDING_COST }
        }
    }

    suspend fun getHoldingCostExpensesSync(vehicleId: UUID): List<Expense> {
        return expenseDao.getExpensesForVehicleSync(vehicleId)
            .filter { it.expenseType == ExpenseCategoryType.HOLDING_COST }
    }

    fun getOperationalExpenses(vehicleId: UUID): Flow<List<Expense>> {
        return expenseDao.getByVehicleId(vehicleId).map { expenses ->
            expenses.filter { it.expenseType == ExpenseCategoryType.OPERATIONAL }
        }
    }

    suspend fun getOperationalExpensesSync(vehicleId: UUID): List<Expense> {
        return expenseDao.getExpensesForVehicleSync(vehicleId)
            .filter { it.expenseType == ExpenseCategoryType.OPERATIONAL }
    }

    fun getExpensesByDateRange(startDate: Date, endDate: Date): Flow<List<Expense>> {
        return expenseDao.getAll().map { expenses ->
            expenses.filter { it.date >= startDate && it.date <= endDate }
        }
    }

    suspend fun getExpensesByDateRangeSync(startDate: Date, endDate: Date): List<Expense> {
        return expenseDao.getAll().first()
            .filter { it.date >= startDate && it.date <= endDate }
    }

    fun getExpensesByCategory(category: String): Flow<List<Expense>> {
        return expenseDao.getAll().map { expenses ->
            expenses.filter { it.category.equals(category, ignoreCase = true) }
        }
    }

    suspend fun getExpensesSince(since: Date): List<Expense> {
        return expenseDao.getExpensesSince(since)
    }

    suspend fun searchExpenses(query: String): List<Expense> {
        return expenseDao.searchActive("%${query.lowercase()}%")
    }

    suspend fun getExpenseById(expenseId: UUID): Expense? {
        return expenseDao.getById(expenseId)
    }

    fun getExpenseSummary(): Flow<ExpenseSummary> {
        return expenseDao.getAll().map { expenses ->
            calculateExpenseSummary(expenses)
        }
    }

    suspend fun getExpenseSummarySync(): ExpenseSummary {
        val expenses = expenseDao.getAll().first()
        return calculateExpenseSummary(expenses)
    }

    fun getVehicleExpenseSummary(vehicleId: UUID): Flow<VehicleExpenseSummary> {
        return expenseDao.getByVehicleId(vehicleId).map { expenses ->
            calculateVehicleExpenseSummary(vehicleId, expenses)
        }
    }

    suspend fun getVehicleExpenseSummarySync(vehicleId: UUID): VehicleExpenseSummary {
        val expenses = expenseDao.getExpensesForVehicleSync(vehicleId)
        return calculateVehicleExpenseSummary(vehicleId, expenses)
    }

    fun getTotalExpensesByVehicle(vehicleId: UUID): Flow<BigDecimal> {
        return expenseDao.getByVehicleId(vehicleId).map { expenses ->
            expenses
                .filter { it.deletedAt == null }
                .map { it.amount }
                .fold(BigDecimal.ZERO) { acc, amount -> acc.add(amount) }
        }
    }

    suspend fun getTotalExpensesByVehicleSync(vehicleId: UUID): BigDecimal {
        return expenseDao.getExpensesForVehicleSync(vehicleId)
            .filter { it.deletedAt == null }
            .map { it.amount }
            .fold(BigDecimal.ZERO) { acc, amount -> acc.add(amount) }
    }

    fun getExpensesCount(): Flow<Int> {
        return expenseDao.getAll().map { it.size }
    }

    suspend fun getExpensesCountSync(): Int {
        return expenseDao.count()
    }

    suspend fun getExpensesCountForVehicle(vehicleId: UUID): Int {
        return expenseDao.getExpensesForVehicleSync(vehicleId).size
    }

    suspend fun createExpense(expense: Expense) {
        expenseDao.upsert(expense)
    }

    suspend fun updateExpense(expense: Expense) {
        expenseDao.upsert(expense)
    }

    suspend fun deleteExpense(expense: Expense) {
        expenseDao.delete(expense)
    }

    suspend fun createExpenses(expenses: List<Expense>) {
        expenseDao.upsertAll(expenses)
    }

    private fun calculateExpenseSummary(expenses: List<Expense>): ExpenseSummary {
        val activeExpenses = expenses.filter { it.deletedAt == null }
        val totalAmount = activeExpenses
            .map { it.amount }
            .fold(BigDecimal.ZERO) { acc, amount -> acc.add(amount) }
        val count = activeExpenses.size
        val averageAmount = if (count > 0) {
            totalAmount.divide(BigDecimal(count), 2, BigDecimal.ROUND_HALF_UP)
        } else {
            BigDecimal.ZERO
        }

        val byCategory = activeExpenses
            .groupBy { it.category }
            .mapValues { (_, expenses) ->
                expenses
                    .map { it.amount }
                    .fold(BigDecimal.ZERO) { acc, amount -> acc.add(amount) }
            }

        val byType = activeExpenses
            .groupBy { it.expenseType }
            .mapValues { (_, expenses) ->
                expenses
                    .map { it.amount }
                    .fold(BigDecimal.ZERO) { acc, amount -> acc.add(amount) }
            }

        return ExpenseSummary(
            totalAmount = totalAmount,
            count = count,
            averageAmount = averageAmount,
            byCategory = byCategory,
            byType = byType
        )
    }

    private fun calculateVehicleExpenseSummary(
        vehicleId: UUID,
        expenses: List<Expense>
    ): VehicleExpenseSummary {
        val activeExpenses = expenses.filter { it.deletedAt == null }

        val holdingCosts = activeExpenses
            .filter { it.expenseType == ExpenseCategoryType.HOLDING_COST }
            .map { it.amount }
            .fold(BigDecimal.ZERO) { acc, amount -> acc.add(amount) }

        val improvementCosts = activeExpenses
            .filter { it.expenseType == ExpenseCategoryType.IMPROVEMENT }
            .map { it.amount }
            .fold(BigDecimal.ZERO) { acc, amount -> acc.add(amount) }

        val operationalCosts = activeExpenses
            .filter { it.expenseType == ExpenseCategoryType.OPERATIONAL }
            .map { it.amount }
            .fold(BigDecimal.ZERO) { acc, amount -> acc.add(amount) }

        val totalExpenses = holdingCosts.add(improvementCosts).add(operationalCosts)

        return VehicleExpenseSummary(
            vehicleId = vehicleId,
            totalExpenses = totalExpenses,
            holdingCosts = holdingCosts,
            improvementCosts = improvementCosts,
            operationalCosts = operationalCosts,
            expenseCount = activeExpenses.size
        )
    }
}
