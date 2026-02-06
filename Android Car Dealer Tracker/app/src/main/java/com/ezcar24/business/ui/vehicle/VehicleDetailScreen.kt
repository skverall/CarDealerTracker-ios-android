package com.ezcar24.business.ui.vehicle

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.runtime.*
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.consume
import androidx.compose.ui.input.pointer.awaitPointerEvent
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.toSize
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import coil.compose.SubcomposeAsyncImage
import com.ezcar24.business.util.ImageUtils
import com.ezcar24.business.ui.theme.*
import com.ezcar24.business.ui.components.*
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import android.net.Uri
import java.math.BigDecimal
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sign
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VehicleDetailScreen(
    vehicleId: String,
    onBack: () -> Unit,
    onEdit: (String) -> Unit,
    viewModel: VehicleViewModel = hiltViewModel()
) {
    LaunchedEffect(vehicleId) {
        viewModel.selectVehicle(vehicleId)
    }

    val uiState by viewModel.uiState.collectAsState()
    val detailState by viewModel.detailUiState.collectAsState()
    val vehicle = detailState.vehicle
    var showDeleteDialog by remember { mutableStateOf(false) }
    val shareScope = rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current

    var showPhotoManager by remember { mutableStateOf(false) }
    var showPhotoViewer by remember { mutableStateOf(false) }
    var viewerIndex by remember { mutableStateOf(0) }
    var pendingUris by remember { mutableStateOf<List<Uri>>(emptyList()) }
    var showUploadSheet by remember { mutableStateOf(false) }
    var replaceCover by remember { mutableStateOf(false) }
    var isUploadingPhotos by remember { mutableStateOf(false) }
    var coverVersion by remember { mutableStateOf(System.currentTimeMillis()) }

    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetMultipleContents()
    ) { uris ->
        if (!uris.isNullOrEmpty()) {
            pendingUris = uris
            replaceCover = detailState.photoItems.isEmpty()
            showUploadSheet = true
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Vehicle Details") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (vehicle != null) {
                        TextButton(onClick = { onEdit(vehicle.id.toString()) }) {
                            Text("Edit", color = EzcarGreen, fontWeight = FontWeight.SemiBold)
                        }
                        IconButton(onClick = {
                            shareScope.launch {
                                val vehicleTitle = listOfNotNull(vehicle.year?.toString(), vehicle.make, vehicle.model)
                                    .joinToString(" ")
                                    .trim()
                                    .ifBlank { "vehicle" }
                                val price = formatCurrency(vehicle.salePrice ?: vehicle.askingPrice ?: vehicle.purchasePrice)
                                var shareText = "Check out this $vehicleTitle.\nAsking: $price"
                                val reportLink = vehicle.reportURL?.trim().orEmpty()
                                if (reportLink.isNotEmpty()) {
                                    shareText += "\nReport: $reportLink"
                                }
                                val sendIntent = android.content.Intent().apply {
                                    action = android.content.Intent.ACTION_SEND
                                    putExtra(android.content.Intent.EXTRA_TEXT, shareText)
                                    putExtra(android.content.Intent.EXTRA_SUBJECT, vehicleTitle)
                                    type = "text/plain"
                                }
                                val shareIntent = android.content.Intent.createChooser(sendIntent, null)
                                context.startActivity(shareIntent)
                            }
                        }) {
                            Icon(Icons.Default.Share, contentDescription = "Share", tint = EzcarGreen)
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = EzcarBackgroundLight)
            )
        },
        containerColor = EzcarBackgroundLight
    ) { paddingValues ->
        if (detailState.isLoading) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = EzcarGreen)
            }
        } else if (vehicle == null) {
            Box(Modifier.fillMaxSize().padding(paddingValues), contentAlignment = Alignment.Center) {
                Text("Vehicle not found", style = MaterialTheme.typography.bodyLarge)
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues)
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                VehiclePhotoSection(
                    vehicleId = vehicle.id,
                    photoItems = detailState.photoItems,
                    coverVersion = coverVersion,
                    onOpenViewer = { index ->
                        viewerIndex = index
                        showPhotoViewer = true
                    }
                )
                PhotoActionRow(
                    hasPhotos = detailState.photoItems.isNotEmpty(),
                    onAddPhotos = { photoPickerLauncher.launch("image/*") },
                    onManagePhotos = { showPhotoManager = true }
                )

                VehicleHeaderCard(vehicle = vehicle, detailState = detailState)

                if (detailState.alerts.isNotEmpty()) {
                    InventoryAlertList(alerts = detailState.alerts)
                }

                FinancialSummaryCard(
                    data = FinancialSummaryData(
                        purchasePrice = detailState.financialSummary.purchasePrice,
                        totalExpenses = detailState.financialSummary.totalExpenses,
                        holdingCost = detailState.financialSummary.holdingCost,
                        totalCost = detailState.financialSummary.totalCost,
                        expenseBreakdown = detailState.financialSummary.expenseBreakdown,
                        askingPrice = vehicle.askingPrice,
                        salePrice = vehicle.salePrice,
                        projectedROI = detailState.financialSummary.projectedROI,
                        actualROI = detailState.financialSummary.actualROI,
                        daysInInventory = detailState.inventoryStats?.daysInInventory ?: 0,
                        agingBucket = detailState.inventoryStats?.agingBucket ?: "0-30"
                    ),
                    onEditAskingPrice = if (vehicle.status != "sold") {
                        { viewModel.updateAskingPrice(detailState.financialSummary.recommendedPrice) }
                    } else null
                )

                if (vehicle.status != "sold") {
                    RecommendedPricingCard(
                        breakEvenPrice = detailState.financialSummary.breakEvenPrice,
                        recommendedPrice = detailState.financialSummary.recommendedPrice,
                        currentAskingPrice = vehicle.askingPrice,
                        onUpdateAskingPrice = { newPrice ->
                            viewModel.updateAskingPrice(newPrice)
                        }
                    )

                    if (detailState.financialSummary.holdingCost > BigDecimal.ZERO) {
                        HoldingCostCard(
                            holdingCost = detailState.financialSummary.holdingCost,
                            totalCost = detailState.financialSummary.totalCost,
                            dailyRate = detailState.financialSummary.dailyHoldingCost,
                            daysInInventory = detailState.inventoryStats?.daysInInventory ?: 0
                        )
                    }
                }

                ExpensesSection(
                    expenses = detailState.expenses,
                    totalExpenses = detailState.financialSummary.totalExpenses
                )

                OutlinedButton(
                    onClick = { showDeleteDialog = true },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.Red),
                    border = androidx.compose.foundation.BorderStroke(1.dp, Color.Red)
                ) {
                    Icon(Icons.Default.Delete, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Delete Vehicle")
                }

                Spacer(modifier = Modifier.height(32.dp))
            }
        }
    }

    if (showDeleteDialog && vehicle != null) {
        AlertDialog(
            onDismissRequest = { showDeleteDialog = false },
            title = { Text("Delete Vehicle?") },
            text = { Text("This action cannot be undone.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.deleteVehicle(vehicle.id)
                        showDeleteDialog = false
                        onBack()
                    }
                ) {
                    Text("Delete", color = Color.Red)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    if (showUploadSheet && vehicle != null) {
        PhotoUploadSheet(
            uris = pendingUris,
            replaceCover = replaceCover,
            isUploading = isUploadingPhotos,
            onReplaceCoverChange = { replaceCover = it },
            onUpload = {
                if (pendingUris.isEmpty()) return@PhotoUploadSheet
                isUploadingPhotos = true
                shareScope.launch {
                    val images = pendingUris.mapNotNull { uri ->
                        ImageUtils.compressImage(context, uri)
                    }
                    viewModel.uploadVehicleImages(vehicle.id, images, replaceCover)
                    coverVersion = System.currentTimeMillis()
                    isUploadingPhotos = false
                    showUploadSheet = false
                    pendingUris = emptyList()
                }
            },
            onDismiss = {
                showUploadSheet = false
                pendingUris = emptyList()
            }
        )
    }

    if (showPhotoManager && vehicle != null) {
        PhotoManagerSheet(
            photos = detailState.photoItems,
            onSaveOrder = { ordered ->
                viewModel.updateVehiclePhotoOrder(vehicle.id, ordered)
                showPhotoManager = false
            },
            onSetCover = { photo ->
                viewModel.setCoverPhoto(vehicle.id, photo)
                coverVersion = System.currentTimeMillis()
            },
            onDelete = { photo ->
                viewModel.deleteVehiclePhoto(vehicle.id, photo)
            },
            onDismiss = { showPhotoManager = false }
        )
    }

    if (showPhotoViewer && vehicle != null) {
        val coverUrl = CloudSyncEnvironment.vehicleImageUrl(vehicle.id)?.let { "$it?ts=$coverVersion" }
        val viewerItems = buildList {
            if (coverUrl != null) {
                add(PhotoViewerItem(isCover = true, url = coverUrl, photo = null))
            }
            detailState.photoItems.forEach { item ->
                add(PhotoViewerItem(isCover = false, url = item.url, photo = item))
            }
        }
        if (viewerItems.isNotEmpty()) {
            PhotoViewerDialog(
                items = viewerItems,
                startIndex = viewerIndex.coerceIn(0, viewerItems.size - 1),
                onClose = { showPhotoViewer = false },
                onSetCover = { photo ->
                    viewModel.setCoverPhoto(vehicle.id, photo)
                    coverVersion = System.currentTimeMillis()
                },
                onDelete = { photo ->
                    viewModel.deleteVehiclePhoto(vehicle.id, photo)
                    showPhotoViewer = false
                },
                onRemoveCover = {
                    viewModel.deleteVehicleCover(vehicle.id)
                    coverVersion = System.currentTimeMillis()
                    showPhotoViewer = false
                }
            )
        }
    }
}

@Composable
private fun VehiclePhotoSection(
    vehicleId: java.util.UUID,
    photoItems: List<VehiclePhotoItem>,
    coverVersion: Long,
    onOpenViewer: (Int) -> Unit
) {
    val coverUrl = CloudSyncEnvironment.vehicleImageUrl(vehicleId)?.let { "$it?ts=$coverVersion" }
    var useCover by remember { mutableStateOf(true) }
    val primaryUrl = if (useCover && coverUrl != null) coverUrl else photoItems.firstOrNull()?.url
    val hasViewerContent = coverUrl != null || photoItems.isNotEmpty()

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(200.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Color(0xFFE0E0E0))
                .clickable(enabled = hasViewerContent) {
                    onOpenViewer(0)
                },
            contentAlignment = Alignment.Center
        ) {
            if (primaryUrl != null) {
                SubcomposeAsyncImage(
                    model = primaryUrl,
                    contentDescription = "Vehicle Photo",
                    modifier = Modifier.fillMaxSize(),
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                    error = {
                        if (useCover && photoItems.isNotEmpty()) {
                            useCover = false
                        } else {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Icon(
                                    Icons.Default.DirectionsCar,
                                    contentDescription = null,
                                    modifier = Modifier.size(64.dp),
                                    tint = Color.Gray
                                )
                                Spacer(modifier = Modifier.height(8.dp))
                                Text("No photo available", color = Color.Gray)
                            }
                        }
                    },
                    loading = {
                        CircularProgressIndicator(color = EzcarGreen, modifier = Modifier.size(32.dp))
                    }
                )
                if (useCover && coverUrl != null) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomStart)
                            .padding(12.dp)
                            .background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(10.dp))
                            .padding(horizontal = 10.dp, vertical = 4.dp)
                    ) {
                        Text("Cover", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
            } else {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        Icons.Default.DirectionsCar,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                        tint = Color.Gray
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text("Tap Edit to add photo", color = Color.Gray)
                }
            }
        }

        if (photoItems.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                photoItems.forEachIndexed { index, item ->
                    SubcomposeAsyncImage(
                        model = item.url,
                        contentDescription = "Vehicle Photo",
                        modifier = Modifier
                            .size(width = 120.dp, height = 80.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .clickable {
                                val start = (if (coverUrl != null) 1 else 0) + index
                                onOpenViewer(start)
                            },
                        contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                        loading = {
                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator(color = EzcarGreen, strokeWidth = 2.dp)
                            }
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun PhotoActionRow(
    hasPhotos: Boolean,
    onAddPhotos: () -> Unit,
    onManagePhotos: () -> Unit
) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
        Button(
            onClick = onAddPhotos,
            modifier = Modifier.weight(1f),
            colors = ButtonDefaults.buttonColors(containerColor = EzcarGreen)
        ) {
            Icon(Icons.Default.Add, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("Add Photos")
        }
        OutlinedButton(
            onClick = onManagePhotos,
            modifier = Modifier.weight(1f),
            enabled = hasPhotos
        ) {
            Icon(Icons.Default.GridOn, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("Manage")
        }
    }
}

data class PhotoViewerItem(
    val isCover: Boolean,
    val url: String,
    val photo: VehiclePhotoItem?
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PhotoUploadSheet(
    uris: List<Uri>,
    replaceCover: Boolean,
    isUploading: Boolean,
    onReplaceCoverChange: (Boolean) -> Unit,
    onUpload: () -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color.White
    ) {
        Column(modifier = Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Upload Photos", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            if (uris.isEmpty()) {
                Text("No photos selected", color = Color.Gray)
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(3),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.heightIn(max = 260.dp)
                ) {
                    itemsIndexed(uris) { _, uri ->
                        SubcomposeAsyncImage(
                            model = uri,
                            contentDescription = null,
                            modifier = Modifier
                                .aspectRatio(1f)
                                .clip(RoundedCornerShape(10.dp)),
                            contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                            loading = {
                                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                    CircularProgressIndicator(color = EzcarGreen, strokeWidth = 2.dp)
                                }
                            }
                        )
                    }
                }
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Set first photo as cover")
                Switch(checked = replaceCover, onCheckedChange = onReplaceCoverChange)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f), enabled = !isUploading) {
                    Text("Cancel")
                }
                Button(
                    onClick = onUpload,
                    modifier = Modifier.weight(1f),
                    enabled = uris.isNotEmpty() && !isUploading,
                    colors = ButtonDefaults.buttonColors(containerColor = EzcarGreen)
                ) {
                    if (isUploading) {
                        CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                    }
                    Text("Upload")
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PhotoManagerSheet(
    photos: List<VehiclePhotoItem>,
    onSaveOrder: (List<VehiclePhotoItem>) -> Unit,
    onSetCover: (VehiclePhotoItem) -> Unit,
    onDelete: (VehiclePhotoItem) -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var workingPhotos by remember { mutableStateOf(photos) }
    val itemBounds = remember { mutableStateMapOf<String, Rect>() }
    var draggingId by remember { mutableStateOf<String?>(null) }
    var dragOffset by remember { mutableStateOf(Offset.Zero) }
    var didReorder by remember { mutableStateOf(false) }
    val haptic = LocalHapticFeedback.current
    LaunchedEffect(photos) { workingPhotos = photos }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color.White
    ) {
        Column(modifier = Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Photo Gallery", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            LazyVerticalGrid(
                columns = GridCells.Fixed(3),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.heightIn(max = 360.dp)
            ) {
                itemsIndexed(workingPhotos, key = { _, item -> item.id }) { index, photo ->
                    val isDragging = draggingId == photo.id
                    val offset = if (isDragging) dragOffset else Offset.Zero
                    PhotoGridItem(
                        modifier = Modifier
                            .onGloballyPositioned { coordinates ->
                                val position = coordinates.positionInParent()
                                itemBounds[photo.id] = Rect(position, coordinates.size.toSize())
                            }
                            .animateItemPlacement()
                            .offset { IntOffset(offset.x.roundToInt(), offset.y.roundToInt()) }
                            .zIndex(if (isDragging) 1f else 0f)
                            .pointerInput(photo.id, workingPhotos) {
                                detectDragGesturesAfterLongPress(
                                    onDragStart = {
                                        draggingId = photo.id
                                        dragOffset = Offset.Zero
                                        didReorder = false
                                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                    },
                                    onDrag = { change, dragAmount ->
                                        change.consume()
                                        dragOffset += dragAmount
                                        val current = itemBounds[photo.id] ?: return@detectDragGesturesAfterLongPress
                                        val center = current.center + dragOffset
                                        val targetId = itemBounds.entries.firstOrNull {
                                            it.key != photo.id && it.value.contains(center)
                                        }?.key
                                        if (targetId != null) {
                                            val from = workingPhotos.indexOfFirst { it.id == photo.id }
                                            val to = workingPhotos.indexOfFirst { it.id == targetId }
                                            if (from != -1 && to != -1 && from != to) {
                                                val updated = workingPhotos.toMutableList()
                                                val moved = updated.removeAt(from)
                                                updated.add(to, moved)
                                                workingPhotos = updated
                                                didReorder = true
                                            }
                                        }
                                    },
                                    onDragEnd = {
                                        val activeId = draggingId
                                        if (activeId != null) {
                                            val current = itemBounds[activeId]
                                            if (current != null && itemBounds.isNotEmpty()) {
                                                val currentCenter = current.center + dragOffset
                                                val nearestId = itemBounds.minByOrNull { entry ->
                                                    val center = entry.value.center
                                                    val dx = center.x - currentCenter.x
                                                    val dy = center.y - currentCenter.y
                                                    (dx * dx) + (dy * dy)
                                                }?.key
                                                if (nearestId != null && nearestId != activeId) {
                                                    val from = workingPhotos.indexOfFirst { it.id == activeId }
                                                    val to = workingPhotos.indexOfFirst { it.id == nearestId }
                                                    if (from != -1 && to != -1 && from != to) {
                                                        val updated = workingPhotos.toMutableList()
                                                        val moved = updated.removeAt(from)
                                                        updated.add(to, moved)
                                                        workingPhotos = updated
                                                        didReorder = true
                                                    }
                                                }
                                            }
                                        }
                                        if (didReorder) {
                                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                        }
                                        draggingId = null
                                        dragOffset = Offset.Zero
                                    },
                                    onDragCancel = {
                                        draggingId = null
                                        dragOffset = Offset.Zero
                                    }
                                )
                            },
                        photo = photo,
                        index = index + 1,
                        isDragging = isDragging,
                        onSetCover = { onSetCover(photo) },
                        onDelete = {
                            onDelete(photo)
                            workingPhotos = workingPhotos.filterNot { it.id == photo.id }
                        }
                    )
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) {
                    Text("Close")
                }
                Button(
                    onClick = { onSaveOrder(workingPhotos) },
                    modifier = Modifier.weight(1f),
                    enabled = workingPhotos.isNotEmpty(),
                    colors = ButtonDefaults.buttonColors(containerColor = EzcarGreen)
                ) {
                    Text("Save Order")
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PhotoViewerDialog(
    items: List<PhotoViewerItem>,
    startIndex: Int,
    onClose: () -> Unit,
    onSetCover: (VehiclePhotoItem) -> Unit,
    onDelete: (VehiclePhotoItem) -> Unit,
    onRemoveCover: () -> Unit
) {
    val pagerState = rememberPagerState(initialPage = startIndex)
    var isZoomed by remember { mutableStateOf(false) }
    LaunchedEffect(pagerState.currentPage) { isZoomed = false }
    androidx.compose.ui.window.Dialog(
        onDismissRequest = onClose,
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
            HorizontalPager(pageCount = items.size, state = pagerState, userScrollEnabled = !isZoomed) { page ->
                val item = items[page]
                val currentPage = pagerState.currentPage
                ZoomableImage(
                    model = item.url,
                    contentDescription = null,
                    onZoomChanged = { zoomed ->
                        if (page == currentPage) {
                            isZoomed = zoomed
                        }
                    }
                )
            }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp)
                    .align(Alignment.TopCenter),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onClose) {
                    Icon(Icons.Default.Close, contentDescription = null, tint = Color.White)
                }
                Spacer(modifier = Modifier.weight(1f))
                Text("${pagerState.currentPage + 1}/${items.size}", color = Color.White)
                Spacer(modifier = Modifier.weight(1f))
                PhotoViewerActions(
                    item = items[pagerState.currentPage],
                    onSetCover = onSetCover,
                    onDelete = onDelete,
                    onRemoveCover = onRemoveCover
                )
            }
        }
    }
}

@Composable
private fun ZoomableImage(
    model: Any?,
    contentDescription: String?,
    onZoomChanged: (Boolean) -> Unit
) {
    var scale by remember { mutableStateOf(1f) }
    val offsetAnim = remember { Animatable(Offset.Zero, Offset.VectorConverter) }
    val offset = offsetAnim.value
    var imageSize by remember { mutableStateOf<Size?>(null) }
    val minScale = 1f
    val maxScale = 4f
    val scope = rememberCoroutineScope()

    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val container = with(androidx.compose.ui.platform.LocalDensity.current) { Size(maxWidth.toPx(), maxHeight.toPx()) }
        val intrinsic = imageSize ?: container
        val baseSize = aspectFitSize(intrinsic, container)
        val clampOffset: (Offset, Float) -> Offset = { value, currentScale ->
            if (currentScale <= minScale) {
                Offset.Zero
            } else {
                val maxX = max(0f, (baseSize.width * currentScale - container.width) / 2f)
                val maxY = max(0f, (baseSize.height * currentScale - container.height) / 2f)
                Offset(
                    x = value.x.coerceIn(-maxX, maxX),
                    y = value.y.coerceIn(-maxY, maxY)
                )
            }
        }
        val rubberBandOffset: (Offset, Float) -> Offset = { value, currentScale ->
            if (currentScale <= minScale) {
                Offset.Zero
            } else {
                val maxX = max(0f, (baseSize.width * currentScale - container.width) / 2f)
                val maxY = max(0f, (baseSize.height * currentScale - container.height) / 2f)
                Offset(
                    x = rubberBand(value.x, maxX),
                    y = rubberBand(value.y, maxY)
                )
            }
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(baseSize, container) {
                    detectTransformGestures { _, pan, zoom, _ ->
                        val newScale = (scale * zoom).coerceIn(minScale, maxScale)
                        scale = newScale
                        val current = offsetAnim.value
                        val proposed = if (newScale > minScale) current + pan else Offset.Zero
                        offsetAnim.snapTo(rubberBandOffset(proposed, newScale))
                        onZoomChanged(newScale > minScale)
                    }
                }
                .pointerInput(baseSize, container, scale) {
                    awaitEachGesture {
                        awaitFirstDown()
                        var pressed = true
                        while (pressed) {
                            val event = awaitPointerEvent()
                            pressed = event.changes.any { it.pressed }
                        }
                        val target = clampOffset(offsetAnim.value, scale)
                        if (target != offsetAnim.value) {
                            offsetAnim.animateTo(target, spring(stiffness = 500f, dampingRatio = 0.85f))
                        }
                    }
                }
                .pointerInput(baseSize, container) {
                    detectTapGestures(
                        onDoubleTap = {
                            scale = minScale
                            onZoomChanged(false)
                            scope.launch {
                                offsetAnim.animateTo(Offset.Zero, spring(stiffness = 500f, dampingRatio = 0.85f))
                            }
                        }
                    )
                }
        ) {
            SubcomposeAsyncImage(
                model = model,
                contentDescription = contentDescription,
                modifier = Modifier
                    .fillMaxSize()
                    .graphicsLayer {
                        scaleX = scale
                        scaleY = scale
                        translationX = offset.x
                        translationY = offset.y
                    },
                contentScale = androidx.compose.ui.layout.ContentScale.Fit,
                onSuccess = { state ->
                    val drawable = state.result.drawable
                    val width = drawable.intrinsicWidth
                    val height = drawable.intrinsicHeight
                    if (width > 0 && height > 0) {
                        imageSize = Size(width.toFloat(), height.toFloat())
                        scope.launch {
                            offsetAnim.snapTo(clampOffset(offsetAnim.value, scale))
                        }
                    }
                },
                loading = {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = EzcarGreen)
                    }
                }
            )
        }
    }
}

private fun aspectFitSize(image: Size, container: Size): Size {
    if (image.width <= 0f || image.height <= 0f || container.width <= 0f || container.height <= 0f) {
        return container
    }
    val imageAspect = image.width / image.height
    val containerAspect = container.width / container.height
    return if (imageAspect > containerAspect) {
        val width = container.width
        val height = width / imageAspect
        Size(width, height)
    } else {
        val height = container.height
        val width = height * imageAspect
        Size(width, height)
    }
}

private fun rubberBand(value: Float, limit: Float): Float {
    if (limit <= 0f) return 0f
    val magnitude = abs(value)
    if (magnitude <= limit) return value
    val excess = magnitude - limit
    val damped = limit + (excess * 0.25f)
    return sign(value) * damped
}

@Composable
private fun PhotoViewerActions(
    item: PhotoViewerItem,
    onSetCover: (VehiclePhotoItem) -> Unit,
    onDelete: (VehiclePhotoItem) -> Unit,
    onRemoveCover: () -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { expanded = true }) {
            Icon(Icons.Default.MoreVert, contentDescription = null, tint = Color.White)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            if (item.isCover) {
                DropdownMenuItem(
                    text = { Text("Remove cover") },
                    onClick = {
                        expanded = false
                        onRemoveCover()
                    }
                )
            } else if (item.photo != null) {
                DropdownMenuItem(
                    text = { Text("Set as cover") },
                    onClick = {
                        expanded = false
                        onSetCover(item.photo)
                    }
                )
                DropdownMenuItem(
                    text = { Text("Delete photo") },
                    onClick = {
                        expanded = false
                        onDelete(item.photo)
                    }
                )
            }
        }
    }
}

@Composable
private fun PhotoGridItem(
    modifier: Modifier = Modifier,
    photo: VehiclePhotoItem,
    index: Int,
    isDragging: Boolean,
    onSetCover: () -> Unit,
    onDelete: () -> Unit
) {
    var menuExpanded by remember { mutableStateOf(false) }
    Box(
        modifier = modifier
            .shadow(if (isDragging) 12.dp else 0.dp, RoundedCornerShape(10.dp), clip = false)
            .graphicsLayer {
                val scale = if (isDragging) 1.03f else 1f
                scaleX = scale
                scaleY = scale
            }
            .aspectRatio(1f)
            .clip(RoundedCornerShape(10.dp))
            .background(Color(0xFFEDEDED))
    ) {
        SubcomposeAsyncImage(
            model = photo.url,
            contentDescription = null,
            modifier = Modifier.fillMaxSize(),
            contentScale = androidx.compose.ui.layout.ContentScale.Crop,
            loading = {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = EzcarGreen, strokeWidth = 2.dp)
                }
            }
        )
        Box(
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(6.dp)
                .background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(8.dp))
                .padding(horizontal = 6.dp, vertical = 2.dp)
        ) {
            Text(index.toString(), color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        }
        IconButton(
            onClick = { menuExpanded = true },
            modifier = Modifier.align(Alignment.TopEnd)
        ) {
            Icon(Icons.Default.MoreVert, contentDescription = null, tint = Color.White)
        }
        DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
            DropdownMenuItem(
                text = { Text("Set as cover") },
                onClick = {
                    menuExpanded = false
                    onSetCover()
                }
            )
            DropdownMenuItem(
                text = { Text("Delete photo") },
                onClick = {
                    menuExpanded = false
                    onDelete()
                }
            )
        }
        Box(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(6.dp)
                .background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(8.dp))
                .padding(horizontal = 6.dp, vertical = 4.dp)
        ) {
            Icon(Icons.Default.DragHandle, contentDescription = null, tint = Color.White, modifier = Modifier.size(14.dp))
        }
        if (isDragging) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .background(Color.Black.copy(alpha = 0.08f))
            )
        }
    }
}

@Composable
private fun VehicleHeaderCard(
    vehicle: com.ezcar24.business.data.local.Vehicle,
    detailState: VehicleDetailUiState
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "${vehicle.make ?: ""} ${vehicle.model ?: ""}".trim().ifEmpty { "Vehicle" },
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "Year: ${vehicle.year ?: "N/A"}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.Gray
                    )
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    VehicleStatusBadge(status = vehicle.status)
                    detailState.inventoryStats?.let { stats ->
                        AgingBucketBadge(daysInInventory = stats.daysInInventory)
                    }
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp), color = Color(0xFFE5E5EA))

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("VIN:", color = Color.Gray, style = MaterialTheme.typography.bodyMedium)
                Text(vehicle.vin, fontWeight = FontWeight.Medium)
            }

            Spacer(modifier = Modifier.height(4.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Purchase Date:", color = Color.Gray, style = MaterialTheme.typography.bodyMedium)
                Text(
                    SimpleDateFormat("MMM dd, yyyy", Locale.getDefault()).format(vehicle.purchaseDate),
                    fontWeight = FontWeight.Medium
                )
            }

            detailState.inventoryStats?.let { stats ->
                Spacer(modifier = Modifier.height(4.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Days in Inventory:", color = Color.Gray, style = MaterialTheme.typography.bodyMedium)
                    Text(
                        "${stats.daysInInventory} days (${stats.agingBucket})",
                        fontWeight = FontWeight.Medium,
                        color = when (stats.agingBucket) {
                            "0-30" -> EzcarGreen
                            "31-60" -> EzcarWarning
                            "61-90" -> EzcarOrange
                            else -> EzcarDanger
                        }
                    )
                }
            }

            if (!vehicle.notes.isNullOrBlank()) {
                HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp), color = Color(0xFFE5E5EA))
                Text("Notes", style = MaterialTheme.typography.labelMedium, color = Color.Gray)
                Spacer(modifier = Modifier.height(4.dp))
                Text(vehicle.notes, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@Composable
private fun ExpensesSection(
    expenses: List<com.ezcar24.business.data.local.Expense>,
    totalExpenses: BigDecimal
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "Expenses (${expenses.size})",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    formatCurrency(totalExpenses),
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Bold,
                    color = EzcarOrange
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            if (expenses.isEmpty()) {
                Text(
                    "No expenses recorded for this vehicle",
                    color = Color.Gray,
                    style = MaterialTheme.typography.bodyMedium
                )
            } else {
                expenses.take(5).forEach { expense ->
                    ExpenseRow(expense = expense)
                    if (expense != expenses.take(5).last()) {
                        HorizontalDivider(
                            modifier = Modifier.padding(vertical = 8.dp),
                            color = Color(0xFFE5E5EA)
                        )
                    }
                }

                if (expenses.size > 5) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "+${expenses.size - 5} more expenses",
                        color = Color.Gray,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.align(Alignment.CenterHorizontally)
                    )
                }
            }
        }
    }
}

@Composable
private fun ExpenseRow(expense: com.ezcar24.business.data.local.Expense) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column {
            Text(
                text = expense.expenseDescription ?: expense.category,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = SimpleDateFormat("MMM dd, yyyy", Locale.getDefault()).format(expense.date),
                style = MaterialTheme.typography.bodySmall,
                color = Color.Gray
            )
        }
        Text(
            text = formatCurrency(expense.amount),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
fun VehicleStatusBadge(status: String) {
    val (text, color) = when (status) {
        "owned" -> "Owned" to Color.Gray
        "on_sale" -> "On Sale" to EzcarGreen
        "in_transit" -> "In Transit" to EzcarPurple
        "under_service" -> "Service" to EzcarOrange
        "sold" -> "Sold" to EzcarBlueBright
        else -> status.replaceFirstChar { it.uppercase() } to EzcarGreen
    }

    Text(
        text = text,
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        color = color,
        modifier = Modifier
            .background(color.copy(alpha = 0.1f), RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 4.dp)
    )
}

@Composable
fun FinancialDetailRow(
    label: String,
    amount: BigDecimal?,
    color: Color = Color.Black,
    isBold: Boolean = false
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            label,
            color = if (isBold) Color.Black else Color.Gray,
            fontWeight = if (isBold) FontWeight.Bold else FontWeight.Normal
        )
        Text(
            text = formatCurrency(amount),
            fontWeight = if (isBold) FontWeight.Bold else FontWeight.Medium,
            color = color
        )
    }
}

@Composable
fun FinancialDetailRow(
    label: String,
    value: String,
    color: Color = Color.Black,
    isBold: Boolean = false
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            label,
            color = if (isBold) Color.Black else Color.Gray,
            fontWeight = if (isBold) FontWeight.Bold else FontWeight.Normal
        )
        Text(
            text = value,
            fontWeight = if (isBold) FontWeight.Bold else FontWeight.Medium,
            color = color
        )
    }
}

private fun formatCurrency(amount: BigDecimal?): String {
    return amount?.let {
        NumberFormat.getCurrencyInstance(Locale.US).format(it).replace("$", "AED ")
    } ?: "-"
}
