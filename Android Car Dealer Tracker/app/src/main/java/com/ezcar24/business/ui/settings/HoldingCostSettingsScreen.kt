package com.ezcar24.business.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.ui.theme.*
import java.math.RoundingMode

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HoldingCostSettingsScreen(
    onBack: () -> Unit,
    viewModel: HoldingCostSettingsViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val scrollState = rememberScrollState()

    // Handle save success
    LaunchedEffect(uiState.saveSuccess) {
        if (uiState.saveSuccess) {
            kotlinx.coroutines.delay(1500)
            viewModel.resetSaveSuccess()
        }
    }

    Scaffold(
        containerColor = EzcarBackgroundLight,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "Holding Cost Settings",
                        fontWeight = FontWeight.Bold,
                        color = EzcarNavy
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.Default.ArrowBack,
                            contentDescription = "Back",
                            tint = EzcarNavy
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = EzcarBackgroundLight
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(scrollState)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Info Card
            InfoCard()

            // Enable/Disable Toggle
            SettingsCard(
                title = "Enable Holding Cost Calculation",
                icon = Icons.Default.Calculate
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            "Calculate holding costs",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium
                        )
                        Text(
                            "Track daily cost of keeping vehicles in inventory",
                            style = MaterialTheme.typography.bodySmall,
                            color = Color.Gray
                        )
                    }
                    Switch(
                        checked = uiState.isEnabled,
                        onCheckedChange = { viewModel.toggleEnabled(it) },
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = Color.White,
                            checkedTrackColor = EzcarGreen,
                            uncheckedThumbColor = Color.White,
                            uncheckedTrackColor = Color.LightGray
                        )
                    )
                }
            }

            // Annual Rate Input
            SettingsCard(
                title = "Annual Rate",
                icon = Icons.Default.TrendingUp
            ) {
                Column {
                    Text(
                        "Annual percentage rate for holding cost calculation",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.Gray,
                        modifier = Modifier.padding(bottom = 8.dp)
                    )

                    OutlinedTextField(
                        value = uiState.annualRatePercent,
                        onValueChange = { viewModel.updateAnnualRate(it) },
                        label = { Text("Annual Rate (%)") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true,
                        enabled = uiState.isEnabled,
                        modifier = Modifier.fillMaxWidth(),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = EzcarGreen,
                            focusedLabelColor = EzcarGreen
                        ),
                        trailingIcon = {
                            Text(
                                "%",
                                style = MaterialTheme.typography.bodyMedium,
                                color = Color.Gray,
                                modifier = Modifier.padding(end = 12.dp)
                            )
                        }
                    )

                    // Default suggestion chips
                    if (uiState.isEnabled) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 8.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            SuggestionChip(
                                onClick = { viewModel.updateAnnualRate("10.00") },
                                label = { Text("10%") }
                            )
                            SuggestionChip(
                                onClick = { viewModel.updateAnnualRate("15.00") },
                                label = { Text("15%") }
                            )
                            SuggestionChip(
                                onClick = { viewModel.updateAnnualRate("20.00") },
                                label = { Text("20%") }
                            )
                            SuggestionChip(
                                onClick = { viewModel.updateAnnualRate("25.00") },
                                label = { Text("25%") }
                            )
                        }
                    }
                }
            }

            // Daily Rate Display
            SettingsCard(
                title = "Daily Rate",
                icon = Icons.Default.CalendarToday
            ) {
                Column {
                    Text(
                        "Automatically calculated from annual rate",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.Gray,
                        modifier = Modifier.padding(bottom = 8.dp)
                    )

                    val dailyRateFormatted = uiState.dailyRatePercent
                        .setScale(6, RoundingMode.HALF_UP)
                        .toString()

                    OutlinedTextField(
                        value = "$dailyRateFormatted%",
                        onValueChange = { },
                        readOnly = true,
                        enabled = false,
                        modifier = Modifier.fillMaxWidth(),
                        colors = OutlinedTextFieldDefaults.colors(
                            disabledTextColor = Color.Black,
                            disabledBorderColor = Color.LightGray,
                            disabledLabelColor = Color.Gray
                        )
                    )

                    Text(
                        "Formula: Annual Rate ÷ 365 days",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.Gray,
                        modifier = Modifier.padding(top = 8.dp)
                    )
                }
            }

            // Explanation Card
            ExplanationCard()

            Spacer(modifier = Modifier.weight(1f))

            // Error Message
            if (uiState.errorMessage != null) {
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = EzcarDanger.copy(alpha = 0.1f)
                    ),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            Icons.Default.Error,
                            contentDescription = null,
                            tint = EzcarDanger,
                            modifier = Modifier.size(24.dp)
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        Text(
                            uiState.errorMessage!!,
                            style = MaterialTheme.typography.bodyMedium,
                            color = EzcarDanger,
                            modifier = Modifier.weight(1f)
                        )
                        IconButton(onClick = { viewModel.dismissError() }) {
                            Icon(
                                Icons.Default.Close,
                                contentDescription = "Dismiss",
                                tint = EzcarDanger
                            )
                        }
                    }
                }
            }

            // Success Message
            if (uiState.saveSuccess) {
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = EzcarSuccess.copy(alpha = 0.1f)
                    ),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.Center
                    ) {
                        Icon(
                            Icons.Default.CheckCircle,
                            contentDescription = null,
                            tint = EzcarSuccess,
                            modifier = Modifier.size(24.dp)
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        Text(
                            "Settings saved successfully",
                            style = MaterialTheme.typography.bodyMedium,
                            color = EzcarSuccess,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
            }

            // Action Buttons
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                OutlinedButton(
                    onClick = onBack,
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = EzcarNavy
                    )
                ) {
                    Text("Cancel")
                }

                Button(
                    onClick = { viewModel.saveSettings() },
                    modifier = Modifier.weight(1f),
                    enabled = !uiState.isSaving && uiState.isEnabled,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = EzcarGreen,
                        contentColor = Color.White
                    )
                ) {
                    if (uiState.isSaving) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp,
                            color = Color.White
                        )
                    } else {
                        Text("Save Settings")
                    }
                }
            }
        }
    }
}

@Composable
private fun InfoCard() {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = EzcarBlueBright.copy(alpha = 0.1f)
        ),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.Top
        ) {
            Icon(
                Icons.Default.Info,
                contentDescription = null,
                tint = EzcarBlueBright,
                modifier = Modifier.size(24.dp)
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column {
                Text(
                    "About Holding Costs",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = EzcarNavy
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    "Holding costs represent the daily expense of keeping a vehicle in your inventory. " +
                    "This includes capital costs, insurance, storage, and depreciation.",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.Gray
                )
            }
        }
    }
}

@Composable
private fun SettingsCard(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    content: @Composable () -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = Color.White
        ),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(bottom = 16.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .background(EzcarGreen.copy(alpha = 0.1f), RoundedCornerShape(8.dp)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = EzcarGreen,
                        modifier = Modifier.size(24.dp)
                    )
                }
                Spacer(modifier = Modifier.width(12.dp))
                Text(
                    title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = EzcarNavy
                )
            }
            content()
        }
    }
}

@Composable
private fun ExplanationCard() {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = Color.White
        ),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(
                "How It Works",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = EzcarNavy,
                modifier = Modifier.padding(bottom = 12.dp)
            )

            val explanations = listOf(
                Triple("1", "Daily Rate Calculation", "Annual rate divided by 365 days"),
                Triple("2", "Vehicle Cost Base", "Purchase price + improvement expenses"),
                Triple("3", "Daily Accumulation", "Cost base × daily rate"),
                Triple("4", "Total Holding Cost", "Sum of daily costs since purchase")
            )

            explanations.forEach { (number, title, description) ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 8.dp),
                    verticalAlignment = Alignment.Top
                ) {
                    Box(
                        modifier = Modifier
                            .size(28.dp)
                            .background(EzcarNavy.copy(alpha = 0.1f), RoundedCornerShape(14.dp)),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            number,
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.Bold,
                            color = EzcarNavy
                        )
                    }
                    Spacer(modifier = Modifier.width(12.dp))
                    Column {
                        Text(
                            title,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium,
                            color = Color.Black
                        )
                        Text(
                            description,
                            style = MaterialTheme.typography.bodySmall,
                            color = Color.Gray
                        )
                    }
                }
            }

            HorizontalDivider(
                modifier = Modifier.padding(vertical = 12.dp),
                color = Color.LightGray.copy(alpha = 0.3f)
            )

            Text(
                "Example: With 15% annual rate on a $10,000 vehicle:",
                style = MaterialTheme.typography.bodySmall,
                color = Color.Gray
            )
            Text(
                "Daily cost = $10,000 × (15% ÷ 365) = $4.11 per day",
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.Medium,
                color = EzcarNavy,
                modifier = Modifier.padding(top = 4.dp)
            )
        }
    }
}
