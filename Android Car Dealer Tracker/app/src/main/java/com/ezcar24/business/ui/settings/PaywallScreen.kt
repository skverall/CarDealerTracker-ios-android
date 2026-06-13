package com.ezcar24.business.ui.settings

import android.app.Activity
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import com.ezcar24.business.BuildConfig
import com.ezcar24.business.R
import com.ezcar24.business.data.billing.SubscriptionManager
import com.ezcar24.business.data.billing.SubscriptionOffer
import com.ezcar24.business.util.localizedUiString

@Composable
fun PaywallScreen(
    subscriptionManager: SubscriptionManager,
    onDismiss: () -> Unit
) {
    val offerings by subscriptionManager.offerings.collectAsState()
    val isLoading by subscriptionManager.isLoading.collectAsState()
    val isProActive by subscriptionManager.isProAccessActive.collectAsState()
    val showSuccessState = isProActive && !BuildConfig.DEBUG
    var selectedOffer by remember { mutableStateOf<SubscriptionOffer?>(null) }
    val view = LocalView.current
    val darkTheme = isSystemInDarkTheme()

    LaunchedEffect(offerings) {
        if (selectedOffer == null && offerings.isNotEmpty()) {
            selectedOffer = offerings.firstOrNull { it.period == "yearly" } ?: offerings.first()
        }
    }

    DisposableEffect(view, darkTheme) {
        if (!view.isInEditMode) {
            val window = (view.context as Activity).window
            val controller = WindowCompat.getInsetsController(window, view)
            window.statusBarColor = Color.Transparent.toArgb()
            window.navigationBarColor = Color.Transparent.toArgb()
            controller.isAppearanceLightStatusBars = false
            controller.isAppearanceLightNavigationBars = false
        }
        onDispose {
            if (!view.isInEditMode) {
                val window = (view.context as Activity).window
                val controller = WindowCompat.getInsetsController(window, view)
                controller.isAppearanceLightStatusBars = !darkTheme
                controller.isAppearanceLightNavigationBars = !darkTheme
            }
        }
    }

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = Color.Black
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            Color(0xFF05030A),
                            Color(0xFF12081F),
                            Color.Black
                        )
                    )
                )
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .navigationBarsPadding()
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    horizontalArrangement = Arrangement.End
                ) {
                    IconButton(
                        onClick = onDismiss,
                        modifier = Modifier
                            .size(48.dp)
                            .background(Color.White.copy(alpha = 0.08f), CircleShape)
                            .border(1.dp, Color.White.copy(alpha = 0.14f), CircleShape)
                    ) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = localizedUiString("Close"),
                            tint = Color.White
                        )
                    }
                }

                if (showSuccessState) {
                    SuccessState(onDismiss = onDismiss)
                } else {
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = 18.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        PaywallHero()
                        Spacer(modifier = Modifier.height(16.dp))
                        SectionTitle("WHAT YOU GET")
                        Spacer(modifier = Modifier.height(10.dp))
                        FeatureGrid()
                        Spacer(modifier = Modifier.height(18.dp))
                        SectionTitle("CHOOSE YOUR PLAN")
                        Spacer(modifier = Modifier.height(10.dp))
                        if (isLoading && offerings.isEmpty()) {
                            CircularProgressIndicator(
                                color = Color.White,
                                modifier = Modifier.padding(28.dp)
                            )
                        } else if (offerings.isEmpty()) {
                            EmptyPlansState(onRetry = subscriptionManager::queryProducts)
                        } else {
                            PlanSelection(
                                offers = offerings,
                                selectedOffer = selectedOffer,
                                onSelect = { selectedOffer = it }
                            )
                        }
                        Spacer(modifier = Modifier.height(18.dp))
                    }

                    PaywallBottomBar(
                        selectedOffer = selectedOffer,
                        isLoading = isLoading,
                        onSubscribe = { activity ->
                            selectedOffer?.let { offer ->
                                subscriptionManager.launchBillingFlow(activity, offer)
                            }
                        },
                        onRestore = subscriptionManager::restorePurchases
                    )
                }
            }
        }
    }
}

@Composable
private fun PaywallHero() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 520.dp)
            .height(288.dp)
            .clip(RoundedCornerShape(28.dp))
    ) {
        Image(
            painter = painterResource(id = R.drawable.paywall_neon_car),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize()
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            Color.Black.copy(alpha = 0.18f),
                            Color.Black.copy(alpha = 0.18f),
                            Color.Black.copy(alpha = 0.86f)
                        )
                    )
                )
        )
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 18.dp, vertical = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            PremiumBadge()
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = localizedUiString("Upgrade to Pro"),
                style = MaterialTheme.typography.headlineLarge,
                fontWeight = FontWeight.ExtraBold,
                color = Color.White,
                textAlign = TextAlign.Center,
                maxLines = 1
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = localizedUiString("Everything you need to grow your dealership business."),
                style = MaterialTheme.typography.bodyLarge,
                color = Color.White.copy(alpha = 0.72f),
                textAlign = TextAlign.Center,
                maxLines = 2
            )
        }
    }
}

@Composable
private fun PremiumBadge() {
    Surface(
        shape = RoundedCornerShape(50),
        color = Color.Black.copy(alpha = 0.46f),
        border = androidx.compose.foundation.BorderStroke(
            1.dp,
            Brush.horizontalGradient(
                listOf(Color(0xFFA855F7), Color(0xFF4F46E5))
            )
        )
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(
                imageVector = Icons.Default.Star,
                contentDescription = null,
                tint = Color(0xFFC084FC),
                modifier = Modifier.size(16.dp)
            )
            Text(
                text = localizedUiString("Unlock Full Potential"),
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Bold,
                color = Color(0xFFC084FC)
            )
        }
    }
}

@Composable
private fun FeatureGrid() {
    val features = listOf(
        PaywallFeatureItem(
            icon = Icons.Default.Star,
            title = "AI Tips",
            subtitle = "Instant insights for smarter deals"
        ),
        PaywallFeatureItem(
            icon = Icons.Default.Check,
            title = "Unlimited",
            subtitle = "Add unlimited cars, no restrictions"
        ),
        PaywallFeatureItem(
            icon = Icons.Default.CloudUpload,
            title = "Sync",
            subtitle = "Synced across all your devices"
        ),
        PaywallFeatureItem(
            icon = Icons.Default.Description,
            title = "Reports",
            subtitle = "Export professional PDF reports"
        )
    )

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 520.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        features.chunked(2).forEach { rowItems ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                rowItems.forEach { feature ->
                    FeatureCard(
                        feature = feature,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }
}

@Composable
private fun FeatureCard(
    feature: PaywallFeatureItem,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.heightIn(min = 86.dp),
        shape = RoundedCornerShape(16.dp),
        color = Color.White.copy(alpha = 0.08f),
        border = androidx.compose.foundation.BorderStroke(1.dp, Color.White.copy(alpha = 0.14f))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(38.dp)
                    .background(Color(0xFFA855F7).copy(alpha = 0.16f), RoundedCornerShape(12.dp)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = feature.icon,
                    contentDescription = null,
                    tint = Color(0xFFC084FC),
                    modifier = Modifier.size(20.dp)
                )
            }
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = localizedUiString(feature.title),
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = localizedUiString(feature.subtitle),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White.copy(alpha = 0.58f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

private data class PaywallFeatureItem(
    val icon: ImageVector,
    val title: String,
    val subtitle: String
)

@Composable
private fun SectionTitle(title: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 520.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Box(
            modifier = Modifier
                .weight(1f)
                .height(1.dp)
                .background(Color.White.copy(alpha = 0.12f))
        )
        Text(
            text = localizedUiString(title),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.ExtraBold,
            color = Color.White.copy(alpha = 0.58f),
            maxLines = 1
        )
        Box(
            modifier = Modifier
                .weight(1f)
                .height(1.dp)
                .background(Color.White.copy(alpha = 0.12f))
        )
    }
}

@Composable
private fun EmptyPlansState(onRetry: () -> Unit) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 520.dp),
        shape = RoundedCornerShape(22.dp),
        color = Color.White.copy(alpha = 0.08f),
        border = androidx.compose.foundation.BorderStroke(1.dp, Color.White.copy(alpha = 0.14f))
    ) {
        Column(
            modifier = Modifier.padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = localizedUiString("Unable to load plans"),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = Color.White.copy(alpha = 0.78f)
            )
            TextButton(onClick = onRetry) {
                Text(
                    text = localizedUiString("Retry"),
                    color = Color(0xFFC084FC),
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}

@Composable
private fun PlanSelection(
    offers: List<SubscriptionOffer>,
    selectedOffer: SubscriptionOffer?,
    onSelect: (SubscriptionOffer) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 520.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        offers.forEach { offer ->
            PlanCard(
                offer = offer,
                selected = selectedOffer?.productDetails?.productId == offer.productDetails.productId,
                onClick = { onSelect(offer) }
            )
        }
    }
}

@Composable
private fun PlanCard(
    offer: SubscriptionOffer,
    selected: Boolean,
    onClick: () -> Unit
) {
    val shape = RoundedCornerShape(22.dp)

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(116.dp)
            .clickable(onClick = onClick),
        shape = shape,
        color = if (selected) Color(0xFF1D1333).copy(alpha = 0.94f) else Color.White.copy(alpha = 0.08f),
        border = androidx.compose.foundation.BorderStroke(
            width = if (selected) 2.dp else 1.dp,
            brush = if (selected) {
                Brush.linearGradient(listOf(Color(0xFF60A5FA), Color(0xFFA855F7), Color(0xFFF0ABFC)))
            } else {
                Brush.linearGradient(listOf(Color.White.copy(alpha = 0.14f), Color.White.copy(alpha = 0.08f)))
            }
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = localizedUiString(planName(offer)),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        maxLines = 1
                    )
                    if (offer.period == "yearly") {
                        PlanBadge("Best value")
                    } else if (offer.hasFreeTrial) {
                        PlanBadge("Trial")
                    }
                }
                Text(
                    text = localizedUiString(billingLine(offer)),
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.White.copy(alpha = 0.58f),
                    maxLines = 1
                )
                Text(
                    text = offer.price.ifBlank { "..." },
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.ExtraBold,
                    color = Color.White,
                    maxLines = 1
                )
            }
            SelectionDot(selected = selected)
        }
    }
}

@Composable
private fun PlanBadge(text: String) {
    Surface(
        shape = RoundedCornerShape(50),
        color = Color(0xFFA855F7)
    ) {
        Text(
            text = localizedUiString(text),
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.ExtraBold,
            color = Color.White,
            maxLines = 1
        )
    }
}

@Composable
private fun SelectionDot(selected: Boolean) {
    Box(
        modifier = Modifier
            .size(30.dp)
            .background(
                color = if (selected) Color(0xFFC084FC) else Color.Transparent,
                shape = CircleShape
            )
            .border(
                width = 2.dp,
                color = if (selected) Color(0xFFC084FC) else Color.White.copy(alpha = 0.42f),
                shape = CircleShape
            ),
        contentAlignment = Alignment.Center
    ) {
        if (selected) {
            Icon(
                imageVector = Icons.Default.Check,
                contentDescription = null,
                tint = Color.Black.copy(alpha = 0.7f),
                modifier = Modifier.size(16.dp)
            )
        }
    }
}

@Composable
private fun PaywallBottomBar(
    selectedOffer: SubscriptionOffer?,
    isLoading: Boolean,
    onSubscribe: (Activity) -> Unit,
    onRestore: () -> Unit
) {
    val activity = LocalContext.current as? Activity

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                Brush.verticalGradient(
                    listOf(Color.Black.copy(alpha = 0f), Color.Black.copy(alpha = 0.94f), Color.Black)
                )
            )
            .padding(horizontal = 18.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            Icon(
                imageVector = Icons.Default.Check,
                contentDescription = null,
                tint = Color(0xFFA855F7),
                modifier = Modifier.size(16.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = localizedUiString("Cancel anytime. No hidden fees."),
                style = MaterialTheme.typography.bodySmall,
                color = Color.White.copy(alpha = 0.68f),
                maxLines = 1
            )
        }

        Button(
            onClick = { activity?.let(onSubscribe) },
            enabled = selectedOffer != null && !isLoading,
            modifier = Modifier
                .fillMaxWidth()
                .widthIn(max = 520.dp)
                .height(58.dp),
            shape = RoundedCornerShape(22.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = Color.Transparent,
                disabledContainerColor = Color.Transparent,
                contentColor = Color.White,
                disabledContentColor = Color.White.copy(alpha = 0.6f)
            ),
            contentPadding = ButtonDefaults.ContentPadding
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.horizontalGradient(
                            colors = listOf(Color(0xFF4A00E0), Color(0xFF8E2DE2), Color(0xFFA855F7))
                        ),
                        RoundedCornerShape(22.dp)
                    ),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = if (isLoading) localizedUiString("Processing...") else localizedUiString(ctaText(selectedOffer)),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.ExtraBold
                )
            }
        }

        TextButton(onClick = onRestore) {
            Text(
                text = localizedUiString("Restore Purchases"),
                color = Color(0xFFC084FC),
                fontWeight = FontWeight.Medium
            )
        }
    }
}

@Composable
private fun SuccessState(onDismiss: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(
            modifier = Modifier
                .size(96.dp)
                .background(
                    Brush.linearGradient(listOf(Color(0xFF29AB63), Color(0xFF00D26A))),
                    CircleShape
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.Check,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(48.dp)
            )
        }
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            text = localizedUiString("You're all set!"),
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.ExtraBold,
            color = Color.White
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = localizedUiString("Your Pro subscription is active. Enjoy full access."),
            style = MaterialTheme.typography.bodyLarge,
            color = Color.White.copy(alpha = 0.7f),
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(28.dp))
        Button(
            onClick = onDismiss,
            shape = RoundedCornerShape(18.dp)
        ) {
            Text(localizedUiString("Continue"))
        }
    }
}

private fun planName(offer: SubscriptionOffer): String {
    return when (offer.period) {
        "monthly" -> "Monthly"
        "yearly" -> "Yearly"
        else -> offer.period.replaceFirstChar { it.uppercase() }
    }
}

private fun billingLine(offer: SubscriptionOffer): String {
    return when (offer.period) {
        "monthly" -> "Billed monthly"
        "yearly" -> "Billed yearly"
        else -> "Billed automatically"
    }
}

private fun ctaText(selectedOffer: SubscriptionOffer?): String {
    return when {
        selectedOffer == null -> "Select a Plan"
        selectedOffer.hasFreeTrial -> "Start Free Trial"
        else -> "Continue"
    }
}
