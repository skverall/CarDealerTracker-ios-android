package com.ezcar24.business.ui.expense

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.widget.DatePicker
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
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.data.local.User
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.ui.theme.*
import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddExpenseSheet(
    onDismiss: () -> Unit,
    onSave: (BigDecimal, Date, String, String, Vehicle?, User?, FinancialAccount?) -> Unit,
    vehicles: List<Vehicle>,
    users: List<User>,
    accounts: List<FinancialAccount>
) {
    // Form State
    var amountStr by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }
    var category by remember { mutableStateOf("vehicle") } // Default to vehicle
    var date by remember { mutableStateOf(Date()) }

    // Context Selection State
    var selectedVehicle by remember { mutableStateOf<Vehicle?>(null) }
    var selectedUser by remember { mutableStateOf<User?>(null) }
    var selectedAccount by remember { mutableStateOf<FinancialAccount?>(null) }

    // Sheet State
    var showVehicleSheet by remember { mutableStateOf(false) }
    var showUserSheet by remember { mutableStateOf(false) }
    var showAccountSheet by remember { mutableStateOf(false) }

    // Helpers
    val context = LocalContext.current
    val focusManager = LocalFocusManager.current
    val isValid = amountStr.isNotEmpty() && (amountStr.toBigDecimalOrNull() ?: BigDecimal.ZERO) > BigDecimal.ZERO
    
    // Categories matching iOS
    val categories = remember {
        listOf(
            Triple("vehicle", "Vehicle", Icons.Default.DirectionsCar),
            Triple("personal", "Personal", Icons.Default.Person),
            Triple("employee", "Employee", Icons.Default.Work),
            Triple("office", "Bills", Icons.Default.Business),
            Triple("marketing", "Marketing", Icons.Default.Campaign)
        )
    }

    // Effect: reset vehicle if not vehicle category
    LaunchedEffect(category) {
        if (category != "vehicle") {
            selectedVehicle = null
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = EzcarBackgroundLight,
        dragHandle = null // Custom header
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(bottom = 80.dp) // Space for floating button
            ) {
                // --- Header ---
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

                    // Menu Placeholder (Templates)
                    IconButton(
                        onClick = { /* TODO: Templates */ },
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
                }

                LazyColumn(
                    modifier = Modifier.fillMaxWidth(),
                    contentPadding = PaddingValues(vertical = 16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    // --- Hero Amount Input ---
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
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    "AED",
                                    style = MaterialTheme.typography.headlineSmall,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color.Gray
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                TextField(
                                    value = amountStr,
                                    onValueChange = { if (it.count { c -> c == '.' } <= 1) amountStr = it },
                                    textStyle = MaterialTheme.typography.displayLarge.copy(
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 48.sp,
                                        textAlign = TextAlign.Center
                                    ),
                                    colors = TextFieldDefaults.colors(
                                        focusedContainerColor = Color.Transparent,
                                        unfocusedContainerColor = Color.Transparent,
                                        focusedIndicatorColor = Color.Transparent,
                                        unfocusedIndicatorColor = Color.Transparent
                                    ),
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                    placeholder = { 
                                        Text("0", style = MaterialTheme.typography.displayLarge.copy(fontWeight = FontWeight.Bold, fontSize = 48.sp, color = Color.LightGray)) 
                                    },
                                    modifier = Modifier.width(IntrinsicSize.Min)
                                )
                            }
                        }
                    }

                    // --- Category Selector ---
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

                    // --- Details Card ---
                    item {
                        Column(
                            modifier = Modifier
                                .padding(horizontal = 20.dp)
                                .shadow(4.dp, RoundedCornerShape(20.dp))
                                .background(Color.White, RoundedCornerShape(20.dp))
                                .clip(RoundedCornerShape(20.dp))
                        ) {
                            // Description
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
                                            .offset(x = (-12).dp, y = (-12).dp) // Adjust padding to align
                                    )
                                }
                            }

                            Divider(color = Color.LightGray.copy(alpha = 0.3f), modifier = Modifier.padding(start = 56.dp))

                            // Date
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
                                                // Show TimePicker immediately after Date
                                                TimePickerDialog(
                                                    context,
                                                    { _, hour, minute ->
                                                        cal.set(Calendar.HOUR_OF_DAY, hour)
                                                        cal.set(Calendar.MINUTE, minute)
                                                        date = cal.time
                                                    },
                                                    cal.get(Calendar.HOUR_OF_DAY),
                                                    cal.get(Calendar.MINUTE),
                                                    true // 24h format
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

                    // --- Context Selectors ---
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
                        }
                    }
                }
            }
            
            // --- Save Button ---
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
                            onSave(amt, date, description, category, selectedVehicle, selectedUser, selectedAccount)
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

        // --- Bottom Sheets for Context ---
        
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
                    itemContent = { user -> Text(user.name ?: "Unknown", fontWeight = FontWeight.SemiBold) },
                    onSelect = { 
                        selectedUser = it
                        showUserSheet = false 
                    },
                    onClear = {
                        selectedUser = null
                        showUserSheet = false
                    }
                )
            }
        }
        
        if (showAccountSheet) {
            ModalBottomSheet(onDismissRequest = { showAccountSheet = false }, containerColor = Color.White) {
                SelectionListSheet(
                    title = "Select Account",
                    items = accounts,
                    itemContent = { account -> Text(account.accountType?.replaceFirstChar { it.titlecase() } ?: "Account", fontWeight = FontWeight.SemiBold) },
                    onSelect = { 
                        selectedAccount = it
                        showAccountSheet = false 
                    },
                    onClear = {
                        selectedAccount = null
                        showAccountSheet = false
                    }
                )
            }
        }
    }
}

@Composable
fun CategoryItem(title: String, icon: ImageVector, isSelected: Boolean, onClick: () -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally, 
        modifier = Modifier.clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = null, // No ripple for custom interaction if wanted, but standard is fine
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
    onClear: () -> Unit
) {
    Column(modifier = Modifier.padding(bottom = 50.dp)) {
        Text(
            title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(20.dp)
        )
        
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
