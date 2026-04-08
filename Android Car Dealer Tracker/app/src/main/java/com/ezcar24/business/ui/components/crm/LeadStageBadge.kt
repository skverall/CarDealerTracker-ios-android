package com.ezcar24.business.ui.components.crm

import androidx.compose.foundation.background
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ezcar24.business.data.local.LeadStage
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarDanger
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarPurple
import com.ezcar24.business.ui.theme.EzcarSuccess
import com.ezcar24.business.ui.theme.EzcarWarning

@Composable
fun LeadStageBadge(
    stage: LeadStage,
    modifier: Modifier = Modifier
) {
    val (text, color) = when (stage) {
        LeadStage.new -> "New" to EzcarBlueBright
        LeadStage.contacted -> "Contacted" to EzcarPurple
        LeadStage.qualified -> "Qualified" to EzcarWarning
        LeadStage.negotiation -> "Negotiation" to EzcarOrange
        LeadStage.offer -> "Offer" to Color(0xFFFF9800)
        LeadStage.test_drive -> "Test Drive" to Color(0xFF9C27B0)
        LeadStage.closed_won -> "Won" to EzcarSuccess
        LeadStage.closed_lost -> "Lost" to EzcarDanger
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
fun LeadStageSelector(
    selectedStage: LeadStage,
    onStageSelected: (LeadStage) -> Unit,
    modifier: Modifier = Modifier,
    excludeClosed: Boolean = false
) {
    val stages = if (excludeClosed) {
        LeadStage.values().filter { it != LeadStage.closed_won && it != LeadStage.closed_lost }
    } else {
        LeadStage.values().toList()
    }

    androidx.compose.foundation.lazy.LazyRow(
        horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp),
        modifier = modifier
    ) {
        items(items = stages, key = { it.name }) { stage ->
            val isSelected = stage == selectedStage
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

            val displayText = when (stage) {
                LeadStage.new -> "New"
                LeadStage.contacted -> "Contacted"
                LeadStage.qualified -> "Qualified"
                LeadStage.negotiation -> "Negotiation"
                LeadStage.offer -> "Offer"
                LeadStage.test_drive -> "Test Drive"
                LeadStage.closed_won -> "Won"
                LeadStage.closed_lost -> "Lost"
            }

            androidx.compose.material3.FilterChip(
                selected = isSelected,
                onClick = { onStageSelected(stage) },
                label = { 
                    Text(
                        displayText,
                        fontSize = 12.sp,
                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal
                    ) 
                },
                colors = androidx.compose.material3.FilterChipDefaults.filterChipColors(
                    selectedContainerColor = color,
                    selectedLabelColor = Color.White,
                    containerColor = color.copy(alpha = 0.1f),
                    labelColor = color
                )
            )
        }
    }
}
