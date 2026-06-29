package com.ezcar24.business

import android.app.Application
import com.ezcar24.business.analytics.OnboardingAnalytics
import com.ezcar24.business.util.RegionSettingsEntryPoint
import com.google.firebase.crashlytics.FirebaseCrashlytics
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class Ezcar24Application : Application() {
    override fun onCreate() {
        super.onCreate()

        if (BuildConfig.FIREBASE_ENABLED) {
            FirebaseCrashlytics.getInstance().setCrashlyticsCollectionEnabled(true)
        }

        val regionSettingsManager = EntryPointAccessors.fromApplication(
            this,
            RegionSettingsEntryPoint::class.java
        ).regionSettingsManager()
        regionSettingsManager.initialize()
        OnboardingAnalytics.configure(this, regionSettingsManager.state.value)
    }
}
