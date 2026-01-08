package com.ezcar24.business.notification

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import dagger.hilt.android.AndroidEntryPoint
import java.util.UUID
import javax.inject.Inject

@AndroidEntryPoint
class NotificationReceiver : BroadcastReceiver() {

    @Inject
    lateinit var notificationHelper: NotificationHelper

    @Inject
    lateinit var notificationScheduler: NotificationScheduler

    private val tag = "NotificationReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(tag, "Received intent: ${intent.action}")

        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> {
                // Re-schedule all notifications after device reboot
                // This needs to be done in a coroutine, but BroadcastReceiver is short-lived
                // For boot, we'll use WorkManager to reschedule
                Log.d(tag, "Boot completed - notifications will be rescheduled on app launch")
            }

            NotificationScheduler.ACTION_SHOW_NOTIFICATION -> {
                handleShowNotification(intent)
            }
        }
    }

    private fun handleShowNotification(intent: Intent) {
        val type = intent.getStringExtra(NotificationScheduler.EXTRA_NOTIFICATION_TYPE)
        val idString = intent.getStringExtra(NotificationScheduler.EXTRA_ID)
        val title = intent.getStringExtra(NotificationScheduler.EXTRA_TITLE) ?: ""
        val body = intent.getStringExtra(NotificationScheduler.EXTRA_BODY) ?: ""

        if (idString == null) {
            Log.e(tag, "Notification ID is null")
            return
        }

        val id = try {
            UUID.fromString(idString)
        } catch (e: IllegalArgumentException) {
            Log.e(tag, "Invalid UUID: $idString")
            return
        }

        when (type) {
            NotificationScheduler.TYPE_CLIENT_REMINDER -> {
                notificationHelper.showClientReminderNotification(
                    id = id,
                    clientName = title,
                    reminderTitle = body
                )
            }

            NotificationScheduler.TYPE_DEBT_DUE -> {
                val isOwedToMe = intent.getBooleanExtra(
                    NotificationScheduler.EXTRA_IS_OWED_TO_ME, 
                    false
                )
                notificationHelper.showDebtDueNotification(
                    id = id,
                    counterpartyName = title,
                    amount = body,
                    isOwedToMe = isOwedToMe
                )
            }

            else -> {
                Log.w(tag, "Unknown notification type: $type")
            }
        }
    }
}
