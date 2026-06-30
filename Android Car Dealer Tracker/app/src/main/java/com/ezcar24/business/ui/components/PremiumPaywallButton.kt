package com.ezcar24.business.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val PaywallButton = Color(0xFF0F66FF)
private val PaywallButtonLight = Color(0xFF4F91FF)
private val PaywallButtonDeep = Color(0xFF0848C7)

@Composable
fun PremiumPaywallButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    isLoading: Boolean = false,
    height: Dp = 52.dp,
    cornerRadius: Dp = 20.dp,
    fontSize: TextUnit = 18.sp
) {
    val shape = RoundedCornerShape(cornerRadius)
    val interactive = enabled && !isLoading
    val gradient = if (interactive) {
        Brush.linearGradient(listOf(PaywallButtonLight, PaywallButton, PaywallButtonDeep))
    } else {
        Brush.linearGradient(
            listOf(
                PaywallButtonLight.copy(alpha = 0.46f),
                PaywallButton.copy(alpha = 0.42f),
                PaywallButtonDeep.copy(alpha = 0.42f)
            )
        )
    }

    Box(
        modifier = modifier
            .widthIn(min = 156.dp)
            .height(height)
            .shadow(
                elevation = if (interactive) 14.dp else 0.dp,
                shape = shape,
                clip = false
            )
            .clip(shape)
            .background(gradient, shape)
            .border(1.dp, Color.White.copy(alpha = 0.32f), shape)
            .clickable(
                enabled = interactive,
                role = Role.Button,
                onClick = onClick
            )
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center
    ) {
        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(22.dp),
                color = Color.White,
                strokeWidth = 2.dp
            )
        } else {
            Text(
                text = text,
                color = Color.White,
                fontSize = fontSize,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}
