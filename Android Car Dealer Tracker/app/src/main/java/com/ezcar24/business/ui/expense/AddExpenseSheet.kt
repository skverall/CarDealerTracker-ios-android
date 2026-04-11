package com.ezcar24.business.ui.expense

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import android.widget.DatePicker
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.ripple.rememberRipple
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ezcar24.business.data.local.ExpenseCategoryType
import com.ezcar24.business.data.local.ExpenseTemplate
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.data.local.User
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.ui.theme.*
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.io.ByteArrayOutputStream
import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddExpenseSheet(
    onDismiss: () -> Unit,
    onSave: (BigDecimal, Date, String, String, Vehicle?, User?, FinancialAccount?, ExpenseCategoryType, ExpenseReceiptDraft?) -> Unit,
    onSaveTemplate: (String, String, BigDecimal?, String?, Vehicle?, User?, FinancialAccount?) -> Unit,
    vehicles: List<Vehicle>,
    users: List<User>,
    accounts: List<FinancialAccount>,
    templates: List<ExpenseTemplate>,
    currencyCode: String
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    var amountStr by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }
    var category by remember { mutableStateOf("vehicle") }
    var date by remember { mutableStateOf(Date()) }
    var expenseType by remember { mutableStateOf(ExpenseCategoryType.OPERATIONAL) }

    var selectedVehicle by remember { mutableStateOf<Vehicle?>(null) }
    var selectedUser by remember { mutableStateOf<User?>(null) }
    var selectedAccount by remember { mutableStateOf<FinancialAccount?>(null) }

    var showVehicleSheet by remember { mutableStateOf(false) }
    var showUserSheet by remember { mutableStateOf(false) }
    var showAccountSheet by remember { mutableStateOf(false) }
    var showMoreMenu by remember { mutableStateOf(false) }
    var showTemplatesSheet by remember { mutableStateOf(false) }
    var showSaveTemplateDialog by remember { mutableStateOf(false) }
    var showReceiptActionsSheet by remember { mutableStateOf(false) }
    var templateName by remember { mutableStateOf("") }
    var receiptDraft by remember { mutableStateOf<ExpenseReceiptDraft?>(null) }

    val context = LocalContext.current
    val focusManager = LocalFocusManager.current
    val isValid = amountStr.isNotEmpty() && (amountStr.toBigDecimalOrNull() ?: BigDecimal.ZERO) > BigDecimal.ZERO
    val openReceiptPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            val draft = readExpenseReceiptDraft(context, uri)
            if (draft != null) {
                receiptDraft = draft
            } else {
                android.widget.Toast.makeText(context, "Could not attach receipt", android.widget.Toast.LENGTH_SHORT).show()
            }
        }
    }
    val takePhotoLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.TakePicturePreview()
    ) { bitmap ->
        if (bitmap != null) {
            receiptDraft = bitmap.toExpenseReceiptDraft()
        }
    }

    val categories = remember {
        listOf(
            Triple("vehicle", "Vehicle", Icons.Default.DirectionsCar),
            Triple("personal", "Personal", Icons.Default.Person),
            Triple("employee", "Employee", Icons.Default.Work),
            Triple("office", "Bills", Icons.Default.Business),
            Triple("marketing", "Marketing", Icons.Default.Campaign)
        )
    }

    val expenseTypes = listOf(
        Triple(ExpenseCategoryType.HOLDING_COST, "Holding Cost", Icons.Default.Schedule),
        Triple(ExpenseCategoryType.IMPROVEMENT, "Improvement", Icons.Default.Build),
        Triple(ExpenseCategoryType.OPERATIONAL, "Operational", Icons.Default.TrendingUp)
    )

    LaunchedEffect(category) {
        if (category != "vehicle") {
            selectedVehicle = null
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = EzcarBackgroundLight,
        dragHandle = null
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(bottom = 80.dp)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .statusBarsPadding()
                        .padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 16.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(
                        onClick = onDismiss,
                        modifier = Modifier
                            .size(44.dp)
                            .background(Color.White, CircleShape)
                    ) {
                        Icon(
                            Icons.Default.Close,
                            contentDescription = "Close",
                            tint = Color.Black,
                            modifier = Modifier.size(24.dp)
                        )
                    }

                    Text(
                        text = "New Expense",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )

                    Box {
                        IconButton(
                            onClick = { showMoreMenu = true },
                            modifier = Modifier
                                .size(44.dp)
                                .background(Color.White, CircleShape)
                        ) {
                            Icon(
                                Icons.Default.MoreHoriz,
                                contentDescription = "Menu",
                                tint = EzcarNavy,
                                modifier = Modifier.size(24.dp)
                            )
                        }

                        DropdownMenu(
                            expanded = showMoreMenu,
                            onDismissRequest = { showMoreMenu = false }
                        ) {
                            if (templates.isNotEmpty()) {
                                DropdownMenuItem(
                                    text = { Text("Use Template") },
                                    leadingIcon = { Icon(Icons.Default.AutoAwesome, contentDescription = null) },
                                    onClick = {
                                        showMoreMenu = false
                                        showTemplatesSheet = true
                                    }
                                )
                            }
                            DropdownMenuItem(
                                text = { Text("Save as Template") },
                                leadingIcon = { Icon(Icons.Default.BookmarkBorder, contentDescription = null) },
                                onClick = {
                                    templateName = description.trim().takeIf { it.isNotEmpty() } ?: "Template"
                                    showMoreMenu = false
                                    showSaveTemplateDialog = true
                                }
                            )
                        }
                    }
                }

                LazyColumn(
                    modifier = Modifier.fillMaxWidth(),
                    contentPadding = PaddingValues(vertical = 16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    item {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            modifier = Modifier.padding(bottom = 24.dp)
                        ) {
                            Text(
                                "AMOUNT",
                                style = MaterialTheme.typography.labelSmall,
                                fontWeight = FontWeight.Bold,
                                color = Color.Gray,
                                letterSpacing = 1.sp
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.Center,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    currencyCode,
                                    style = MaterialTheme.typography.headlineSmall,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color.Gray
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                androidx.compose.foundation.text.BasicTextField(
                                    value = amountStr,
                                    onValueChange = { if (it.count { c -> c == '.' } <= 1) amountStr = it },
                                    textStyle = MaterialTheme.typography.displayLarge.copy(
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 48.sp,
                                        color = MaterialTheme.colorScheme.onSurface
                                    ),
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                    decorationBox = { innerTextField ->
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            if (amountStr.isEmpty()) {
                                                Text("0", style = MaterialTheme.typography.displayLarge.copy(fontWeight = FontWeight.Bold, fontSize = 48.sp, color = Color.LightGray))
                                            } else {
                                                innerTextField()
                                            }
                                        }
                                    },
                                    modifier = Modifier.width(IntrinsicSize.Min)
                                )
                            }
                        }
                    }

                    item {
                        LazyRow(
                            contentPadding = PaddingValues(horizontal = 20.dp),
                            horizontalArrangement = Arrangement.spacedBy(16.dp),
                            modifier = Modifier.padding(bottom = 24.dp)
                        ) {
                            items(categories) { (key, title, icon) ->
                                CategoryItem(
                                    title = title,
                                    icon = icon,
                                    isSelected = category == key,
                                    onClick = {
                                        category = key
                                        focusManager.clearFocus()
                                    }
                                )
                            }
                        }
                    }

                    item {
                        Column(
                            modifier = Modifier
                                .padding(horizontal = 20.dp)
                                .padding(bottom = 16.dp)
                        ) {
                            Text(
                                text = "Expense Type",
                                style = MaterialTheme.typography.labelMedium,
                                color = Color.Gray,
                                modifier = Modifier.padding(bottom = 8.dp)
                            )

                            LazyRow(
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                items(expenseTypes) { (type, title, icon) ->
                                    val isSelected = expenseType == type
                                    FilterChip(
                                        selected = isSelected,
                                        onClick = { expenseType = type },
                                        label = { Text(title) },
                                        leadingIcon = {
                                            Icon(
                                                imageVector = icon,
                                                contentDescription = null,
                                                modifier = Modifier.size(18.dp)
                                            )
                                        },
                                        colors = FilterChipDefaults.filterChipColors(
                                            selectedContainerColor = EzcarNavy,
                                            selectedLabelColor = Color.White,
                                            selectedLeadingIconColor = Color.White
                                        ),
                                        border = if (!isSelected) {
                                            FilterChipDefaults.filterChipBorder(
                                                enabled = true,
                                                selected = false
                                            )
                                        } else null
                                    )
                                }
                            }
                        }
                    }

                    item {
                        Column(
                            modifier = Modifier
                                .padding(horizontal = 20.dp)
                                .shadow(4.dp, RoundedCornerShape(20.dp))
                                .background(Color.White, RoundedCornerShape(20.dp))
                                .clip(RoundedCornerShape(20.dp))
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                                verticalAlignment = Alignment.Top
                            ) {
                                Icon(Icons.Default.Subject, contentDescription = null, tint = Color.Gray)
                                Spacer(modifier = Modifier.width(16.dp))
                                Box(modifier = Modifier.weight(1f)) {
                                    if (description.isEmpty()) {
                                        Text("What is this for?", color = Color.Gray)
                                    }
                                    TextField(
                                        value = description,
                                        onValueChange = { description = it },
                                        colors = TextFieldDefaults.colors(
                                            focusedContainerColor = Color.Transparent,
                                            unfocusedContainerColor = Color.Transparent,
                                            focusedIndicatorColor = Color.Transparent,
                                            unfocusedIndicatorColor = Color.Transparent
                                        ),
                                        modifier = Modifier.fillMaxWidth()
                                            .offset(x = (-12).dp, y = (-12).dp)
                                    )
                                }
                            }

                            Divider(color = Color.LightGray.copy(alpha = 0.3f), modifier = Modifier.padding(start = 56.dp))

                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        val cal = Calendar.getInstance()
                                        cal.time = date
                                        DatePickerDialog(
                                            context,
                                            { _, y, m, d ->
                                                cal.set(y, m, d)
                                                TimePickerDialog(
                                                    context,
                                                    { _, hour, minute ->
                                                        cal.set(Calendar.HOUR_OF_DAY, hour)
                                                        cal.set(Calendar.MINUTE, minute)
                                                        date = cal.time
                                                    },
                                                    cal.get(Calendar.HOUR_OF_DAY),
                                                    cal.get(Calendar.MINUTE),
                                                    true
                                                ).show()
                                            },
                                            cal.get(Calendar.YEAR),
                                            cal.get(Calendar.MONTH),
                                            cal.get(Calendar.DAY_OF_MONTH)
                                        ).show()
                                    }
                                    .padding(16.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(Icons.Default.CalendarToday, contentDescription = null, tint = Color.Gray)
                                Spacer(modifier = Modifier.width(16.dp))
                                Text("Date", style = MaterialTheme.typography.bodyLarge)
                                Spacer(modifier = Modifier.weight(1f))
                                Text(
                                    SimpleDateFormat("MMM dd, HH:mm", Locale.getDefault()).format(date),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = EzcarNavy,
                                    fontWeight = FontWeight.SemiBold
                                )
                                Icon(Icons.Default.KeyboardArrowDown, contentDescription = null, tint = Color.Gray, modifier = Modifier.size(20.dp))
                            }
                        }
                        Spacer(modifier = Modifier.height(20.dp))
                    }

                    item {
                        Column(
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                            modifier = Modifier.padding(horizontal = 20.dp)
                        ) {
                            if (category == "vehicle") {
                                ContextSelectorButton(
                                    title = "Vehicle",
                                    value = selectedVehicle?.let { "${it.year} ${it.make} ${it.model}" } ?: "Select Vehicle",
                                    icon = Icons.Default.DirectionsCar,
                                    isActive = selectedVehicle != null,
                                    onClick = { showVehicleSheet = true }
                                )
                            }

                            ContextSelectorButton(
                                title = "Paid By",
                                value = selectedUser?.name ?: "Select User",
                                icon = Icons.Default.Person,
                                isActive = selectedUser != null,
                                onClick = { showUserSheet = true }
                            )

                            ContextSelectorButton(
                                title = "Account",
                                value = selectedAccount?.accountType?.replaceFirstChar { it.titlecase() } ?: "Select Account",
                                icon = Icons.Default.CreditCard,
                                isActive = selectedAccount != null,
                                onClick = { showAccountSheet = true }
                            )

                            ContextSelectorButton(
                                title = "Receipt",
                                value = receiptDraft?.fileName ?: "Attach receipt",
                                icon = Icons.Default.ReceiptLong,
                                isActive = receiptDraft != null,
                                onClick = { showReceiptActionsSheet = true }
                            )
                        }
                    }
                }
            }

            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(20.dp)
                    .fillMaxWidth()
            ) {
                Button(
                    onClick = {
                        val amt = amountStr.toBigDecimalOrNull()
                        if (amt != null && amt > BigDecimal.ZERO) {
                            onSave(
                                amt,
                                date,
                                description,
                                category,
                                selectedVehicle,
                                selectedUser,
                                selectedAccount,
                                expenseType,
                                receiptDraft
                            )
                        }
                    },
                    enabled = isValid,
                    colors = ButtonDefaults.buttonColors(containerColor = EzcarNavy, disabledContainerColor = Color.Gray),
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp)
                        .shadow(if (isValid) 8.dp else 0.dp, RoundedCornerShape(16.dp)),
                    shape = RoundedCornerShape(16.dp)
                ) {
                    Text(
                        "Save Expense",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }
            }
        }

        if (showVehicleSheet) {
            ModalBottomSheet(onDismissRequest = { showVehicleSheet = false }, containerColor = Color.White) {
                SelectionListSheet(
                    title = "Select Vehicle",
                    items = vehicles,
                    itemContent = { vehicle ->
                        Column {
                            Text("${vehicle.year} ${vehicle.make} ${vehicle.model}", fontWeight = FontWeight.SemiBold)
                            Text(vehicle.vin ?: "No VIN", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
                        }
                    },
                    onSelect = {
                        selectedVehicle = it
                        showVehicleSheet = false
                    },
                    onClear = {
                        selectedVehicle = null
                        showVehicleSheet = false
                    }
                )
            }
        }

        if (showUserSheet) {
            ModalBottomSheet(onDismissRequest = { showUserSheet = false }, containerColor = Color.White) {
                SelectionListSheet(
                    title = "Select User",
                    items = users,
                    itemContent = { user -> 
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                modifier = Modifier
                                    .size(36.dp)
                                    .clip(CircleShape)
                                    .background(EzcarBackgroundLight),
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(Icons.Default.Person, null, tint = EzcarNavy, modifier = Modifier.size(20.dp))
                            }
                            Spacer(modifier = Modifier.width(16.dp))
                            Text(user.name ?: "Unknown", fontWeight = FontWeight.SemiBold)
                        }
                    },
                    onSelect = {
                        selectedUser = it
                        showUserSheet = false
                    },
                    onClear = {
                        selectedUser = null
                        showUserSheet = false
                    },
                    onAddClick = {
                        android.widget.Toast.makeText(context, "Add User feature coming soon", android.widget.Toast.LENGTH_SHORT).show()
                    }
                )
            }
        }

        if (showAccountSheet) {
            ModalBottomSheet(onDismissRequest = { showAccountSheet = false }, containerColor = Color.White) {
                SelectionListSheet(
                    title = "Select Account",
                    items = accounts,
                    itemContent = { account -> 
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            val isCash = account.accountType?.lowercase() == "cash"
                            Box(
                                modifier = Modifier
                                    .size(36.dp)
                                    .clip(CircleShape)
                                    .background(EzcarBackgroundLight),
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(if (isCash) Icons.Default.Money else Icons.Default.AccountBalance, null, tint = EzcarNavy, modifier = Modifier.size(20.dp))
                            }
                            Spacer(modifier = Modifier.width(16.dp))
                            Text(account.accountType?.replaceFirstChar { it.titlecase() } ?: "Account", fontWeight = FontWeight.SemiBold)
                        }
                    },
                    onSelect = {
                        selectedAccount = it
                        showAccountSheet = false
                    },
                    onClear = {
                        selectedAccount = null
                        showAccountSheet = false
                    },
                    onAddClick = {
                        android.widget.Toast.makeText(context, "Add Account feature coming soon", android.widget.Toast.LENGTH_SHORT).show()
                    }
                )
            }
        }

        if (showTemplatesSheet) {
            ModalBottomSheet(onDismissRequest = { showTemplatesSheet = false }, containerColor = Color.White) {
                TemplateSelectionSheet(
                    templates = templates,
                    onDismiss = { showTemplatesSheet = false },
                    onApply = { template ->
                        amountStr = template.defaultAmount?.stripTrailingZeros()?.toPlainString().orEmpty()
                        description = template.defaultDescription.orEmpty()
                        category = template.category ?: "vehicle"
                        selectedVehicle = vehicles.firstOrNull { it.id == template.vehicleId }
                        selectedUser = users.firstOrNull { it.id == template.userId }
                        selectedAccount = accounts.firstOrNull { it.id == template.accountId }
                        showTemplatesSheet = false
                    }
                )
            }
        }

        if (showReceiptActionsSheet) {
            ModalBottomSheet(
                onDismissRequest = { showReceiptActionsSheet = false },
                containerColor = Color.White
            ) {
                ReceiptActionSheet(
                    hasReceipt = receiptDraft != null,
                    receiptLabel = receiptDraft?.fileName,
                    onDismiss = { showReceiptActionsSheet = false },
                    onTakePhoto = {
                        showReceiptActionsSheet = false
                        takePhotoLauncher.launch(null)
                    },
                    onChooseFile = {
                        showReceiptActionsSheet = false
                        openReceiptPickerLauncher.launch(arrayOf("image/*", "application/pdf"))
                    },
                    onRemove = {
                        receiptDraft = null
                        showReceiptActionsSheet = false
                    }
                )
            }
        }

        if (showSaveTemplateDialog) {
            AlertDialog(
                onDismissRequest = { showSaveTemplateDialog = false },
                title = { Text("Save Template") },
                text = {
                    Column {
                        OutlinedTextField(
                            value = templateName,
                            onValueChange = { templateName = it },
                            label = { Text("Template Name") },
                            singleLine = true
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = "This saves the current category, amount, description, vehicle, user and account.",
                            style = MaterialTheme.typography.bodySmall,
                            color = Color.Gray
                        )
                    }
                },
                confirmButton = {
                    TextButton(
                        onClick = {
                            onSaveTemplate(
                                templateName,
                                category,
                                amountStr.toBigDecimalOrNull(),
                                description,
                                selectedVehicle,
                                selectedUser,
                                selectedAccount
                            )
                            showSaveTemplateDialog = false
                            android.widget.Toast.makeText(
                                context,
                                "Template saved",
                                android.widget.Toast.LENGTH_SHORT
                            ).show()
                        },
                        enabled = templateName.trim().isNotEmpty()
                    ) {
                        Text("Save")
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showSaveTemplateDialog = false }) {
                        Text("Cancel")
                    }
                }
            )
        }
    }
}

@Composable
fun CategoryItem(title: String, icon: ImageVector, isSelected: Boolean, onClick: () -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = null,
            onClick = onClick
        )
    ) {
        Box(
            modifier = Modifier
                .size(64.dp)
                .shadow(if (isSelected) 8.dp else 0.dp, CircleShape, spotColor = EzcarNavy.copy(alpha = 0.5f))
                .background(if (isSelected) EzcarNavy else EzcarBackgroundLight, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = title,
                tint = if (isSelected) Color.White else Color.Gray,
                modifier = Modifier.size(28.dp)
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            title,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (isSelected) EzcarNavy else Color.Gray
        )
    }
}

@Composable
fun ContextSelectorButton(
    title: String,
    value: String,
    icon: ImageVector,
    isActive: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(2.dp, RoundedCornerShape(16.dp))
            .background(Color.White, RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .background(if (isActive) EzcarNavy.copy(alpha = 0.1f) else EzcarBackgroundLight, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = if (isActive) EzcarNavy else Color.Gray,
                modifier = Modifier.size(20.dp)
            )
        }

        Spacer(modifier = Modifier.width(16.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.labelSmall, color = Color.Gray)
            Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1)
        }

        Icon(Icons.Default.ChevronRight, contentDescription = null, tint = Color.LightGray)
    }
}

@Composable
fun <T> SelectionListSheet(
    title: String,
    items: List<T>,
    itemContent: @Composable (T) -> Unit,
    onSelect: (T) -> Unit,
    onClear: () -> Unit,
    onAddClick: (() -> Unit)? = null
) {
    Column(modifier = Modifier.padding(bottom = 50.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            if (onAddClick != null) {
                IconButton(onClick = onAddClick) {
                    Icon(Icons.Default.Add, contentDescription = "Add", tint = EzcarNavy)
                }
            }
        }

        LazyColumn {
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(onClick = onClear)
                        .padding(horizontal = 20.dp, vertical = 16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("None", color = Color.Gray)
                }
                Divider(thickness = 0.5.dp, color = Color.LightGray.copy(alpha = 0.3f))
            }

            items(items) { item ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onSelect(item) }
                        .padding(horizontal = 20.dp, vertical = 16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    itemContent(item)
                }
                Divider(thickness = 0.5.dp, color = Color.LightGray.copy(alpha = 0.3f))
            }
        }
    }
}

@Composable
fun TemplateSelectionSheet(
    templates: List<ExpenseTemplate>,
    onDismiss: () -> Unit,
    onApply: (ExpenseTemplate) -> Unit
) {
    Column(modifier = Modifier.padding(bottom = 50.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Templates",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            TextButton(onClick = onDismiss) {
                Text("Close")
            }
        }

        if (templates.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "No saved templates yet",
                    color = Color.Gray
                )
            }
        } else {
            LazyColumn {
                items(templates) { template ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onApply(template) }
                            .padding(horizontal = 20.dp, vertical = 14.dp)
                    ) {
                        Text(
                            text = template.name,
                            style = MaterialTheme.typography.bodyLarge,
                            fontWeight = FontWeight.SemiBold
                        )
                        val subtitle = listOfNotNull(
                            template.category?.replaceFirstChar { it.titlecase() },
                            template.defaultDescription?.takeIf { it.isNotBlank() }
                        ).joinToString(" • ")
                        if (subtitle.isNotBlank()) {
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                text = subtitle,
                                style = MaterialTheme.typography.bodySmall,
                                color = Color.Gray
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun ReceiptActionSheet(
    hasReceipt: Boolean,
    receiptLabel: String?,
    onDismiss: () -> Unit,
    onTakePhoto: () -> Unit,
    onChooseFile: () -> Unit,
    onRemove: () -> Unit
) {
    Column(modifier = Modifier.padding(bottom = 50.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = "Receipt",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                receiptLabel?.let {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = it,
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.Gray
                    )
                }
            }
            TextButton(onClick = onDismiss) {
                Text("Close")
            }
        }

        ReceiptActionRow(
            icon = Icons.Default.PhotoCamera,
            title = "Take Photo",
            onClick = onTakePhoto
        )
        ReceiptActionRow(
            icon = Icons.Default.AttachFile,
            title = "Choose File",
            onClick = onChooseFile
        )
        if (hasReceipt) {
            ReceiptActionRow(
                icon = Icons.Default.DeleteOutline,
                title = "Remove Receipt",
                titleColor = MaterialTheme.colorScheme.error,
                onClick = onRemove
            )
        }
    }
}

@Composable
private fun ReceiptActionRow(
    icon: ImageVector,
    title: String,
    titleColor: Color = MaterialTheme.colorScheme.onSurface,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = titleColor
        )
        Spacer(modifier = Modifier.width(16.dp))
        Text(
            text = title,
            style = MaterialTheme.typography.bodyLarge,
            color = titleColor
        )
    }
}

fun readExpenseReceiptDraft(context: Context, uri: Uri): ExpenseReceiptDraft? {
    val resolver = context.contentResolver
    val bytes = resolver.openInputStream(uri)?.use { it.readBytes() } ?: return null
    val rawName = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) {
            cursor.getString(0)
        } else {
            null
        }
    }
    val contentType = resolver.getType(uri) ?: "application/octet-stream"
    val baseFileName = rawName?.takeIf { it.isNotBlank() } ?: "receipt-${System.currentTimeMillis()}"
    val extensionFromName = baseFileName.substringAfterLast('.', "").lowercase(Locale.US)
    val fileExtension = extensionFromName.ifBlank {
        MimeTypeMap.getSingleton()
            .getExtensionFromMimeType(contentType)
            ?.lowercase(Locale.US)
            ?: "bin"
    }
    val fileName = if (extensionFromName.isBlank()) {
        "$baseFileName.$fileExtension"
    } else {
        baseFileName
    }
    return ExpenseReceiptDraft(
        bytes = bytes,
        fileName = fileName,
        contentType = contentType,
        fileExtension = fileExtension
    )
}

fun Bitmap.toExpenseReceiptDraft(): ExpenseReceiptDraft {
    val output = ByteArrayOutputStream()
    compress(Bitmap.CompressFormat.JPEG, 85, output)
    val timestamp = System.currentTimeMillis()
    return ExpenseReceiptDraft(
        bytes = output.toByteArray(),
        fileName = "receipt-$timestamp.jpg",
        contentType = "image/jpeg",
        fileExtension = "jpg"
    )
}
