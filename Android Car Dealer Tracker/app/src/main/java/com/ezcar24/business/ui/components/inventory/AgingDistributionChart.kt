package com.ezcar24.business.ui.components.inventory

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarWarning
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarDanger

@Composable
fun AgingDistributionChart(
    distribution: Map<String, Int>,
    modifier: Modifier = Modifier
) {
    val buckets = listOf("0-30", "31-60", "61-90", "90+")
    val colors = listOf(EzcarGreen, EzcarWarning, EzcarOrange, EzcarDanger)
    
    val maxCount = distribution.values.maxOrNull()?.coerceAtLeast(1) ?: 1
    
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Color.White)
            .padding(16.dp)
    ) {
        Text(
            text = "Aging Distribution",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = Color.Black
        )
        
        Spacer(modifier = Modifier.height(16.dp))
        
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(120.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.Bottom
        ) {
            buckets.forEachIndexed { index, bucket ->
                val count = distribution[bucket] ?: 0
                val heightFraction = count.toFloat() / maxCount.toFloat()
                
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(
                        text = count.toString(),
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.Bold,
                        color = colors[index]
                    )
                    
                    Spacer(modifier = Modifier.height(4.dp))
                    
                    Box(
                        modifier = Modifier
                            .width(40.dp)
                            .fillMaxHeight(heightFraction.coerceAtLeast(0.1f))
                            .clip(RoundedCornerShape(topStart = 8.dp, topEnd = 8.dp))
                            .background(colors[index].copy(alpha = 0.8f))
                    )
                    
                    Spacer(modifier = Modifier.height(8.dp))
                    
                    Text(
                        text = bucket,
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.Gray
                    )
                    Text(
                        text = "days",
                        style = MaterialTheme.typography.labelSmall,
                        color = Color.Gray.copy(alpha = 0.7f)
                    )
                }
            }
        }
    }
}

@Composable
fun AgingDistributionHorizontal(
    distribution: Map<String, Int>,
    modifier: Modifier = Modifier
) {
    val buckets = listOf("0-30", "31-60", "61-90", "90+")
    val colors = listOf(EzcarGreen, EzcarWarning, EzcarOrange, EzcarDanger)
    
    val total = distribution.values.sum().coerceAtLeast(1)
    
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Color.White)
            .padding(16.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(24.dp)
                .clip(RoundedCornerShape(12.dp))
        ) {
            buckets.forEachIndexed { index, bucket ->
                val count = distribution[bucket] ?: 0
                val widthFraction = count.toFloat() / total.toFloat()
                
                if (widthFraction > 0) {
                    Box(
                        modifier = Modifier
                            .fillMaxHeight()
                            .weight(widthFraction.coerceAtLeast(0.01f))
                            .background(colors[index])
                    )
                }
            }
        }
        
        Spacer(modifier = Modifier.height(12.dp))
        
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            buckets.forEachIndexed { index, bucket ->
                val count = distribution[bucket] ?: 0
                
                Row(
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(RoundedCornerShape(2.dp))
                            .background(colors[index])
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = "$bucket: $count",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.Gray
                    )
                }
            }
        }
    }
}
