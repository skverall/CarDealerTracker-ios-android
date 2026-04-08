package com.ezcar24.business.ui.settings

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ezcar24.business.data.billing.SubscriptionManager
import com.ezcar24.business.data.billing.SubscriptionOffer

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaywallScreen(
    subscriptionManager: SubscriptionManager,
    onDismiss: () -> Unit
) {
    val offerings by subscriptionManager.offerings.collectAsState()
    val isLoading by subscriptionManager.isLoading.collectAsState()
    val isProActive by subscriptionManager.isProAccessActive.collectAsState()
    var selectedOffer by remember { mutableStateOf<SubscriptionOffer?>(null) }

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ) {
        Column(
            modifier = Modifier.fillMaxSize()
        ) {
            TopAppBar(
                title = { },
                navigationIcon = {
                    TextButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = "Close")
                    }
                }
            )

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                if (isProActive) {
                    SuccessState(onDismiss = onDismiss)
                } else {
                    PremiumHeader()
                    Spacer(modifier = Modifier.height(24.dp))
                    FeatureGrid()
                    Spacer(modifier = Modifier.height(24.dp))
                    if (isLoading) {
                        CircularProgressIndicator(modifier = Modifier.padding(32.dp))
                    } else {
                        PlanSelection(
                            offers = offerings,
                            selectedOffer = selectedOffer,
                            onSelect = { selectedOffer = it }
                        )
                    }
                    Spacer(modifier = Modifier.height(16.dp))
                    SubscribeButton(
                        selectedOffer = selectedOffer,
                        isLoading = isLoading,
                        onSubscribe = {
                            selectedOffer?.let { offer ->
                                subscriptionManager.launchBillingFlow(
                                    it,
                                    offer
                                )
                            }
                        },
                        onRestore = { subscriptionManager.restorePurchases() }
                    )
                    Spacer(modifier = Modifier.height(32.dp))
                }
            }
        }
    }
}

@Composable
private fun PremiumHeader() {
    Box(
        modifier = Modifier
            .size(80.dp)
            .shadow(12.dp, CircleShape)
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        Color(0xFFFFD700),
                        Color(0xFFFFA500)
                    )
                ),
                CircleShape
            ),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = Icons.Default.WorkspacePremium,
            contentDescription = null,
            tint = Color.White,
            modifier = Modifier.size(44.dp)
        )
    }

    Spacer(modifier = Modifier.height(16.dp))

    Text(
        text = "Upgrade to Pro",
        style = MaterialTheme.typography.headlineMedium,
        fontWeight = FontWeight.Bold
    )

    Spacer(modifier = Modifier.height(8.dp))

    Text(
        text = "Unlock the full power of your dealership",
        style = MaterialTheme.typography.bodyLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center
    )
}

@Composable
private fun FeatureGrid() {
    val features = listOf(
        "Unlimited Vehicles" to "No limits on inventory",
        "Cloud Sync" to "Sync across all devices",
        "PDF Reports" to "Professional monthly reports",
        "Advanced Analytics" to "ROI, profit & inventory insights",
        "Team Management" to "Invite & manage your team",
        "Priority Support" to "Fast response on issues"
    )

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        features.chunked(2).forEach { row ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                row.forEach { (title, subtitle) ->
                    Card(
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(12.dp),
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f)
                        )
                    ) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                imageVector = Icons.Default.Check,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Column {
                                Text(
                                    text = title,
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.SemiBold
                                )
                                Text(
                                    text = subtitle,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
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
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        offers.forEach { offer ->
            val isSelected = selectedOffer?.productDetails?.productId == offer.productDetails.productId
            val borderColor = if (isSelected) MaterialTheme.colorScheme.primary else Color.Transparent

            Card(
                onClick = { onSelect(offer) },
                modifier = Modifier
                    .fillMaxWidth()
                    .border(
                        width = if (isSelected) 2.dp else 1.dp,
                        color = borderColor,
                        shape = RoundedCornerShape(16.dp)
                    ),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(
                    containerColor = if (isSelected) {
                        MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
                    } else {
                        MaterialTheme.colorScheme.surface
                    }
                )
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = when (offer.period) {
                                    "monthly" -> "Monthly"
                                    "yearly" -> "Yearly"
                                    else -> offer.period
                                },
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold
                            )
                            if (offer.hasFreeTrial) {
                                Spacer(modifier = Modifier.width(8.dp))
                                Surface(
                                    shape = RoundedCornerShape(50),
                                    color = Color(0xFF4CAF50).copy(alpha = 0.15f)
                                ) {
                                    Text(
                                        text = "Free Trial",
                                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                                        style = MaterialTheme.typography.labelSmall,
                                        fontWeight = FontWeight.SemiBold,
                                        color = Color(0xFF4CAF50)
                                    )
                                }
                            }
                        }
                        if (offer.period == "yearly") {
                            Text(
                                text = "Best value",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.primary,
                                fontWeight = FontWeight.Medium
                            )
                        }
                    }
                    Text(
                        text = offer.price,
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }
    }
}

@Composable
private fun SubscribeButton(
    selectedOffer: SubscriptionOffer?,
    isLoading: Boolean,
    onSubscribe: (android.app.Activity) -> Unit,
    onRestore: () -> Unit
) {
    val activity = androidx.compose.ui.platform.LocalContext.current as? android.app.Activity

    Button(
        onClick = { activity?.let { onSubscribe(it) } },
        enabled = selectedOffer != null && !isLoading,
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp),
        shape = RoundedCornerShape(16.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.primary,
            disabledContainerColor = Color.Gray.copy(alpha = 0.5f)
        )
    ) {
        if (isLoading) {
            CircularProgressIndicator(
                color = Color.White,
                modifier = Modifier.size(24.dp)
            )
        } else {
            Icon(
                imageVector = Icons.Default.Star,
                contentDescription = null,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = if (selectedOffer?.hasFreeTrial == true) "Start Free Trial" else "Subscribe Now",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
        }
    }

    Spacer(modifier = Modifier.height(8.dp))

    OutlinedButton(
        onClick = onRestore,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp)
    ) {
        Text("Restore Purchases")
    }
}

@Composable
private fun SuccessState(onDismiss: () -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.padding(vertical = 48.dp)
    ) {
        Box(
            modifier = Modifier
                .size(100.dp)
                .shadow(12.dp, CircleShape)
                .background(
                    Brush.linearGradient(
                        colors = listOf(Color(0xFF4CAF50), Color(0xFF2E7D32))
                    ),
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
            text = "You're all set!",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Your Pro subscription is active. Enjoy full access.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(32.dp))
        Button(onClick = onDismiss, shape = RoundedCornerShape(12.dp)) {
            Text("Continue")
        }
    }
}
