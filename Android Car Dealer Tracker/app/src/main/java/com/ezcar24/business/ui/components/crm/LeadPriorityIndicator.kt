package com.ezcar24.business.ui.components.crm

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarWarning

@Composable
fun LeadPriorityIndicator(
    priority: Int,
    modifier: Modifier = Modifier,
    maxPriority: Int = 5,
    showLabel: Boolean = true
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        modifier = modifier
    ) {
        if (showLabel) {
            Text(
                text = "Priority: ",
                fontSize = 12.sp,
                color = Color.Gray
            )
        }
        
        repeat(maxPriority) { index ->
            val isFilled = index < priority
            Icon(
                imageVector = if (isFilled) Icons.Filled.Star else Icons.Outlined.Star,
                contentDescription = null,
                tint = if (isFilled) {
                    when {
                        priority >= 4 -> Color(0xFFE53935) // High priority - Red
                        priority >= 3 -> EzcarOrange // Medium-High - Orange
                        else -> EzcarWarning // Low-Medium - Yellow
                    }
                } else Color.LightGray,
                modifier = Modifier.size(16.dp)
            )
        }
    }
}

@Composable
fun LeadPrioritySelector(
    priority: Int,
    onPriorityChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
    maxPriority: Int = 5
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = modifier
    ) {
        Text(
            text = "Priority",
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            color = Color.Gray
        )
        
        repeat(maxPriority) { index ->
            val starIndex = index + 1
            val isFilled = starIndex <= priority
            
            IconButton(
                onClick = { onPriorityChange(starIndex) },
                modifier = Modifier.size(32.dp)
            ) {
                Icon(
                    imageVector = if (isFilled) Icons.Filled.Star else Icons.Outlined.Star,
                    contentDescription = "Priority $starIndex",
                    tint = if (isFilled) {
                        when {
                            starIndex >= 4 -> Color(0xFFE53935)
                            starIndex >= 3 -> EzcarOrange
                            else -> EzcarWarning
                        }
                    } else Color.LightGray
                )
            }
        }
    }
}

@Composable
fun LeadPriorityBadge(
    priority: Int,
    modifier: Modifier = Modifier
) {
    val (text, color) = when (priority) {
        5 -> "Critical" to Color(0xFFE53935)
        4 -> "High" to EzcarOrange
        3 -> "Medium" to EzcarWarning
        2 -> "Low" to Color(0xFF4CAF50)
        1 -> "Very Low" to Color(0xFF9E9E9E)
        else -> "None" to Color.LightGray
    }

    Text(
        text = text,
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        color = color,
        modifier = modifier
            .background(color.copy(alpha = 0.1f), androidx.compose.foundation.shape.RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 4.dp)
    )
}
