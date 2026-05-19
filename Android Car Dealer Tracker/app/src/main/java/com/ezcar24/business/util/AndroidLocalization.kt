package com.ezcar24.business.util

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import java.security.MessageDigest
import java.util.Locale

@Composable
fun localizedUiString(source: String): String {
    val context = LocalContext.current
    val resourceId = remember(source, context) {
        context.localizedUiStringResourceId(source)
    }
    return if (resourceId == 0) source else context.getString(resourceId)
}

@Composable
fun localizedUiString(source: String, vararg formatArgs: Any): String {
    val context = LocalContext.current
    val resourceId = remember(source, context) {
        context.localizedUiStringResourceId(source)
    }
    return if (resourceId == 0) {
        String.format(Locale.getDefault(), source, *formatArgs)
    } else {
        context.getString(resourceId, *formatArgs)
    }
}

fun Context.localizedUiString(source: String): String {
    val resourceId = localizedUiStringResourceId(source)
    return if (resourceId == 0) source else getString(resourceId)
}

fun Context.localizedUiString(source: String, vararg formatArgs: Any): String {
    val resourceId = localizedUiStringResourceId(source)
    return if (resourceId == 0) {
        String.format(Locale.getDefault(), source, *formatArgs)
    } else {
        getString(resourceId, *formatArgs)
    }
}

@Composable
fun localizedInventoryAlertMessage(message: String): String {
    inventoryAlertPatterns.forEach { pattern ->
        val match = pattern.regex.matchEntire(message) ?: return@forEach
        val args = match.groupValues.drop(1).map { value ->
            val parsedInt = value.toIntOrNull()
            if (parsedInt != null) parsedInt as Any else value as Any
        }.toTypedArray()
        return localizedUiString(pattern.template, *args)
    }
    return localizedUiString(message)
}

fun localizationResourceName(source: String): String {
    val slug = source
        .lowercase(Locale.US)
        .replace(Regex("[^a-z0-9]+"), "_")
        .trim('_')
        .take(42)
        .ifEmpty { "text" }
    val digest = MessageDigest.getInstance("SHA-1")
        .digest(source.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
        .take(10)
    return "l10n_${slug}_$digest"
}

private fun Context.localizedUiStringResourceId(source: String): Int {
    return resources.getIdentifier(localizationResourceName(source), "string", packageName)
}

private data class InventoryAlertPattern(
    val regex: Regex,
    val template: String
)

private val inventoryAlertPatterns = listOf(
    InventoryAlertPattern(
        Regex("""Vehicle has been in inventory for (\d+) days\. Consider aggressive pricing\. """.trim()),
        "Vehicle has been in inventory for %d days. Consider aggressive pricing."
    ),
    InventoryAlertPattern(
        Regex("""Vehicle has been in inventory for (\d+) days\. Monitor closely\. """.trim()),
        "Vehicle has been in inventory for %d days. Monitor closely."
    ),
    InventoryAlertPattern(
        Regex("""Vehicle has been in inventory for (\d+) days\. Review pricing strategy\. """.trim()),
        "Vehicle has been in inventory for %d days. Review pricing strategy."
    ),
    InventoryAlertPattern(
        Regex("""ROI is ([0-9.]+)%\. Consider reviewing pricing strategy\. """.trim()),
        "ROI is %s%%. Consider reviewing pricing strategy."
    ),
    InventoryAlertPattern(
        Regex("""Projected ROI is ([0-9.]+)%\. Consider cost reduction or price increase\. """.trim()),
        "Projected ROI is %s%%. Consider cost reduction or price increase."
    ),
    InventoryAlertPattern(
        Regex("""Holding costs are ([0-9.]+)% of vehicle cost\. Consider faster turnover\. """.trim()),
        "Holding costs are %s%% of vehicle cost. Consider faster turnover."
    ),
    InventoryAlertPattern(
        Regex("""Holding cost is ([0-9.]+)% of total cost\. Consider faster turnover\. """.trim()),
        "Holding cost is %s%% of total cost. Consider faster turnover."
    )
)
