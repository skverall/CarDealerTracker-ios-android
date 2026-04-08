package com.ezcar24.business.worker

import android.content.Context
import android.util.Log
import androidx.work.*
import com.ezcar24.business.data.local.*
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.util.calculator.InventoryMetricsCalculator
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import java.math.BigDecimal
import java.util.Date
import java.util.UUID
import java.util.concurrent.TimeUnit

class InventoryStatsWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "InventoryStatsWorker"
        private const val WORK_NAME = "inventory_stats_update"

        fun schedulePeriodicWork(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
                .setRequiresBatteryNotLow(true)
                .build()

            val request = PeriodicWorkRequestBuilder<InventoryStatsWorker>(
                15, TimeUnit.MINUTES, // Run every 15 minutes
                5, TimeUnit.MINUTES  // Flex interval
            )
                .setConstraints(constraints)
                .setBackoffCriteria(
                    BackoffPolicy.EXPONENTIAL,
                    WorkRequest.MIN_BACKOFF_MILLIS,
                    TimeUnit.MILLISECONDS
                )
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )

            Log.i(TAG, "Scheduled periodic inventory stats update")
        }

        fun scheduleOneTimeWork(context: Context) {
            val request = OneTimeWorkRequestBuilder<InventoryStatsWorker>()
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
                        .build()
                )
                .build()

            WorkManager.getInstance(context).enqueue(request)
        }

        fun cancelWork(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }

    @EntryPoint
    @InstallIn(SingletonComponent::class)
    interface InventoryStatsWorkerEntryPoint {
        fun vehicleDao(): VehicleDao
        fun expenseDao(): ExpenseDao
        fun holdingCostSettingsDao(): HoldingCostSettingsDao
        fun vehicleInventoryStatsDao(): VehicleInventoryStatsDao
        fun inventoryAlertDao(): InventoryAlertDao
    }

    override suspend fun doWork(): Result {
        Log.i(TAG, "Starting inventory stats update")

        val entryPoint = EntryPointAccessors.fromApplication(
            applicationContext,
            InventoryStatsWorkerEntryPoint::class.java
        )

        val vehicleDao = entryPoint.vehicleDao()
        val expenseDao = entryPoint.expenseDao()
        val holdingCostSettingsDao = entryPoint.holdingCostSettingsDao()
        val vehicleInventoryStatsDao = entryPoint.vehicleInventoryStatsDao()
        val inventoryAlertDao = entryPoint.inventoryAlertDao()

        val dealerId = CloudSyncEnvironment.currentDealerId
        if (dealerId == null) {
            Log.w(TAG, "No dealer ID available, skipping update")
            return Result.retry()
        }

        return try {
            // Get holding cost settings
            val settings = holdingCostSettingsDao.getByDealerId(dealerId)
            val holdingCostEnabled = settings?.isEnabled ?: true
            val dailyRate = settings?.dailyRatePercent ?: BigDecimal("0.04109589")

            // Get all active vehicles
            val vehicles = vehicleDao.getAllIncludingDeleted()
                .filter { it.deletedAt == null && it.status == "owned" }

            var updatedCount = 0
            var alertCount = 0

            for (vehicle in vehicles) {
                try {
                    val expenses = expenseDao.getExpensesForVehicleSync(vehicle.id)
                        .filter { it.deletedAt == null }
                    val effectiveSettings = settings ?: HoldingCostSettings(
                        id = UUID.randomUUID(),
                        dealerId = dealerId,
                        annualRatePercent = dailyRate.multiply(BigDecimal("36500")),
                        dailyRatePercent = dailyRate,
                        isEnabled = holdingCostEnabled,
                        createdAt = Date(),
                        updatedAt = Date()
                    )

                    val stats = InventoryMetricsCalculator.calculateInventoryStats(
                        vehicle = vehicle,
                        expenses = expenses,
                        settings = effectiveSettings
                    )

                    val existingStats = vehicleInventoryStatsDao.getByVehicleId(vehicle.id)
                    if (existingStats != null) {
                        vehicleInventoryStatsDao.delete(existingStats)
                    }
                    vehicleInventoryStatsDao.upsert(stats)
                    updatedCount++

                    val alerts = generateAlerts(
                        vehicleId = vehicle.id,
                        daysInInventory = stats.daysInInventory,
                        roiPercent = stats.roiPercent,
                        holdingCostAccumulated = stats.holdingCostAccumulated,
                        totalCost = stats.totalCost,
                        askingPrice = vehicle.askingPrice
                    )

                    for (alert in alerts) {
                        inventoryAlertDao.upsert(alert)
                        alertCount++
                    }

                } catch (e: Exception) {
                    Log.e(TAG, "Error processing vehicle ${vehicle.id}: ${e.message}", e)
                }
            }

            Log.i(TAG, "Updated $updatedCount vehicles, created $alertCount alerts")
            Result.success()

        } catch (e: Exception) {
            Log.e(TAG, "Error updating inventory stats: ${e.message}", e)
            Result.retry()
        }
    }

    private fun generateAlerts(
        vehicleId: UUID,
        daysInInventory: Int,
        roiPercent: BigDecimal?,
        holdingCostAccumulated: BigDecimal,
        totalCost: BigDecimal,
        askingPrice: BigDecimal?
    ): List<InventoryAlert> {
        val alerts = mutableListOf<InventoryAlert>()
        val now = Date()

        // Aging alerts
        when {
            daysInInventory >= 90 -> {
                alerts.add(
                    InventoryAlert(
                        id = UUID.randomUUID(),
                        vehicleId = vehicleId,
                        alertType = InventoryAlertType.aging_90_days,
                        severity = "high",
                        message = "Vehicle has been in inventory for $daysInInventory days. Consider aggressive pricing.",
                        isRead = false,
                        createdAt = now,
                        dismissedAt = null
                    )
                )
            }
            daysInInventory >= 60 -> {
                alerts.add(
                    InventoryAlert(
                        id = UUID.randomUUID(),
                        vehicleId = vehicleId,
                        alertType = InventoryAlertType.aging_60_days,
                        severity = "medium",
                        message = "Vehicle has been in inventory for $daysInInventory days. Monitor closely.",
                        isRead = false,
                        createdAt = now,
                        dismissedAt = null
                    )
                )
            }
        }

        // ROI alert
        roiPercent?.let { roi ->
            if (roi < BigDecimal("10")) {
                alerts.add(
                    InventoryAlert(
                        id = UUID.randomUUID(),
                        vehicleId = vehicleId,
                        alertType = InventoryAlertType.low_roi,
                        severity = if (roi < BigDecimal.ZERO) "high" else "medium",
                        message = "ROI is ${roi.setScale(1, java.math.RoundingMode.HALF_UP)}%. Consider reviewing pricing strategy.",
                        isRead = false,
                        createdAt = now,
                        dismissedAt = null
                    )
                )
            }
        }

        // High holding cost alert
        val holdingCostPercent = if (totalCost > BigDecimal.ZERO) {
            holdingCostAccumulated.multiply(BigDecimal("100")).divide(totalCost, 2, java.math.RoundingMode.HALF_UP)
        } else {
            BigDecimal.ZERO
        }

        if (holdingCostPercent > BigDecimal("5")) {
            alerts.add(
                InventoryAlert(
                    id = UUID.randomUUID(),
                    vehicleId = vehicleId,
                    alertType = InventoryAlertType.high_holding_cost,
                    severity = "medium",
                    message = "Holding costs are ${holdingCostPercent.setScale(1, java.math.RoundingMode.HALF_UP)}% of vehicle cost. Consider faster turnover.",
                    isRead = false,
                    createdAt = now,
                    dismissedAt = null
                )
            )
        }

        // Price reduction suggestion
        if (daysInInventory >= 45 && roiPercent != null && roiPercent > BigDecimal("20")) {
            alerts.add(
                InventoryAlert(
                    id = UUID.randomUUID(),
                    vehicleId = vehicleId,
                    alertType = InventoryAlertType.price_reduction_needed,
                    severity = "low",
                    message = "Vehicle has healthy margin. Consider a small price reduction to accelerate sale.",
                    isRead = false,
                    createdAt = now,
                    dismissedAt = null
                )
            )
        }

        return alerts
    }
}
