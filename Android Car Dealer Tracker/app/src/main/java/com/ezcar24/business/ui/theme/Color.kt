package com.ezcar24.business.ui.theme

import androidx.compose.ui.graphics.Color

val EzcarNavy = Color(0xFF17478C) // Primary Light
val EzcarBlueLight = Color(0xFF4785E6) // Primary Dark
val EzcarBlueBright = Color(0xFF2E85EB) // Secondary
val EzcarOrange = Color(0xFFFA8C38) // Accent
val EzcarGreen = Color(0xFF00D26A) // Dealer Green
val EzcarPurple = Color(0xFF856DF2)
val EzcarSuccess = Color(0xFF29AB63)
val EzcarWarning = Color(0xFFFFD142)
val EzcarDanger = Color(0xFFE63342)

val EzcarBackgroundLight = Color(0xFFF2F2F7) // systemGroupedBackground light
val EzcarBackground = EzcarBackgroundLight // Alias for convenience
val EzcarBackgroundDark = Color(0xFF000000) // systemGroupedBackground dark
val EzcarSurfaceLight = Color(0xFFFFFFFF)
val EzcarSurfaceDark = Color(0xFF1C1C1E)

fun getCategoryColor(category: String?): Color {
    return when (category?.lowercase()?.trim()) {
        "fuel", "gas", "petrol" -> EzcarOrange
        "repair", "maintenance", "service", "parts" -> EzcarDanger
        "insurance" -> EzcarPurple
        "tax", "registration", "inspection" -> EzcarBlueBright
        "cleaning", "wash", "detail" -> Color(0xFF30B0C7) // Cyan-ish
        "parking", "toll", "fine", "fees" -> Color.Gray
        else -> EzcarGreen
    }
}