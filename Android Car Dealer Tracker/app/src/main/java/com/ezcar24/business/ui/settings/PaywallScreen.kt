package com.ezcar24.business.ui.settings

import android.app.Activity
import android.graphics.Matrix
import android.media.MediaPlayer
import android.view.Surface
import android.view.TextureView
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.compose.foundation.BorderStroke
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
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import com.ezcar24.business.BuildConfig
import com.ezcar24.business.R
import com.ezcar24.business.data.billing.SubscriptionManager
import com.ezcar24.business.data.billing.SubscriptionOffer
import com.ezcar24.business.ui.components.PremiumPaywallButton
import com.ezcar24.business.util.localizedUiString

enum class PaywallScreenSource(val routeValue: String) {
    General("general"),
    VehicleLimit("vehicle_limit"),
    AiInsights("ai_insights");

    companion object {
        fun fromRoute(routeValue: String?): PaywallScreenSource {
            return entries.firstOrNull { it.routeValue == routeValue } ?: General
        }
    }
}

private val PaywallBlue = Color(0xFF0F66FF)
private val PaywallBlueLight = Color(0xFF4F91FF)
private val PaywallBlueDeep = Color(0xFF0848C7)
private val PaywallBackground = Color(0xFFF7FAFF)
private val PaywallSurface = Color.White
private val PaywallSurfaceSoft = Color(0xFFF0F6FF)
private val PaywallText = Color(0xFF07142F)
private val PaywallMutedText = Color(0xFF69748C)
private val PaywallBorder = Color(0xFFDCE6F6)
private val PaywallSuccess = Color(0xFF22C55E)

@Composable
fun PaywallScreen(
    subscriptionManager: SubscriptionManager,
    onDismiss: () -> Unit,
    source: PaywallScreenSource = PaywallScreenSource.General
) {
    val offerings by subscriptionManager.offerings.collectAsState()
    val isLoading by subscriptionManager.isLoading.collectAsState()
    val isProActive by subscriptionManager.isProAccessActive.collectAsState()
    val showSuccessState = isProActive && !BuildConfig.DEBUG
    val displayOffers = remember(offerings) { offerings.sortedBy(::displayOrder) }
    var selectedOffer by remember { mutableStateOf<SubscriptionOffer?>(null) }
    val view = LocalView.current
    val darkTheme = isSystemInDarkTheme()
    val layout = rememberPaywallLayout()

    LaunchedEffect(displayOffers) {
        if (selectedOffer == null || displayOffers.none { it.productId == selectedOffer?.productId }) {
            selectedOffer = displayOffers.firstOrNull { it.period == "yearly" }
                ?: displayOffers.firstOrNull { it.period == "monthly" }
                ?: displayOffers.firstOrNull()
        }
    }

    DisposableEffect(view, darkTheme) {
        if (!view.isInEditMode) {
            val window = (view.context as Activity).window
            val controller = WindowCompat.getInsetsController(window, view)
            window.statusBarColor = Color.Transparent.toArgb()
            window.navigationBarColor = PaywallBackground.toArgb()
            controller.isAppearanceLightStatusBars = true
            controller.isAppearanceLightNavigationBars = true
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
        color = PaywallBackground
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(Color.White, PaywallBackground, PaywallSurfaceSoft.copy(alpha = 0.72f))
                    )
                )
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .navigationBarsPadding()
            ) {
                if (showSuccessState) {
                    SuccessState(onDismiss = onDismiss)
                } else {
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = layout.horizontalPadding),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Spacer(modifier = Modifier.height(layout.topPadding))
                        PaywallHero(source = source, layout = layout)
                        Spacer(modifier = Modifier.height(layout.contentSpacing))
                        SectionTitle("Choose your plan", layout = layout)
                        Spacer(modifier = Modifier.height(layout.sectionTitleSpacing))
                        if (isLoading && displayOffers.isEmpty()) {
                            CircularProgressIndicator(
                                color = PaywallBlue,
                                modifier = Modifier.padding(28.dp)
                            )
                        } else if (displayOffers.isEmpty()) {
                            EmptyPlansState(
                                onRetry = subscriptionManager::queryProducts,
                                layout = layout
                            )
                        } else {
                            PlanSelection(
                                offers = displayOffers,
                                selectedOffer = selectedOffer,
                                onSelect = { selectedOffer = it },
                                layout = layout
                            )
                        }
                        Spacer(modifier = Modifier.height(layout.contentSpacing))
                        SectionTitle("What you get", layout = layout)
                        Spacer(modifier = Modifier.height(layout.sectionTitleSpacing))
                        FeatureList(layout = layout)
                        Spacer(modifier = Modifier.height(layout.contentSpacing))
                    }

                    PaywallBottomBar(
                        selectedOffer = selectedOffer,
                        isLoading = isLoading,
                        layout = layout,
                        onSubscribe = { activity ->
                            selectedOffer?.let { offer ->
                                subscriptionManager.launchBillingFlow(activity, offer)
                            }
                        },
                        onRestore = subscriptionManager::restorePurchases
                    )
                }
            }

            CloseButton(onDismiss = onDismiss, layout = layout)
        }
    }
}

@Composable
private fun rememberPaywallLayout(): PaywallLayout {
    val configuration = LocalConfiguration.current
    val isUltraTiny = configuration.screenHeightDp < 640 || configuration.screenWidthDp < 340
    val isTiny = configuration.screenHeightDp < 720 || configuration.screenWidthDp < 370
    val isCompact = configuration.screenHeightDp < 800 || configuration.screenWidthDp < 390

    return PaywallLayout(
        isUltraTiny = isUltraTiny,
        isTiny = isTiny,
        isCompact = isCompact,
        horizontalPadding = if (isUltraTiny) 12.dp else if (configuration.screenWidthDp < 370) 14.dp else 18.dp,
        topPadding = if (isUltraTiny) 14.dp else if (isTiny) 18.dp else 22.dp,
        contentSpacing = if (isUltraTiny) 7.dp else if (isTiny) 9.dp else 12.dp,
        sectionTitleSpacing = if (isUltraTiny) 4.dp else if (isTiny) 6.dp else 8.dp,
        heroMediaHeight = if (isUltraTiny) 190.dp else if (isTiny) 214.dp else if (isCompact) 238.dp else 254.dp,
        heroCornerRadius = if (isUltraTiny) 22.dp else if (isTiny) 24.dp else 28.dp,
        planCardHeight = if (isUltraTiny) 50.dp else if (isTiny) 54.dp else if (isCompact) 58.dp else 60.dp,
        featureCardHeight = if (isUltraTiny) 56.dp else if (isTiny) 62.dp else if (isCompact) 68.dp else 72.dp,
        heroVideoVerticalShift = if (isUltraTiny) 56.dp else if (isTiny) 62.dp else 68.dp,
        bottomPadding = if (isUltraTiny) 6.dp else 10.dp,
        ctaHeight = if (isUltraTiny) 42.dp else if (isTiny) 46.dp else if (isCompact) 50.dp else 52.dp,
        closeButtonSize = if (isUltraTiny) 34.dp else if (isTiny) 36.dp else 38.dp
    )
}

private data class PaywallLayout(
    val isUltraTiny: Boolean,
    val isTiny: Boolean,
    val isCompact: Boolean,
    val horizontalPadding: Dp,
    val topPadding: Dp,
    val contentSpacing: Dp,
    val sectionTitleSpacing: Dp,
    val heroMediaHeight: Dp,
    val heroCornerRadius: Dp,
    val planCardHeight: Dp,
    val featureCardHeight: Dp,
    val heroVideoVerticalShift: Dp,
    val bottomPadding: Dp,
    val ctaHeight: Dp,
    val closeButtonSize: Dp
)

@Composable
private fun PaywallHero(source: PaywallScreenSource, layout: PaywallLayout) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 560.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(if (layout.isTiny) 9.dp else 10.dp)
    ) {
        PremiumBadge(source = source, layout = layout)
        Text(
            text = localizedUiString(heroTitle(source)),
            fontSize = if (layout.isUltraTiny) 26.sp else if (layout.isTiny) 29.sp else if (layout.isCompact) 31.sp else 34.sp,
            lineHeight = if (layout.isUltraTiny) 30.sp else if (layout.isTiny) 34.sp else 38.sp,
            fontWeight = FontWeight.Black,
            color = PaywallText,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth()
        )
        Text(
            text = localizedUiString(heroSubtitle(source)),
            fontSize = if (layout.isUltraTiny) 12.sp else 13.sp,
            lineHeight = if (layout.isUltraTiny) 16.sp else 18.sp,
            fontWeight = FontWeight.Medium,
            color = PaywallMutedText,
            textAlign = TextAlign.Center,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = if (layout.isUltraTiny) 6.dp else 10.dp)
        )
        PaywallHeroVideo(layout = layout)
    }
}

@Composable
private fun PremiumBadge(source: PaywallScreenSource, layout: PaywallLayout) {
    Surface(
        shape = RoundedCornerShape(50),
        color = PaywallBlue.copy(alpha = 0.10f),
        border = BorderStroke(1.dp, PaywallBlue.copy(alpha = 0.14f))
    ) {
        Row(
            modifier = Modifier.padding(
                horizontal = if (layout.isTiny) 12.dp else 16.dp,
                vertical = if (layout.isTiny) 6.dp else 8.dp
            ),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(7.dp)
        ) {
            Icon(
                imageVector = Icons.Default.Star,
                contentDescription = null,
                tint = PaywallBlue,
                modifier = Modifier.size(if (layout.isTiny) 13.dp else 15.dp)
            )
            Text(
                text = localizedUiString(heroBadge(source)),
                fontSize = if (layout.isTiny) 12.sp else 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = PaywallBlue,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun PaywallHeroVideo(layout: PaywallLayout) {
    val shape = RoundedCornerShape(layout.heroCornerRadius)
    val verticalShiftPx = with(LocalDensity.current) { layout.heroVideoVerticalShift.toPx() }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(layout.heroMediaHeight)
            .shadow(18.dp, shape, clip = false)
            .clip(shape)
            .background(
                Brush.verticalGradient(
                    listOf(Color.White, PaywallSurfaceSoft, PaywallBlueLight.copy(alpha = 0.18f))
                )
            )
            .border(1.dp, PaywallBorder.copy(alpha = 0.72f), shape)
    ) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { context ->
                FrameLayout(context).apply {
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                    clipChildren = true
                    clipToPadding = true
                    addView(createHeroTextureView(context, verticalShiftPx))
                }
            },
            update = { container ->
                (container.getChildAt(0) as? TextureView)?.let { textureView ->
                    (textureView.tag as? MediaPlayer)?.let { mediaPlayer ->
                        applyTextureCenterCrop(
                            textureView = textureView,
                            videoWidth = mediaPlayer.videoWidth,
                            videoHeight = mediaPlayer.videoHeight,
                            verticalShiftPx = verticalShiftPx
                        )
                        if (!mediaPlayer.isPlaying) {
                            mediaPlayer.start()
                        }
                    }
                }
            }
        )
    }
}

private fun createHeroTextureView(context: android.content.Context, verticalShiftPx: Float): TextureView {
    return TextureView(context).apply textureView@{
        layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            private var mediaPlayer: MediaPlayer? = null
            private var surface: Surface? = null

            override fun onSurfaceTextureAvailable(surfaceTexture: android.graphics.SurfaceTexture, width: Int, height: Int) {
                releasePlayer()
                val outputSurface = Surface(surfaceTexture)
                surface = outputSurface
                try {
                    val descriptor = context.resources.openRawResourceFd(R.raw.paywall_hero_911)
                    val player = MediaPlayer().apply {
                        descriptor.use {
                            setDataSource(it.fileDescriptor, it.startOffset, it.length)
                        }
                        setSurface(outputSurface)
                        isLooping = true
                        setVolume(0f, 0f)
                        setOnVideoSizeChangedListener { _, videoWidth, videoHeight ->
                            applyTextureCenterCrop(this@textureView, videoWidth, videoHeight, verticalShiftPx)
                        }
                        setOnPreparedListener {
                            applyTextureCenterCrop(this@textureView, videoWidth, videoHeight, verticalShiftPx)
                            start()
                        }
                        prepareAsync()
                    }
                    mediaPlayer = player
                    tag = player
                } catch (_: Exception) {
                    releasePlayer()
                }
            }

            override fun onSurfaceTextureSizeChanged(surfaceTexture: android.graphics.SurfaceTexture, width: Int, height: Int) {
                mediaPlayer?.let { player ->
                    applyTextureCenterCrop(this@textureView, player.videoWidth, player.videoHeight, verticalShiftPx)
                }
            }

            override fun onSurfaceTextureDestroyed(surfaceTexture: android.graphics.SurfaceTexture): Boolean {
                releasePlayer()
                return true
            }

            override fun onSurfaceTextureUpdated(surfaceTexture: android.graphics.SurfaceTexture) = Unit

            private fun releasePlayer() {
                val taggedPlayer = tag as? MediaPlayer
                tag = null
                if (taggedPlayer !== mediaPlayer) {
                    taggedPlayer?.release()
                }
                mediaPlayer?.release()
                mediaPlayer = null
                surface?.release()
                surface = null
            }
        }
    }
}

private fun applyTextureCenterCrop(textureView: TextureView, videoWidth: Int, videoHeight: Int, verticalShiftPx: Float) {
    if (videoWidth <= 0 || videoHeight <= 0) return
    textureView.post {
        val viewWidth = textureView.width.toFloat()
        val viewHeight = textureView.height.toFloat()
        if (viewWidth <= 0f || viewHeight <= 0f) return@post
        val viewRatio = viewWidth / viewHeight
        val videoRatio = videoWidth.toFloat() / videoHeight.toFloat()
        val scaleX: Float
        val scaleY: Float
        if (videoRatio > viewRatio) {
            scaleX = videoRatio / viewRatio
            scaleY = 1f
        } else {
            scaleX = 1f
            scaleY = viewRatio / videoRatio
        }
        val maxShift = ((viewHeight * scaleY) - viewHeight).coerceAtLeast(0f) / 2f
        val matrix = Matrix().apply {
            setScale(scaleX, scaleY, viewWidth / 2f, viewHeight / 2f)
            postTranslate(0f, -verticalShiftPx.coerceIn(0f, maxShift))
        }
        textureView.setTransform(matrix)
    }
}

@Composable
private fun SectionTitle(title: String, layout: PaywallLayout) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 560.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Box(
            modifier = Modifier
                .weight(1f)
                .height(1.dp)
                .background(PaywallBorder)
        )
        Text(
            text = localizedUiString(title),
            fontSize = if (layout.isUltraTiny) 10.sp else if (layout.isTiny) 11.sp else 12.sp,
            fontWeight = FontWeight.ExtraBold,
            color = PaywallMutedText,
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Box(
            modifier = Modifier
                .weight(1f)
                .height(1.dp)
                .background(PaywallBorder)
        )
    }
}

@Composable
private fun EmptyPlansState(onRetry: () -> Unit, layout: PaywallLayout) {
    val isDebugPackage = BuildConfig.APPLICATION_ID.endsWith(".debug")
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 560.dp)
            .heightIn(min = 66.dp),
        shape = RoundedCornerShape(if (layout.isTiny) 18.dp else 20.dp),
        color = PaywallSurface.copy(alpha = 0.92f),
        border = BorderStroke(1.dp, PaywallBorder)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = localizedUiString(
                    if (isDebugPackage) {
                        "Live prices need the Google Play build"
                    } else {
                        "Unable to load plans"
                    }
                ),
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = PaywallText
            )
            if (isDebugPackage) {
                Text(
                    text = localizedUiString("Open the Play Store or billing debug build to load RevenueCat prices."),
                    fontSize = 11.5.sp,
                    lineHeight = 15.sp,
                    color = PaywallMutedText,
                    textAlign = TextAlign.Center
                )
            }
            TextButton(onClick = onRetry) {
                Text(
                    text = localizedUiString("Retry"),
                    color = PaywallBlue,
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
    onSelect: (SubscriptionOffer) -> Unit,
    layout: PaywallLayout
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 560.dp),
        verticalArrangement = Arrangement.spacedBy(if (layout.isTiny) 5.dp else 6.dp)
    ) {
        offers.forEach { offer ->
            PlanCard(
                offer = offer,
                selected = selectedOffer?.productId == offer.productId,
                onClick = { onSelect(offer) },
                layout = layout
            )
        }
    }
}

@Composable
private fun PlanCard(
    offer: SubscriptionOffer,
    selected: Boolean,
    onClick: () -> Unit,
    layout: PaywallLayout
) {
    val shape = RoundedCornerShape(if (layout.isCompact) 14.dp else 16.dp)
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = layout.planCardHeight)
            .clickable(onClick = onClick),
        shape = shape,
        color = if (selected) PaywallSurfaceSoft else PaywallSurface,
        border = BorderStroke(if (selected) 1.5.dp else 1.dp, if (selected) PaywallBlue else PaywallBorder)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = layout.planCardHeight)
                .padding(horizontal = if (layout.isCompact) 12.dp else 14.dp, vertical = if (layout.isCompact) 7.dp else 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(if (layout.isCompact) 10.dp else 12.dp)
        ) {
            SelectionDot(selected = selected, layout = layout)
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = localizedUiString(planName(offer)),
                        fontSize = if (layout.isCompact) 14.sp else 15.5.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = PaywallText,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false)
                    )
                    planBadgeText(offer)?.let { badge ->
                        PlanBadge(text = badge, layout = layout)
                    }
                }
                Text(
                    text = localizedUiString(billingLine(offer)),
                    fontSize = if (layout.isCompact) 10.5.sp else 11.5.sp,
                    color = PaywallMutedText,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Column(
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(1.dp),
                modifier = Modifier.width(if (layout.isCompact) 82.dp else 96.dp)
            ) {
                Text(
                    text = offer.price.ifBlank { "..." },
                    fontSize = if (layout.isCompact) 17.sp else 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (selected) PaywallBlue else PaywallText,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = localizedUiString(periodLabel(offer)),
                    fontSize = if (layout.isCompact) 10.sp else 11.sp,
                    color = PaywallMutedText,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
private fun PlanBadge(text: String, layout: PaywallLayout) {
    Surface(
        shape = RoundedCornerShape(50),
        color = PaywallBlue
    ) {
        Text(
            text = localizedUiString(text),
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 3.dp),
            fontSize = if (layout.isCompact) 8.sp else 9.sp,
            fontWeight = FontWeight.ExtraBold,
            color = Color.White,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun SelectionDot(selected: Boolean, layout: PaywallLayout) {
    Box(
        modifier = Modifier
            .size(if (layout.isCompact) 22.dp else 24.dp)
            .background(if (selected) PaywallBlue else Color.Transparent, CircleShape)
            .border(2.dp, if (selected) PaywallBlue else PaywallBorder, CircleShape),
        contentAlignment = Alignment.Center
    ) {
        if (selected) {
            Icon(
                imageVector = Icons.Default.Check,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(if (layout.isCompact) 10.dp else 11.dp)
            )
        }
    }
}

@Composable
private fun FeatureList(layout: PaywallLayout) {
    val features = listOf(
        PaywallFeatureItem(
            icon = Icons.Default.DirectionsCar,
            title = "Unlimited",
            subtitle = "Add unlimited cars, no restrictions"
        ),
        PaywallFeatureItem(
            icon = Icons.Default.CloudUpload,
            title = "Cloud Sync",
            subtitle = "Synced across all your devices"
        ),
        PaywallFeatureItem(
            icon = Icons.Default.Description,
            title = "PDF Reports",
            subtitle = "Export professional PDF reports"
        )
    )

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 560.dp)
            .clip(RoundedCornerShape(if (layout.isTiny) 18.dp else 20.dp))
            .background(PaywallSurface.copy(alpha = 0.92f))
            .border(1.dp, PaywallBorder, RoundedCornerShape(if (layout.isTiny) 18.dp else 20.dp))
    ) {
        features.forEachIndexed { index, feature ->
            FeatureRow(feature = feature, layout = layout)
            if (index < features.lastIndex) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = if (layout.isUltraTiny) 60.dp else 68.dp)
                        .height(1.dp)
                        .background(PaywallBorder.copy(alpha = 0.82f))
                )
            }
        }
    }
}

@Composable
private fun FeatureRow(feature: PaywallFeatureItem, layout: PaywallLayout) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = layout.featureCardHeight)
            .padding(horizontal = if (layout.isCompact) 9.dp else 10.dp, vertical = if (layout.isCompact) 8.dp else 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(if (layout.isCompact) 8.dp else 10.dp)
    ) {
        Box(
            modifier = Modifier
                .size(if (layout.isUltraTiny) 34.dp else if (layout.isTiny) 38.dp else 42.dp)
                .background(PaywallBlue.copy(alpha = 0.09f), RoundedCornerShape(if (layout.isCompact) 10.dp else 12.dp)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = feature.icon,
                contentDescription = null,
                tint = PaywallBlue,
                modifier = Modifier.size(if (layout.isUltraTiny) 16.dp else if (layout.isTiny) 18.dp else 20.dp)
            )
        }
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                text = localizedUiString(feature.title),
                fontSize = if (layout.isUltraTiny) 13.sp else if (layout.isTiny) 14.sp else 15.5.sp,
                fontWeight = FontWeight.SemiBold,
                color = PaywallText,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = localizedUiString(feature.subtitle),
                fontSize = if (layout.isUltraTiny) 11.sp else if (layout.isTiny) 12.sp else 12.5.sp,
                color = PaywallMutedText,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

private data class PaywallFeatureItem(
    val icon: ImageVector,
    val title: String,
    val subtitle: String
)

@Composable
private fun PaywallBottomBar(
    selectedOffer: SubscriptionOffer?,
    isLoading: Boolean,
    layout: PaywallLayout,
    onSubscribe: (Activity) -> Unit,
    onRestore: () -> Unit
) {
    val activity = LocalContext.current as? Activity
    val uriHandler = LocalUriHandler.current

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                Brush.verticalGradient(
                    listOf(PaywallBackground.copy(alpha = 0f), PaywallBackground.copy(alpha = 0.92f), PaywallBackground)
                )
            )
            .padding(horizontal = layout.horizontalPadding)
            .padding(top = if (layout.isTiny) 5.dp else 6.dp, bottom = layout.bottomPadding),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(if (layout.isTiny) 4.dp else 5.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            Icon(
                imageVector = Icons.Default.Shield,
                contentDescription = null,
                tint = PaywallBlue,
                modifier = Modifier.size(if (layout.isTiny) 12.dp else 13.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = localizedUiString("Cancel anytime. No hidden fees."),
                fontSize = if (layout.isTiny) 12.sp else 12.5.sp,
                color = PaywallMutedText,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }

        PremiumPaywallButton(
            text = localizedUiString(if (isLoading) "Processing..." else ctaText(selectedOffer)),
            onClick = { activity?.let(onSubscribe) },
            enabled = selectedOffer != null && !isLoading,
            modifier = Modifier
                .fillMaxWidth()
                .widthIn(max = 560.dp),
            isLoading = isLoading,
            height = layout.ctaHeight,
            cornerRadius = if (layout.isTiny) 18.dp else 20.dp,
            fontSize = if (layout.isTiny) 17.sp else 18.sp
        )

        selectedOffer?.let { offer ->
            Text(
                text = disclosureText(offer),
                fontSize = if (layout.isTiny) 10.sp else 11.sp,
                color = PaywallMutedText,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }

        TextButton(onClick = onRestore) {
            Text(
                text = localizedUiString("Restore Purchases"),
                color = PaywallBlue,
                fontWeight = FontWeight.Medium,
                fontSize = if (layout.isTiny) 12.sp else 13.sp
            )
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            TextButton(onClick = { uriHandler.openUri("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") }) {
                Text(
                    text = localizedUiString("Terms of Use"),
                    color = PaywallMutedText,
                    fontSize = if (layout.isTiny) 10.sp else 10.5.sp
                )
            }
            Text(
                text = "|",
                color = PaywallMutedText.copy(alpha = 0.45f),
                fontSize = 10.sp
            )
            TextButton(onClick = { uriHandler.openUri("https://www.ezcar24.com/en/privacy-policy") }) {
                Text(
                    text = localizedUiString("Privacy Policy"),
                    color = PaywallMutedText,
                    fontSize = if (layout.isTiny) 10.sp else 10.5.sp
                )
            }
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
                .background(PaywallSuccess.copy(alpha = 0.18f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.Check,
                contentDescription = null,
                tint = PaywallSuccess,
                modifier = Modifier.size(48.dp)
            )
        }
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            text = localizedUiString("You're all set!"),
            fontSize = 26.sp,
            lineHeight = 30.sp,
            fontWeight = FontWeight.ExtraBold,
            color = PaywallText,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = localizedUiString("Your Pro subscription is active. Enjoy full access."),
            fontSize = 16.sp,
            color = PaywallMutedText,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(28.dp))
        Button(
            onClick = onDismiss,
            shape = RoundedCornerShape(18.dp),
            colors = ButtonDefaults.buttonColors(containerColor = PaywallBlue)
        ) {
            Text(localizedUiString("Continue"))
        }
    }
}

@Composable
private fun CloseButton(onDismiss: () -> Unit, layout: PaywallLayout) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(top = if (layout.isTiny) 8.dp else 10.dp, end = 12.dp),
        contentAlignment = Alignment.TopEnd
    ) {
        IconButton(
            onClick = onDismiss,
            modifier = Modifier
                .size(layout.closeButtonSize)
                .background(Color.White.copy(alpha = 0.82f), CircleShape)
                .border(1.dp, PaywallBorder, CircleShape)
        ) {
            Icon(
                imageVector = Icons.Default.Close,
                contentDescription = localizedUiString("Close"),
                tint = PaywallText,
                modifier = Modifier.size(if (layout.isTiny) 13.dp else 14.dp)
            )
        }
    }
}

private fun displayOrder(offer: SubscriptionOffer): Int {
    return when (offer.period) {
        "yearly" -> 0
        "monthly" -> 1
        "weekly" -> 2
        "quarterly" -> 3
        else -> 9
    }
}

private fun heroBadge(source: PaywallScreenSource): String {
    return when (source) {
        PaywallScreenSource.VehicleLimit -> "2-car free limit"
        PaywallScreenSource.AiInsights -> "AI Insights"
        PaywallScreenSource.General -> "Unlock Full Potential"
    }
}

private fun heroTitle(source: PaywallScreenSource): String {
    return when (source) {
        PaywallScreenSource.VehicleLimit -> "Go unlimited"
        PaywallScreenSource.AiInsights -> "AI-powered reports"
        PaywallScreenSource.General -> "Upgrade to Pro"
    }
}

private fun heroSubtitle(source: PaywallScreenSource): String {
    return when (source) {
        PaywallScreenSource.VehicleLimit -> "Unlock unlimited inventory, profit per vehicle, cloud sync, and reports."
        PaywallScreenSource.AiInsights -> "Unlimited inventory, profit tracking, cloud sync, reports, and AI tools."
        PaywallScreenSource.General -> "Unlimited inventory, profit tracking, cloud sync, reports, and AI tools."
    }
}

private fun planName(offer: SubscriptionOffer): String {
    return when (offer.period) {
        "weekly" -> "Weekly"
        "monthly" -> "Monthly"
        "yearly" -> "Yearly"
        "quarterly" -> "Quarterly"
        else -> offer.period.replaceFirstChar { it.uppercase() }
    }
}

private fun billingLine(offer: SubscriptionOffer): String {
    return when (offer.period) {
        "weekly" -> "Billed weekly"
        "monthly" -> "Billed monthly"
        "yearly" -> if (offer.hasFreeTrial) "7 days free, then yearly" else "Billed yearly"
        "quarterly" -> "Billed quarterly"
        else -> "Billed automatically"
    }
}

private fun periodLabel(offer: SubscriptionOffer): String {
    return when (offer.period) {
        "weekly" -> "/ week"
        "monthly" -> "/ month"
        "yearly" -> "/ year"
        "quarterly" -> "/ 3 months"
        else -> ""
    }
}

private fun planBadgeText(offer: SubscriptionOffer): String? {
    return when {
        offer.period == "yearly" -> "Best value"
        offer.hasFreeTrial -> "Trial"
        else -> null
    }
}

private fun ctaText(selectedOffer: SubscriptionOffer?): String {
    return when {
        selectedOffer == null -> "Select a Plan"
        selectedOffer.hasFreeTrial -> "Start Free Trial"
        else -> "Continue"
    }
}

@Composable
private fun disclosureText(offer: SubscriptionOffer): String {
    val priceText = offer.price.ifBlank { "..." }
    return if (offer.period == "yearly") {
        localizedUiString("Renews at %s/year. Cancel anytime.", priceText)
    } else {
        localizedUiString("Renews at %s. Cancel anytime.", priceText)
    }
}
