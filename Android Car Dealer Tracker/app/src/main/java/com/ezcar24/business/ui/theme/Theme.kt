package com.ezcar24.business.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

private val DarkColorScheme = darkColorScheme(
    primary = EzcarBlueLight,
    secondary = EzcarBlueBright,
    tertiary = EzcarOrange,
    background = EzcarBackgroundDark,
    surface = EzcarSurfaceDark,
    surfaceVariant = EzcarSurfaceMutedDark,
    outline = EzcarBorderDark,
    onPrimary = Color.White,
    onSecondary = Color.White,
    onTertiary = Color.White,
    onBackground = Color.White,
    onSurface = Color.White,
    onSurfaceVariant = EzcarTextSecondaryDark
)

private val LightColorScheme = lightColorScheme(
    primary = EzcarNavy,
    secondary = EzcarBlueBright,
    tertiary = EzcarOrange,
    background = EzcarBackgroundLight,
    surface = EzcarSurfaceLight,
    surfaceVariant = EzcarSurfaceMutedLight,
    outline = EzcarBorderLight,
    onPrimary = Color.White,
    onSecondary = Color.White,
    onTertiary = Color.White,
    onBackground = EzcarTextPrimaryLight,
    onSurface = EzcarTextPrimaryLight,
    onSurfaceVariant = EzcarTextSecondaryLight
)

@Composable
fun CarDealerTrackerAndroidTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = Color.Transparent.toArgb()
            window.navigationBarColor = Color.Transparent.toArgb()
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !darkTheme
                isAppearanceLightNavigationBars = !darkTheme
            }
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        content = content
    )
}
