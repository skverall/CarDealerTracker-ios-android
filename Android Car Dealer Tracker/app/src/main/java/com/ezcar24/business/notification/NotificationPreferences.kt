package com.ezcar24.business.notification

import android.content.Context
import android.content.SharedPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class NotificationPreferences @Inject constructor(
    @ApplicationContext context: Context
) {
    private val prefs: SharedPreferences = context.getSharedPreferences(
        "notification_prefs",
        Context.MODE_PRIVATE
    )

    companion object {
        private const val KEY_ENABLED = "notificationsEnabled"
        private const val KEY_FEEDBACK_NUDGE_LAST_OPENED_AT = "feedbackNudgeLastOpenedAt"
        private const val KEY_FEEDBACK_NUDGE_NEXT_TRIGGER_AT = "feedbackNudgeNextTriggerAt"
        const val FEEDBACK_NUDGE_INTERVAL_DAYS = 4
    }

    var isEnabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, false)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    var feedbackNudgeLastOpenedAt: Long?
        get() = prefs.getLong(KEY_FEEDBACK_NUDGE_LAST_OPENED_AT, 0L).takeIf { it > 0L }
        set(value) {
            prefs.edit().apply {
                if (value != null) {
                    putLong(KEY_FEEDBACK_NUDGE_LAST_OPENED_AT, value)
                } else {
                    remove(KEY_FEEDBACK_NUDGE_LAST_OPENED_AT)
                }
            }.apply()
        }

    var feedbackNudgeNextTriggerAt: Long?
        get() = prefs.getLong(KEY_FEEDBACK_NUDGE_NEXT_TRIGGER_AT, 0L).takeIf { it > 0L }
        set(value) {
            prefs.edit().apply {
                if (value != null) {
                    putLong(KEY_FEEDBACK_NUDGE_NEXT_TRIGGER_AT, value)
                } else {
                    remove(KEY_FEEDBACK_NUDGE_NEXT_TRIGGER_AT)
                }
            }.apply()
        }

    fun recordFeedbackBoardOpened() {
        feedbackNudgeLastOpenedAt = System.currentTimeMillis()
        feedbackNudgeNextTriggerAt = null
    }
}
