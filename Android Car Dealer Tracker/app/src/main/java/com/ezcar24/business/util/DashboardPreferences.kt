package com.ezcar24.business.util

import android.content.Context

object DashboardPreferences {
    const val PREFERENCES_NAME = "ezcar24_dashboard"
    const val CAR_ENABLED_KEY = "dashboard_car_enabled"
    const val CAR_MOVING_KEY = "dashboard_car_moving"

    fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
}
