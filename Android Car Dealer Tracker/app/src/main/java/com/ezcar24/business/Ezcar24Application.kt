package com.ezcar24.business

import android.app.Application
import com.ezcar24.business.util.RegionSettingsEntryPoint
import com.google.firebase.crashlytics.FirebaseCrashlytics
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class Ezcar24Application : Application() {
    override fun onCreate() {
        super.onCreate()

        FirebaseCrashlytics.getInstance().setCrashlyticsCollectionEnabled(true)

        EntryPointAccessors.fromApplication(
            this,
            RegionSettingsEntryPoint::class.java
        ).regionSettingsManager().initialize()
    }
}
