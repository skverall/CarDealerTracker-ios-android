package com.ezcar24.business.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarWarning
import com.ezcar24.business.ui.theme.EzcarDanger

@Composable
fun AgingBucketBadge(
    daysInInventory: Int,
    modifier: Modifier = Modifier
) {
    val (text, color) = when {
        daysInInventory <= 30 -> "${daysInInventory}d" to EzcarGreen
        daysInInventory <= 60 -> "${daysInInventory}d" to EzcarWarning
        daysInInventory <= 90 -> "${daysInInventory}d" to EzcarOrange
        else -> "${daysInInventory}d" to EzcarDanger
    }

    Text(
        text = text,
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        color = color,
        modifier = modifier
            .background(color.copy(alpha = 0.1f), RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 4.dp)
    )
}

@Composable
fun AgingBucketLabel(
    bucket: String,
    modifier: Modifier = Modifier
) {
    val color = when (bucket) {
        "0-30" -> EzcarGreen
        "31-60" -> EzcarWarning
        "61-90" -> EzcarOrange
        "90+" -> EzcarDanger
        else -> Color.Gray
    }

    Text(
        text = bucket,
        fontSize = 12.sp,
        fontWeight = FontWeight.Medium,
        color = color,
        modifier = modifier
            .background(color.copy(alpha = 0.1f), RoundedCornerShape(8.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp)
    )
}
