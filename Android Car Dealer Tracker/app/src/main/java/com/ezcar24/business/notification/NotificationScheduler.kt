package com.ezcar24.business.notification

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.ezcar24.business.data.local.ClientReminder
import com.ezcar24.business.data.local.ClientReminderDao
import com.ezcar24.business.data.local.Debt
import com.ezcar24.business.data.local.DebtDao
import dagger.hilt.android.qualifiers.ApplicationContext
import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Singleton
class NotificationScheduler @Inject constructor(
    @ApplicationContext private val context: Context,
    private val notificationPreferences: NotificationPreferences,
    private val clientReminderDao: ClientReminderDao,
    private val debtDao: DebtDao
) {
    private val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    private val tag = "NotificationScheduler"

    companion object {
        const val ACTION_SHOW_NOTIFICATION = "com.ezcar24.business.SHOW_NOTIFICATION"
        const val EXTRA_NOTIFICATION_TYPE = "notification_type"
        const val EXTRA_ID = "notification_id"
        const val EXTRA_TITLE = "notification_title"
        const val EXTRA_BODY = "notification_body"
        const val EXTRA_IS_OWED_TO_ME = "is_owed_to_me"
        
        const val TYPE_CLIENT_REMINDER = "client_reminder"
        const val TYPE_DEBT_DUE = "debt_due"
    }

    suspend fun refreshAll() = withContext(Dispatchers.IO) {
        if (!notificationPreferences.isEnabled) {
            cancelAll()
            return@withContext
        }

        cancelAll()

        val now = Date()

        // Schedule client reminders
        val reminders = clientReminderDao.getUpcomingReminders(now)
        for (reminder in reminders) {
            scheduleClientReminder(reminder)
        }

        // Schedule debt deadlines
        val debts = debtDao.getUpcomingDebts(now)
        for (debt in debts) {
            scheduleDebtDue(debt)
        }

        Log.d(tag, "Scheduled ${reminders.size} reminders and ${debts.size} debt notifications")
    }

    private fun scheduleClientReminder(reminder: ClientReminder) {
        val dueDate = reminder.dueDate
        if (dueDate.time <= System.currentTimeMillis()) return

        val intent = Intent(context, NotificationReceiver::class.java).apply {
            action = ACTION_SHOW_NOTIFICATION
            putExtra(EXTRA_NOTIFICATION_TYPE, TYPE_CLIENT_REMINDER)
            putExtra(EXTRA_ID, reminder.id.toString())
            putExtra(EXTRA_TITLE, reminder.title)
            putExtra(EXTRA_BODY, reminder.notes ?: "Follow up")
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            NotificationHelper.clientReminderId(reminder.id),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        scheduleExactAlarm(dueDate.time, pendingIntent)
    }

    private fun scheduleDebtDue(debt: Debt) {
        val dueDate = debt.dueDate ?: return
        if (dueDate.time <= System.currentTimeMillis()) return

        val currencyFormat = NumberFormat.getCurrencyInstance(Locale.US)
        val amountStr = currencyFormat.format(debt.amount)
        val isOwedToMe = debt.direction == "owed_to_me"

        val intent = Intent(context, NotificationReceiver::class.java).apply {
            action = ACTION_SHOW_NOTIFICATION
            putExtra(EXTRA_NOTIFICATION_TYPE, TYPE_DEBT_DUE)
            putExtra(EXTRA_ID, debt.id.toString())
            putExtra(EXTRA_TITLE, debt.counterpartyName)
            putExtra(EXTRA_BODY, amountStr)
            putExtra(EXTRA_IS_OWED_TO_ME, isOwedToMe)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            NotificationHelper.debtDueId(debt.id),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        scheduleExactAlarm(dueDate.time, pendingIntent)
    }

    private fun scheduleExactAlarm(triggerAtMillis: Long, pendingIntent: PendingIntent) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (alarmManager.canScheduleExactAlarms()) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                } else {
                    // Fallback to inexact alarm
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                }
            } else {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
            }
        } catch (e: SecurityException) {
            Log.e(tag, "Cannot schedule exact alarm: ${e.message}")
            // Fallback to inexact
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent
            )
        }
    }

    fun cancelAll() {
        // Note: We can't enumerate all pending intents, but new schedules will replace old ones
        Log.d(tag, "Cancel all notifications requested")
    }
}
