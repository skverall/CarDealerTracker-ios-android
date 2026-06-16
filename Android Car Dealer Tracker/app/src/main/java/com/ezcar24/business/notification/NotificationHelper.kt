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
import com.ezcar24.business.util.localizedUiString

@Singleton
class NotificationHelper @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    companion object {
        const val CHANNEL_CLIENT_REMINDERS = "client_reminders"
        const val CHANNEL_DEBT_DEADLINES = "debt_deadlines"
        const val CHANNEL_FEEDBACK = "feedback"
        
        private const val NOTIFICATION_PREFIX = "ezcar24.notification"
        
        fun clientReminderId(id: UUID): Int = "client.${id}".hashCode()
        fun debtDueId(id: UUID): Int = "debt.${id}".hashCode()
        fun feedbackNudgeId(): Int = "feedback.board.nudge".hashCode()
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

            val feedbackChannel = NotificationChannel(
                CHANNEL_FEEDBACK,
                "Ideas & Voting",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Occasional reminders to share product ideas"
            }

            notificationManager.createNotificationChannel(clientChannel)
            notificationManager.createNotificationChannel(debtChannel)
            notificationManager.createNotificationChannel(feedbackChannel)
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
            .setContentTitle(context.localizedUiString("Client Reminder"))
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

    fun showFeedbackBoardNudgeNotification() {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_NAVIGATE_ROUTE, MainActivity.ROUTE_FEEDBACK_BOARD)
        }
        val pendingIntent = PendingIntent.getActivity(
            context, feedbackNudgeId(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_FEEDBACK)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(context.localizedUiString("Tell us what to build next"))
            .setContentText(context.localizedUiString("Suggest features and vote on requests from other dealers"))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        notificationManager.notify(feedbackNudgeId(), notification)
    }

    fun cancelNotification(notificationId: Int) {
        notificationManager.cancel(notificationId)
    }

    fun cancelAll() {
        notificationManager.cancelAll()
    }
}
