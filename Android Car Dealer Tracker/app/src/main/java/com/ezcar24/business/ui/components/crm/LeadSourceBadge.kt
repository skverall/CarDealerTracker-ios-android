package com.ezcar24.business.ui.components.crm

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.LocalPhone
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Store
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ezcar24.business.data.local.LeadSource
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarPurple

@Composable
fun LeadSourceBadge(
    source: LeadSource?,
    modifier: Modifier = Modifier
) {
    if (source == null) {
        Text(
            text = "Unknown",
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            color = Color.Gray,
            modifier = modifier
                .background(Color.LightGray.copy(alpha = 0.2f), RoundedCornerShape(50))
                .padding(horizontal = 10.dp, vertical = 4.dp)
        )
        return
    }

    val (text, color, icon) = when (source) {
        LeadSource.facebook -> "Facebook" to Color(0xFF1877F2) to Icons.Default.Share
        LeadSource.dubizzle -> "Dubizzle" to EzcarOrange to Icons.Default.Store
        LeadSource.instagram -> "Instagram" to Color(0xFFE4405F) to Icons.Default.Share
        LeadSource.referral -> "Referral" to EzcarPurple to Icons.Default.People
        LeadSource.walk_in -> "Walk-in" to EzcarGreen to Icons.Default.LocationOn
        LeadSource.phone -> "Phone" to EzcarNavy to Icons.Default.Phone
        LeadSource.website -> "Website" to EzcarBlueBright to Icons.Default.Language
        LeadSource.other -> "Other" to Color.Gray to Icons.Default.Call
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .background(color.copy(alpha = 0.1f), RoundedCornerShape(50))
            .padding(horizontal = 8.dp, vertical = 4.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(12.dp)
        )
        Spacer(modifier = Modifier.width(4.dp))
        Text(
            text = text.first,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            color = color
        )
    }
}

@Composable
fun LeadSourceSelector(
    selectedSource: LeadSource?,
    onSourceSelected: (LeadSource?) -> Unit,
    modifier: Modifier = Modifier,
    includeUnknown: Boolean = true
) {
    val sources = if (includeUnknown) {
        listOf(null) + LeadSource.values().toList()
    } else {
        LeadSource.values().toList()
    }

    androidx.compose.foundation.lazy.LazyRow(
        horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp),
        modifier = modifier
    ) {
        items(sources) { source ->
            val isSelected = source == selectedSource
            val (text, color) = when (source) {
                null -> "Any" to Color.Gray
                LeadSource.facebook -> "Facebook" to Color(0xFF1877F2)
                LeadSource.dubizzle -> "Dubizzle" to EzcarOrange
                LeadSource.instagram -> "Instagram" to Color(0xFFE4405F)
                LeadSource.referral -> "Referral" to EzcarPurple
                LeadSource.walk_in -> "Walk-in" to EzcarGreen
                LeadSource.phone -> "Phone" to EzcarNavy
                LeadSource.website -> "Website" to EzcarBlueBright
                LeadSource.other -> "Other" to Color.Gray
            }

            androidx.compose.material3.FilterChip(
                selected = isSelected,
                onClick = { onSourceSelected(source) },
                label = { 
                    Text(
                        text,
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

fun LeadSource.getDisplayName(): String = when (this) {
    LeadSource.facebook -> "Facebook"
    LeadSource.dubizzle -> "Dubizzle"
    LeadSource.instagram -> "Instagram"
    LeadSource.referral -> "Referral"
    LeadSource.walk_in -> "Walk-in"
    LeadSource.phone -> "Phone"
    LeadSource.website -> "Website"
    LeadSource.other -> "Other"
}

fun LeadSource.getIcon(): ImageVector = when (this) {
    LeadSource.facebook -> Icons.Default.Share
    LeadSource.dubizzle -> Icons.Default.Store
    LeadSource.instagram -> Icons.Default.Share
    LeadSource.referral -> Icons.Default.People
    LeadSource.walk_in -> Icons.Default.LocationOn
    LeadSource.phone -> Icons.Default.Phone
    LeadSource.website -> Icons.Default.Language
    LeadSource.other -> Icons.Default.Call
}

fun LeadSource.getColor(): Color = when (this) {
    LeadSource.facebook -> Color(0xFF1877F2)
    LeadSource.dubizzle -> EzcarOrange
    LeadSource.instagram -> Color(0xFFE4405F)
    LeadSource.referral -> EzcarPurple
    LeadSource.walk_in -> EzcarGreen
    LeadSource.phone -> EzcarNavy
    LeadSource.website -> EzcarBlueBright
    LeadSource.other -> Color.Gray
}
