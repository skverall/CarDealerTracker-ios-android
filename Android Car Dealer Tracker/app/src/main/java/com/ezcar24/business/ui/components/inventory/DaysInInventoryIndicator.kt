package com.ezcar24.business.ui.components.inventory

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ProgressIndicatorDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ezcar24.business.ui.theme.EzcarDanger
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarWarning

@Composable
fun DaysInInventoryIndicator(
    days: Int,
    modifier: Modifier = Modifier,
    showLabel: Boolean = true
) {
    val (color, label) = when {
        days <= 30 -> EzcarGreen to "Fresh"
        days <= 60 -> EzcarWarning to "Aging"
        days <= 90 -> EzcarOrange to "Old"
        else -> EzcarDanger to "Critical"
    }
    
    val progress = (days / 120f).coerceIn(0f, 1f)
    
    val animatedProgress by animateFloatAsState(
        targetValue = progress,
        animationSpec = tween(durationMillis = 500),
        label = "DaysProgressAnimation"
    )
    
    Column(modifier = modifier) {
        if (showLabel) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "$days days",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = color
                )
                Text(
                    text = label,
                    style = MaterialTheme.typography.bodySmall,
                    color = color.copy(alpha = 0.8f)
                )
            }
            Spacer(modifier = Modifier.height(4.dp))
        }
        
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(6.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(Color(0xFFF2F2F7))
        ) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(animatedProgress)
                    .background(color)
            )
        }
    }
}

@Composable
fun CompactDaysIndicator(
    days: Int,
    modifier: Modifier = Modifier
) {
    val color = when {
        days <= 30 -> EzcarGreen
        days <= 60 -> EzcarWarning
        days <= 90 -> EzcarOrange
        else -> EzcarDanger
    }
    
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(color)
        )
        Text(
            text = "${days}d",
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium,
            color = color
        )
    }
}

@Composable
fun DaysBadge(
    days: Int,
    modifier: Modifier = Modifier
) {
    val (backgroundColor, textColor) = when {
        days <= 30 -> EzcarGreen.copy(alpha = 0.1f) to EzcarGreen
        days <= 60 -> EzcarWarning.copy(alpha = 0.1f) to EzcarWarning
        days <= 90 -> EzcarOrange.copy(alpha = 0.1f) to EzcarOrange
        else -> EzcarDanger.copy(alpha = 0.1f) to EzcarDanger
    }
    
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(8.dp))
            .background(backgroundColor)
            .padding(horizontal = 8.dp, vertical = 4.dp)
    ) {
        Text(
            text = "$days days",
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
            color = textColor
        )
    }
}
