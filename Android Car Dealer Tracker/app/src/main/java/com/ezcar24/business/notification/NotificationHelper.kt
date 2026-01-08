package com.ezcar24.business.notification

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.ezcar24.business.MainActivity
import com.ezcar24.business.R
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class NotificationHelper @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    companion object {
        const val CHANNEL_CLIENT_REMINDERS = "client_reminders"
        const val CHANNEL_DEBT_DEADLINES = "debt_deadlines"
        
        private const val NOTIFICATION_PREFIX = "ezcar24.notification"
        
        fun clientReminderId(id: UUID): Int = "client.${id}".hashCode()
        fun debtDueId(id: UUID): Int = "debt.${id}".hashCode()
    }

    init {
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val clientChannel = NotificationChannel(
                CHANNEL_CLIENT_REMINDERS,
                "Client Reminders",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Reminders for client follow-ups"
            }

            val debtChannel = NotificationChannel(
                CHANNEL_DEBT_DEADLINES,
                "Debt Deadlines",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for upcoming debt payments and collections"
            }

            notificationManager.createNotificationChannel(clientChannel)
            notificationManager.createNotificationChannel(debtChannel)
        }
    }

    fun showClientReminderNotification(
        id: UUID,
        clientName: String,
        reminderTitle: String
    ) {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_CLIENT_REMINDERS)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle("Client Reminder")
            .setContentText("$clientName • $reminderTitle")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        notificationManager.notify(clientReminderId(id), notification)
    }

    fun showDebtDueNotification(
        id: UUID,
        counterpartyName: String,
        amount: String,
        isOwedToMe: Boolean
    ) {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val title = if (isOwedToMe) "Debt Collection Due" else "Debt Payment Due"

        val notification = NotificationCompat.Builder(context, CHANNEL_DEBT_DEADLINES)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText("$counterpartyName • $amount")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        notificationManager.notify(debtDueId(id), notification)
    }

    fun cancelNotification(notificationId: Int) {
        notificationManager.cancel(notificationId)
    }

    fun cancelAll() {
        notificationManager.cancelAll()
    }
}
