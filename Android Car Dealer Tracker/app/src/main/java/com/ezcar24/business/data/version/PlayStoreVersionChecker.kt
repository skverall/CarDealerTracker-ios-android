package com.ezcar24.business.data.version

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.net.URL
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Service to check Play Store for latest version and determine if update is required.
 * Matches iOS AppStoreVersionChecker behavior.
 */
@Singleton
class PlayStoreVersionChecker @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val _isUpdateRequired = MutableStateFlow(false)
    val isUpdateRequired = _isUpdateRequired.asStateFlow()

    private val _playStoreVersion = MutableStateFlow<String?>(null)
    val playStoreVersion = _playStoreVersion.asStateFlow()

    private val _isChecking = MutableStateFlow(false)
    val isChecking = _isChecking.asStateFlow()

    private val packageName = context.packageName

    /**
     * Current app version from PackageManager
     */
    val currentVersion: String
        get() = try {
            val packageInfo = context.packageManager.getPackageInfo(packageName, 0)
            packageInfo.versionName ?: "0.0.0"
        } catch (e: PackageManager.NameNotFoundException) {
            "0.0.0"
        }

    /**
     * Check Play Store for updates.
     * Note: Google Play doesn't have a public API like iTunes. We use a simple web scrape
     * of the Play Store page to get the version. For production, consider using
     * Google Play Core library's in-app updates.
     */
    suspend fun checkForUpdate() {
        _isChecking.value = true
        try {
            val storeVersion = fetchPlayStoreVersion()
            _playStoreVersion.value = storeVersion

            if (storeVersion != null && isVersionGreaterThan(storeVersion, currentVersion)) {
                _isUpdateRequired.value = true
            } else {
                _isUpdateRequired.value = false
            }
        } catch (e: Exception) {
            Log.e("PlayStoreVersionChecker", "Failed to check Play Store version", e)
        } finally {
            _isChecking.value = false
        }
    }

    /**
     * Fetch version from Play Store page
     */
    private suspend fun fetchPlayStoreVersion(): String? = withContext(Dispatchers.IO) {
        try {
            val url = URL("https://play.google.com/store/apps/details?id=$packageName&hl=en")
            val html = url.readText()
            
            // Look for pattern like: "Current Version</div><span class="...">[[\d.]+]]"
            // or look for the JSON-LD data that contains the version
            val versionRegex = Regex("\\[\\[\\[\"(\\d+\\.\\d+\\.?\\d*)\"\\]\\]")
            val match = versionRegex.find(html)
            match?.groupValues?.getOrNull(1)
        } catch (e: Exception) {
            Log.e("PlayStoreVersionChecker", "Error fetching Play Store version", e)
            null
        }
    }

    /**
     * Compare two version strings (e.g., "1.2.3" vs "1.2.2")
     * Returns true if v1 > v2
     */
    private fun isVersionGreaterThan(v1: String, v2: String): Boolean {
        val v1Components = v1.split(".").mapNotNull { it.toIntOrNull() }
        val v2Components = v2.split(".").mapNotNull { it.toIntOrNull() }

        val maxCount = maxOf(v1Components.size, v2Components.size)

        for (i in 0 until maxCount) {
            val v1Part = v1Components.getOrElse(i) { 0 }
            val v2Part = v2Components.getOrElse(i) { 0 }

            if (v1Part > v2Part) return true
            if (v1Part < v2Part) return false
        }

        return false
    }

    /**
     * Open Play Store page for this app
     */
    fun openPlayStore() {
        try {
            // Try Play Store app first
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse("market://details?id=$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            // Fallback to browser
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse("https://play.google.com/store/apps/details?id=$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }
    }
}
