package com.ezcar24.business.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarSuccess
import com.ezcar24.business.ui.theme.EzcarWarning
import com.ezcar24.business.ui.theme.EzcarDanger
import java.math.BigDecimal

@Composable
fun ROIBadge(
    roiPercent: BigDecimal?,
    modifier: Modifier = Modifier
) {
    if (roiPercent == null) {
        Text(
            text = "N/A",
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            color = Color.Gray,
            modifier = modifier
                .background(Color.LightGray.copy(alpha = 0.2f), RoundedCornerShape(8.dp))
                .padding(horizontal = 8.dp, vertical = 4.dp)
        )
        return
    }

    val (text, color) = when {
        roiPercent.compareTo(BigDecimal.ZERO) < 0 -> 
            "${roiPercent.toInt()}%" to EzcarDanger
        roiPercent.compareTo(BigDecimal("10")) < 0 -> 
            "${roiPercent.toInt()}%" to EzcarWarning
        roiPercent.compareTo(BigDecimal("20")) < 0 -> 
            "${roiPercent.toInt()}%" to EzcarGreen
        else -> 
            "${roiPercent.toInt()}%" to EzcarSuccess
    }

    Text(
        text = text,
        fontSize = 12.sp,
        fontWeight = FontWeight.Bold,
        color = color,
        modifier = modifier
            .background(color.copy(alpha = 0.1f), RoundedCornerShape(8.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp)
    )
}

@Composable
fun ProfitBadge(
    profit: BigDecimal?,
    modifier: Modifier = Modifier
) {
    if (profit == null) {
        Text(
            text = "-",
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            color = Color.Gray,
            modifier = modifier
                .background(Color.LightGray.copy(alpha = 0.2f), RoundedCornerShape(8.dp))
                .padding(horizontal = 8.dp, vertical = 4.dp)
        )
        return
    }

    val color = when {
        profit.compareTo(BigDecimal.ZERO) < 0 -> EzcarDanger
        profit.compareTo(BigDecimal.ZERO) == 0 -> Color.Gray
        else -> EzcarGreen
    }

    val formattedProfit = formatCurrency(profit)

    Text(
        text = formattedProfit,
        fontSize = 12.sp,
        fontWeight = FontWeight.Bold,
        color = color,
        modifier = modifier
            .background(color.copy(alpha = 0.1f), RoundedCornerShape(8.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp)
    )
}

private fun formatCurrency(amount: BigDecimal): String {
    val prefix = if (amount.compareTo(BigDecimal.ZERO) < 0) "-AED " else "AED "
    val absAmount = amount.abs()
    return prefix + absAmount.toPlainString()
}
