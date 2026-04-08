package com.ezcar24.business.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarWarning
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarDanger
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.math.BigDecimal
import java.util.Locale

@Composable
fun HoldingCostIndicator(
    holdingCost: BigDecimal,
    totalCost: BigDecimal,
    dailyRate: BigDecimal? = null,
    daysInInventory: Int = 0,
    modifier: Modifier = Modifier
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val percentage = if (totalCost.compareTo(BigDecimal.ZERO) > 0) {
        holdingCost
            .multiply(BigDecimal(100))
            .divide(totalCost, 2, BigDecimal.ROUND_HALF_UP)
            .toFloat() / 100f
    } else {
        0f
    }

    val progressColor = when {
        percentage < 0.05f -> EzcarGreen
        percentage < 0.10f -> EzcarWarning
        percentage < 0.15f -> EzcarOrange
        else -> EzcarDanger
    }

    Column(modifier = modifier) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Holding Cost",
                style = MaterialTheme.typography.bodyMedium,
                color = Color.Gray
            )
            Text(
                text = regionSettingsManager.formatCurrency(holdingCost),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = progressColor
            )
        }

        Spacer(modifier = Modifier.height(4.dp))

        LinearProgressIndicator(
            progress = { percentage.coerceIn(0f, 1f) },
            modifier = Modifier
                .fillMaxWidth()
                .height(6.dp),
            color = progressColor,
            trackColor = progressColor.copy(alpha = 0.2f),
            drawStopIndicator = {}
        )

        Spacer(modifier = Modifier.height(4.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            val percentageText = String.format(Locale.US, "%.1f%%", percentage * 100)
            Text(
                text = "$percentageText of total cost",
                style = MaterialTheme.typography.bodySmall,
                color = Color.Gray
            )

            if (dailyRate != null && dailyRate > BigDecimal.ZERO) {
                Text(
                    text = "${regionSettingsManager.formatCurrency(dailyRate)}/day",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.Gray
                )
            }
        }
    }
}

@Composable
fun HoldingCostCard(
    holdingCost: BigDecimal,
    totalCost: BigDecimal,
    dailyRate: BigDecimal? = null,
    daysInInventory: Int = 0,
    modifier: Modifier = Modifier
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val percentage = if (totalCost.compareTo(BigDecimal.ZERO) > 0) {
        holdingCost
            .multiply(BigDecimal(100))
            .divide(totalCost, 2, BigDecimal.ROUND_HALF_UP)
    } else {
        BigDecimal.ZERO
    }

    val cardColor = when {
        percentage.compareTo(BigDecimal("5")) < 0 -> EzcarGreen
        percentage.compareTo(BigDecimal("10")) < 0 -> EzcarWarning
        percentage.compareTo(BigDecimal("15")) < 0 -> EzcarOrange
        else -> EzcarDanger
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(cardColor.copy(alpha = 0.1f), RoundedCornerShape(12.dp))
            .padding(16.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Holding Cost",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = cardColor
            )
            Text(
                text = "${percentage.toInt()}%",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = cardColor
            )
        }

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = regionSettingsManager.formatCurrency(holdingCost),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            color = Color.Black
        )

        Spacer(modifier = Modifier.height(4.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = "$daysInInventory days in inventory",
                style = MaterialTheme.typography.bodySmall,
                color = Color.Gray
            )

            if (dailyRate != null && dailyRate > BigDecimal.ZERO) {
                Text(
                    text = "${regionSettingsManager.formatCurrency(dailyRate)}/day",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.Gray
                )
            }
        }
    }
}
