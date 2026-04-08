package com.ezcar24.business.ui.theme

import androidx.compose.ui.graphics.Color

val EzcarNavy = Color(0xFF17478C)
val EzcarBlueLight = Color(0xFF4785E6)
val EzcarBlueBright = Color(0xFF2E85EB)
val EzcarOrange = Color(0xFFFA8C38)
val EzcarGreen = Color(0xFF00D26A)
val EzcarPurple = Color(0xFF856DF2)
val EzcarSuccess = Color(0xFF29AB63)
val EzcarWarning = Color(0xFFFFD142)
val EzcarDanger = Color(0xFFE63342)

val EzcarBackgroundLight = Color(0xFFF5F5FA)
val EzcarBackground = EzcarBackgroundLight
val EzcarBackgroundDark = Color(0xFF000000)
val EzcarSurfaceLight = Color(0xFFFFFFFF)
val EzcarSurfaceDark = Color(0xFF1F1F24)
val EzcarSurfaceMutedLight = Color(0xFFF0F1F6)
val EzcarSurfaceMutedDark = Color(0xFF121217)
val EzcarBorderLight = Color(0x14000000)
val EzcarBorderDark = Color(0x33FFFFFF)
val EzcarTextPrimaryLight = Color(0xFF111111)
val EzcarTextSecondaryLight = Color(0xFF6B7280)
val EzcarTextPrimaryDark = Color(0xFFFFFFFF)
val EzcarTextSecondaryDark = Color(0xFFB4BAC7)

fun vehicleStatusColor(status: String?): Color {
    return when (status?.lowercase()?.trim()) {
        "reserved" -> EzcarSuccess
        "on_sale", "available" -> EzcarBlueBright
        "sold" -> EzcarSuccess
        "in_transit" -> EzcarWarning
        "under_service" -> EzcarPurple
        else -> Color.Gray
    }
}

fun vehicleStatusBackground(status: String?): Color {
    return vehicleStatusColor(status).copy(alpha = 0.14f)
}

fun getCategoryColor(category: String?): Color {
    return when (category?.lowercase()?.trim()) {
        "fuel", "gas", "petrol" -> EzcarOrange
        "repair", "maintenance", "service", "parts" -> EzcarDanger
        "insurance" -> EzcarPurple
        "tax", "registration", "inspection" -> EzcarBlueBright
        "cleaning", "wash", "detail" -> Color(0xFF30B0C7)
        "parking", "toll", "fine", "fees" -> Color.Gray
        else -> EzcarGreen
    }
}
