package com.ezcar24.business.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.util.AppLanguage
import com.ezcar24.business.util.AppRegion
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.math.BigDecimal

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RegionLanguageSettingsScreen(
    onBack: () -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val languageOptions = remember { listOf(AppLanguage.ENGLISH, AppLanguage.RUSSIAN) }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "Region & Language",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back"
                        )
                    }
                },
                actions = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.Default.Check,
                            contentDescription = "Done",
                            tint = EzcarGreen
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background
                )
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            item {
                Surface(
                    color = MaterialTheme.colorScheme.surface,
                    shape = RoundedCornerShape(22.dp),
                    shadowElevation = 8.dp,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = "This affects currency formatting, mileage units, and app language.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 18.dp, vertical = 16.dp)
                    )
                }
            }

            item {
                SettingsSection(title = "Currency / Region") {
                    AppRegion.entries.forEachIndexed { index, region ->
                        RegionOptionRow(
                            symbol = region.currencySymbol,
                            title = region.displayName,
                            subtitle = "${region.currencyCode} • ${if (region.usesKilometers) "km" else "miles"}",
                            isSelected = regionState.selectedRegion == region,
                            onClick = { regionSettingsManager.updateRegion(region) }
                        )
                        if (index != AppRegion.entries.lastIndex) {
                            SectionDivider()
                        }
                    }
                }
            }

            item {
                SettingsSection(title = "Language") {
                    languageOptions.forEachIndexed { index, language ->
                        RegionOptionRow(
                            symbol = language.nativeName.take(1),
                            title = language.nativeName,
                            subtitle = if (language == AppLanguage.ENGLISH) {
                                "System fallback language"
                            } else {
                                "App content language"
                            },
                            isSelected = regionState.selectedLanguage == language,
                            onClick = { regionSettingsManager.updateLanguage(language) }
                        )
                        if (index != languageOptions.lastIndex) {
                            SectionDivider()
                        }
                    }
                }
            }

            item {
                SettingsSection(title = "Preview") {
                    PreviewValueRow(
                        label = "Currency",
                        value = regionState.selectedRegion.currencyCode
                    )
                    SectionDivider()
                    PreviewValueRow(
                        label = "Mileage",
                        value = if (regionState.selectedRegion.usesKilometers) "Kilometers" else "Miles"
                    )
                    SectionDivider()
                    PreviewValueRow(
                        label = "Example",
                        value = regionSettingsManager.formatCurrency(BigDecimal("12345.67"))
                    )
                }
            }
        }
    }
}

@Composable
private fun RegionOptionRow(
    symbol: String,
    title: String,
    subtitle: String,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .background(EzcarNavy.copy(alpha = 0.08f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = symbol,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = EzcarNavy
            )
        }
        Spacer(modifier = Modifier.size(14.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (isSelected) {
            Icon(
                imageVector = Icons.Default.CheckCircle,
                contentDescription = null,
                tint = EzcarBlueBright
            )
        }
    }
}

@Composable
private fun PreviewValueRow(
    label: String,
    value: String
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 18.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = Color.Gray
        )
    }
}
