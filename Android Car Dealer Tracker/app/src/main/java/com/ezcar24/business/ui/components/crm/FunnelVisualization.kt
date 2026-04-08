package com.ezcar24.business.ui.components.crm

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ezcar24.business.data.local.LeadStage
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarDanger
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarPurple
import com.ezcar24.business.ui.theme.EzcarSuccess
import com.ezcar24.business.ui.theme.EzcarWarning
import com.ezcar24.business.util.calculator.FunnelMetrics
import com.ezcar24.business.util.rememberRegionSettingsManager

@Composable
fun FunnelVisualization(
    metrics: FunnelMetrics,
    onStageClick: ((LeadStage) -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val stageOrder = listOf(
        LeadStage.new,
        LeadStage.contacted,
        LeadStage.qualified,
        LeadStage.negotiation,
        LeadStage.offer,
        LeadStage.test_drive,
        LeadStage.closed_won
    )

    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(
                text = "Sales Funnel",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Funnel bars
            val maxCount = metrics.countsPerStage.values.maxOrNull()?.coerceAtLeast(1) ?: 1

            stageOrder.forEach { stage ->
                val count = metrics.countsPerStage[stage] ?: 0
                val percentage = if (metrics.totalLeads > 0) {
                    (count.toFloat() / metrics.totalLeads * 100)
                } else 0f

                FunnelStageBar(
                    stage = stage,
                    count = count,
                    percentage = percentage,
                    maxCount = maxCount,
                    onClick = { onStageClick?.invoke(stage) },
                    isClickable = onStageClick != null
                )

                Spacer(modifier = Modifier.height(8.dp))
            }

            // Summary stats
            Spacer(modifier = Modifier.height(16.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                FunnelStatItem(
                    label = "Active",
                    value = metrics.activeLeads.toString(),
                    color = EzcarBlueBright
                )
                FunnelStatItem(
                    label = "Won",
                    value = metrics.wonLeads.toString(),
                    color = EzcarSuccess
                )
                FunnelStatItem(
                    label = "Lost",
                    value = metrics.lostLeads.toString(),
                    color = EzcarDanger
                )
                FunnelStatItem(
                    label = "Conversion",
                    value = "${String.format("%.1f", metrics.overallConversionRate)}%",
                    color = EzcarGreen
                )
            }
        }
    }
}

@Composable
private fun FunnelStageBar(
    stage: LeadStage,
    count: Int,
    percentage: Float,
    maxCount: Int,
    onClick: () -> Unit,
    isClickable: Boolean
) {
    val animatedProgress by animateFloatAsState(
        targetValue = if (maxCount > 0) count.toFloat() / maxCount else 0f,
        animationSpec = tween(durationMillis = 500),
        label = "funnel_progress"
    )

    val color = when (stage) {
        LeadStage.new -> EzcarBlueBright
        LeadStage.contacted -> EzcarPurple
        LeadStage.qualified -> EzcarWarning
        LeadStage.negotiation -> EzcarOrange
        LeadStage.offer -> Color(0xFFFF9800)
        LeadStage.test_drive -> Color(0xFF9C27B0)
        LeadStage.closed_won -> EzcarSuccess
        LeadStage.closed_lost -> EzcarDanger
    }

    val stageName = when (stage) {
        LeadStage.new -> "New"
        LeadStage.contacted -> "Contacted"
        LeadStage.qualified -> "Qualified"
        LeadStage.negotiation -> "Negotiation"
        LeadStage.offer -> "Offer"
        LeadStage.test_drive -> "Test Drive"
        LeadStage.closed_won -> "Closed Won"
        LeadStage.closed_lost -> "Closed Lost"
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .then(if (isClickable) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(vertical = 2.dp)
    ) {
        // Stage name
        Text(
            text = stageName,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            color = Color.DarkGray,
            modifier = Modifier.width(80.dp)
        )

        Spacer(modifier = Modifier.width(8.dp))

        // Progress bar
        Box(
            modifier = Modifier
                .weight(1f)
                .height(24.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(Color.LightGray.copy(alpha = 0.2f))
        ) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(animatedProgress.coerceIn(0f, 1f))
                    .background(
                        brush = Brush.horizontalGradient(
                            colors = listOf(color, color.copy(alpha = 0.7f))
                        )
                    )
            )

            // Count text inside bar
            Text(
                text = count.toString(),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = if (animatedProgress > 0.15f) Color.White else Color.Transparent,
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .padding(start = 8.dp)
            )
        }

        Spacer(modifier = Modifier.width(8.dp))

        // Percentage
        Text(
            text = "${String.format("%.1f", percentage)}%",
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            color = color,
            modifier = Modifier.width(45.dp),
            textAlign = TextAlign.End
        )
    }
}

@Composable
private fun FunnelStatItem(
    label: String,
    value: String,
    color: Color
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = value,
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            color = color
        )
        Text(
            text = label,
            fontSize = 11.sp,
            color = Color.Gray
        )
    }
}

@Composable
fun ConversionRateCard(
    fromStage: LeadStage,
    toStage: LeadStage,
    rate: Double,
    modifier: Modifier = Modifier
) {
    val color = when {
        rate >= 50 -> EzcarSuccess
        rate >= 30 -> EzcarGreen
        rate >= 15 -> EzcarWarning
        else -> EzcarOrange
    }

    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        modifier = modifier,
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "${getStageShortName(fromStage)} → ${getStageShortName(toStage)}",
                fontSize = 12.sp,
                color = Color.Gray
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "${String.format("%.1f", rate)}%",
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = color
            )

            Spacer(modifier = Modifier.height(4.dp))

            LinearProgressIndicator(
                progress = { (rate / 100f).toFloat().coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth(),
                color = color,
                trackColor = color.copy(alpha = 0.2f)
            )
        }
    }
}

@Composable
fun PipelineValueCard(
    totalValue: java.math.BigDecimal,
    weightedValue: java.math.BigDecimal,
    leadCount: Int,
    modifier: Modifier = Modifier
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()

    Card(
        colors = CardDefaults.cardColors(containerColor = EzcarNavy),
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp)
        ) {
            Text(
                text = "Pipeline Value (${regionState.selectedRegion.currencyCode})",
                fontSize = 14.sp,
                color = Color.White.copy(alpha = 0.7f)
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = regionSettingsManager.formatCurrency(totalValue),
                fontSize = 32.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )

            Spacer(modifier = Modifier.height(16.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column {
                    Text(
                        text = "Weighted",
                        fontSize = 12.sp,
                        color = Color.White.copy(alpha = 0.7f)
                    )
                    Text(
                        text = regionSettingsManager.formatCurrency(weightedValue),
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = EzcarGreen
                    )
                }

                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        text = "Active Leads",
                        fontSize = 12.sp,
                        color = Color.White.copy(alpha = 0.7f)
                    )
                    Text(
                        text = leadCount.toString(),
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White
                    )
                }
            }
        }
    }
}

private fun getStageShortName(stage: LeadStage): String {
    return when (stage) {
        LeadStage.new -> "New"
        LeadStage.contacted -> "Contact"
        LeadStage.qualified -> "Qual"
        LeadStage.negotiation -> "Nego"
        LeadStage.offer -> "Offer"
        LeadStage.test_drive -> "Test"
        LeadStage.closed_won -> "Won"
        LeadStage.closed_lost -> "Lost"
    }
}
