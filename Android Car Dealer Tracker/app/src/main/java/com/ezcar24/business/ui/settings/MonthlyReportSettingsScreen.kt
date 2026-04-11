package com.ezcar24.business.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.repository.AccountRepository
import com.ezcar24.business.data.repository.MonthlyReportPreferences
import com.ezcar24.business.data.repository.MonthlyReportPreview
import com.ezcar24.business.data.repository.MonthlyReportRecipient
import com.ezcar24.business.data.repository.MonthlyReportRepository
import com.ezcar24.business.data.repository.OrganizationMembership
import com.ezcar24.business.data.repository.ReportMonth
import com.ezcar24.business.ui.theme.EzcarBackgroundLight
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.util.DateUtils
import com.ezcar24.business.util.UserFacingErrorContext
import com.ezcar24.business.util.UserFacingErrorMapper
import dagger.hilt.android.lifecycle.HiltViewModel
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class MonthlyReportSettingsUiState(
    val organizationId: UUID? = null,
    val organizationName: String? = null,
    val role: String? = null,
    val preferences: MonthlyReportPreferences = MonthlyReportPreferences.default(),
    val recipients: List<MonthlyReportRecipient> = emptyList(),
    val preview: MonthlyReportPreview? = null,
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val isLoadingPreview: Boolean = false,
    val isSendingTest: Boolean = false,
    val errorMessage: String? = null,
    val infoMessage: String? = null
) {
    val canAccess: Boolean
        get() = role?.trim()?.lowercase(Locale.US) in setOf("owner", "admin")
}

@HiltViewModel
class MonthlyReportSettingsViewModel @Inject constructor(
    private val accountRepository: AccountRepository,
    private val monthlyReportRepository: MonthlyReportRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(MonthlyReportSettingsUiState())
    val uiState: StateFlow<MonthlyReportSettingsUiState> = _uiState.asStateFlow()

    private val previewMonth = ReportMonth.previousCalendarMonth()

    init {
        viewModelScope.launch {
            accountRepository.activeOrganization.collectLatest { organization ->
                handleOrganizationChanged(organization)
            }
        }
    }

    fun refresh() {
        val organization = currentOrganization() ?: run {
            _uiState.update {
                it.copy(
                    errorMessage = "No active business found.",
                    infoMessage = null
                )
            }
            return
        }

        if (!canAccess(organization.role)) {
            _uiState.update {
                it.copy(
                    errorMessage = "Only owners and admins can manage email reports.",
                    infoMessage = null
                )
            }
            return
        }

        viewModelScope.launch {
            loadOrganizationData(organization, clearMessages = true)
        }
    }

    fun setEnabled(enabled: Boolean) {
        if (_uiState.value.isSaving) return

        _uiState.update {
            it.copy(
                preferences = it.preferences.copy(isEnabled = enabled),
                errorMessage = null,
                infoMessage = null
            )
        }

        save(showConfirmation = false)
    }

    fun loadPreview() {
        val organization = currentOrganization() ?: return
        if (!canAccess(organization.role) || _uiState.value.isLoadingPreview) return

        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isLoadingPreview = true,
                    errorMessage = null,
                    infoMessage = null
                )
            }

            try {
                val preview = monthlyReportRepository.loadPreview(
                    organizationId = organization.organizationId,
                    month = previewMonth
                )
                _uiState.update {
                    it.copy(
                        isLoadingPreview = false,
                        preview = preview
                    )
                }
            } catch (error: Exception) {
                _uiState.update {
                    it.copy(
                        isLoadingPreview = false,
                        errorMessage = UserFacingErrorMapper.map(
                            error,
                            UserFacingErrorContext.LOAD_MONTHLY_REPORT_PREVIEW
                        )
                    )
                }
            }
        }
    }

    fun sendTest() {
        val organization = currentOrganization() ?: return
        if (!canAccess(organization.role) || _uiState.value.isSendingTest) return

        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isSendingTest = true,
                    errorMessage = null,
                    infoMessage = null
                )
            }

            try {
                val message = monthlyReportRepository.sendTestReport(
                    organizationId = organization.organizationId,
                    month = previewMonth
                )
                _uiState.update {
                    it.copy(
                        isSendingTest = false,
                        infoMessage = message
                    )
                }
            } catch (error: Exception) {
                _uiState.update {
                    it.copy(
                        isSendingTest = false,
                        errorMessage = UserFacingErrorMapper.map(
                            error,
                            UserFacingErrorContext.SEND_MONTHLY_REPORT_TEST
                        )
                    )
                }
            }
        }
    }

    fun clearMessages() {
        _uiState.update {
            it.copy(
                errorMessage = null,
                infoMessage = null
            )
        }
    }

    fun previewMonthTitle(): String {
        return previewMonth.displayTitle()
    }

    fun scheduleDescription(): String {
        val preferences = _uiState.value.preferences
        val formatter = SimpleDateFormat("HH:mm", Locale.getDefault()).apply {
            timeZone = TimeZone.getTimeZone(preferences.timezoneIdentifier)
        }
        val baseDate = java.util.Calendar.getInstance().apply {
            clear()
            set(2000, java.util.Calendar.JANUARY, 1, preferences.deliveryHour, preferences.deliveryMinute)
        }.time
        return "${ordinal(preferences.deliveryDay)} day of each month at ${formatter.format(baseDate)}"
    }

    private suspend fun handleOrganizationChanged(organization: OrganizationMembership?) {
        if (organization == null) {
            _uiState.update {
                it.copy(
                    organizationId = null,
                    organizationName = null,
                    role = null,
                    preferences = MonthlyReportPreferences.default(),
                    recipients = emptyList(),
                    preview = null,
                    isLoading = false,
                    errorMessage = null,
                    infoMessage = null
                )
            }
            return
        }

        _uiState.update {
            it.copy(
                organizationId = organization.organizationId,
                organizationName = organization.organizationName,
                role = organization.role,
                preview = null
            )
        }

        if (!canAccess(organization.role)) {
            _uiState.update {
                it.copy(
                    preferences = MonthlyReportPreferences.default(),
                    recipients = emptyList(),
                    isLoading = false,
                    errorMessage = "Only owners and admins can manage email reports.",
                    infoMessage = null
                )
            }
            return
        }

        loadOrganizationData(organization, clearMessages = true)
    }

    private suspend fun loadOrganizationData(
        organization: OrganizationMembership,
        clearMessages: Boolean
    ) {
        _uiState.update {
            it.copy(
                isLoading = true,
                errorMessage = if (clearMessages) null else it.errorMessage,
                infoMessage = if (clearMessages) null else it.infoMessage
            )
        }

        var preferences = MonthlyReportPreferences.default()
        var recipients = emptyList<MonthlyReportRecipient>()
        var errorMessage: String? = null

        try {
            preferences = monthlyReportRepository.loadPreferences(organization.organizationId)
        } catch (error: Exception) {
            errorMessage = UserFacingErrorMapper.map(
                error,
                UserFacingErrorContext.LOAD_MONTHLY_REPORT_SETTINGS
            )
        }

        try {
            recipients = monthlyReportRepository.resolveRecipients(organization.organizationId)
        } catch (error: Exception) {
            if (errorMessage == null) {
                errorMessage = UserFacingErrorMapper.map(
                    error,
                    UserFacingErrorContext.LOAD_MONTHLY_REPORT_SETTINGS
                )
            }
        }

        _uiState.update {
            it.copy(
                preferences = preferences,
                recipients = recipients,
                isLoading = false,
                errorMessage = errorMessage
            )
        }
    }

    private fun save(showConfirmation: Boolean) {
        val organization = currentOrganization() ?: return
        if (!canAccess(organization.role)) return

        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isSaving = true,
                    errorMessage = null,
                    infoMessage = null
                )
            }

            try {
                val stored = monthlyReportRepository.savePreferences(
                    organizationId = organization.organizationId,
                    preferences = _uiState.value.preferences
                )
                _uiState.update {
                    it.copy(
                        preferences = stored,
                        isSaving = false,
                        infoMessage = if (showConfirmation) "Monthly report settings saved." else null
                    )
                }
            } catch (error: Exception) {
                _uiState.update {
                    it.copy(
                        isSaving = false,
                        errorMessage = UserFacingErrorMapper.map(
                            error,
                            UserFacingErrorContext.SAVE_MONTHLY_REPORT_SETTINGS
                        )
                    )
                }
            }
        }
    }

    private fun currentOrganization(): OrganizationMembership? {
        val currentId = _uiState.value.organizationId ?: return null
        return accountRepository.activeOrganization.value
            ?.takeIf { it.organizationId == currentId }
    }

    private fun canAccess(role: String?): Boolean {
        return role?.trim()?.lowercase(Locale.US) in setOf("owner", "admin")
    }

    private fun ordinal(number: Int): String {
        val formatter = NumberFormat.getIntegerInstance(Locale.getDefault())
        return when {
            number % 100 in 11..13 -> "${formatter.format(number)}th"
            number % 10 == 1 -> "${formatter.format(number)}st"
            number % 10 == 2 -> "${formatter.format(number)}nd"
            number % 10 == 3 -> "${formatter.format(number)}rd"
            else -> "${formatter.format(number)}th"
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MonthlyReportSettingsScreen(
    onBack: () -> Unit,
    viewModel: MonthlyReportSettingsViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val previewMonthTitle = remember { viewModel.previewMonthTitle() }

    Scaffold(
        containerColor = EzcarBackgroundLight,
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(
                            text = "Email Reports",
                            fontWeight = FontWeight.Bold,
                            color = EzcarNavy
                        )
                        uiState.organizationName?.let {
                            Text(
                                text = it,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                            tint = EzcarNavy
                        )
                    }
                },
                actions = {
                    IconButton(
                        onClick = viewModel::refresh,
                        enabled = !uiState.isLoading && uiState.canAccess
                    ) {
                        if (uiState.isLoading) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                strokeWidth = 2.dp,
                                color = EzcarNavy
                            )
                        } else {
                            Icon(
                                imageVector = Icons.Default.Email,
                                contentDescription = "Refresh",
                                tint = EzcarNavy
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = EzcarBackgroundLight)
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            uiState.errorMessage?.let { message ->
                item {
                    MonthlyReportStatusCard(
                        text = message,
                        color = Color(0xFFC95A52),
                        onDismiss = viewModel::clearMessages
                    )
                }
            }

            uiState.infoMessage?.let { message ->
                item {
                    MonthlyReportStatusCard(
                        text = message,
                        color = EzcarGreen,
                        onDismiss = viewModel::clearMessages
                    )
                }
            }

            if (!uiState.canAccess) {
                item {
                    MonthlyReportCard {
                        Text(
                            text = "Email reports are available to owners and admins only.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            } else {
                item {
                    MonthlyReportHeaderCard(
                        preferences = uiState.preferences,
                        isEnabled = uiState.preferences.isEnabled,
                        isBusy = uiState.isLoading || uiState.isSaving,
                        onEnabledChange = viewModel::setEnabled
                    )
                }

                item {
                    MonthlyReportCard {
                        Text(
                            text = "Delivery",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = EzcarNavy
                        )
                        Spacer(modifier = Modifier.height(14.dp))
                        MonthlyReportDetailRow("Schedule", viewModel.scheduleDescription())
                        Spacer(modifier = Modifier.height(12.dp))
                        MonthlyReportDetailRow("Timezone", uiState.preferences.timezoneIdentifier)
                        Spacer(modifier = Modifier.height(12.dp))
                        MonthlyReportDetailRow("Preview month", previewMonthTitle)
                    }
                }

                item {
                    MonthlyReportCard {
                        Text(
                            text = "Recipients",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = EzcarNavy
                        )
                        Spacer(modifier = Modifier.height(10.dp))
                        Text(
                            text = "All owner and admin members with a resolved email address.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(modifier = Modifier.height(14.dp))
                        if (uiState.recipients.isEmpty()) {
                            Text(
                                text = "No owner or admin email address is available for delivery.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = EzcarOrange
                            )
                        } else {
                            uiState.recipients.forEachIndexed { index, recipient ->
                                if (index > 0) {
                                    HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))
                                }
                                MonthlyReportRecipientRow(recipient = recipient)
                            }
                        }
                    }
                }

                item {
                    MonthlyReportCard {
                        Text(
                            text = "Report contents",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = EzcarNavy
                        )
                        Spacer(modifier = Modifier.height(14.dp))
                        MonthlyReportDetailRow("Scope", "Finance + inventory + parts")
                        Spacer(modifier = Modifier.height(12.dp))
                        MonthlyReportDetailRow("Format", "Email summary + PDF attachment")
                        Spacer(modifier = Modifier.height(12.dp))
                        MonthlyReportDetailRow(
                            "Profit display",
                            "Realized sales profit, monthly expenses, and net cash movement"
                        )
                    }
                }

                item {
                    MonthlyReportCard {
                        Text(
                            text = "Actions",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = EzcarNavy
                        )
                        Spacer(modifier = Modifier.height(14.dp))
                        MonthlyReportActionButton(
                            icon = Icons.Default.Visibility,
                            title = "Preview previous month",
                            subtitle = "Load the finance snapshot used for delivery",
                            isLoading = uiState.isLoadingPreview,
                            onClick = viewModel::loadPreview
                        )
                        Spacer(modifier = Modifier.height(10.dp))
                        MonthlyReportActionButton(
                            icon = Icons.AutoMirrored.Filled.Send,
                            title = "Send test email",
                            subtitle = "Trigger the backend delivery flow",
                            isLoading = uiState.isSendingTest,
                            onClick = viewModel::sendTest
                        )
                    }
                }

                uiState.preview?.let { preview ->
                    item {
                        MonthlyReportPreviewCard(preview = preview)
                    }
                }
            }
        }
    }
}

@Composable
private fun MonthlyReportHeaderCard(
    preferences: MonthlyReportPreferences,
    isEnabled: Boolean,
    isBusy: Boolean,
    onEnabledChange: (Boolean) -> Unit
) {
    MonthlyReportCard {
        Row(
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .background(EzcarBlueBright.copy(alpha = 0.14f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Email,
                    contentDescription = null,
                    tint = EzcarBlueBright
                )
            }

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Monthly email reports",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = EzcarNavy
                )
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = "Preview and trigger the same finance snapshot that backs monthly email delivery.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Spacer(modifier = Modifier.height(18.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Enable monthly report emails",
                    style = MaterialTheme.typography.bodyLarge,
                    color = EzcarNavy
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Owner and admin recipients only",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (preferences.timezoneIdentifier.isNotBlank()) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = preferences.timezoneIdentifier,
                        style = MaterialTheme.typography.bodySmall,
                        color = EzcarBlueBright
                    )
                }
            }

            Switch(
                checked = isEnabled,
                onCheckedChange = onEnabledChange,
                enabled = !isBusy,
                colors = SwitchDefaults.colors(checkedThumbColor = Color.White)
            )
        }

        if (isBusy) {
            Spacer(modifier = Modifier.height(14.dp))
            CircularProgressIndicator(
                modifier = Modifier.size(22.dp),
                strokeWidth = 2.dp,
                color = EzcarNavy
            )
        }
    }
}

@Composable
private fun MonthlyReportPreviewCard(preview: MonthlyReportPreview) {
    val generatedAtLabel = remember(preview.generatedAt) {
        DateUtils.parseDateAndTime(preview.generatedAt)?.let {
            SimpleDateFormat("MMM d, yyyy • HH:mm", Locale.getDefault()).format(it)
        } ?: preview.generatedAt
    }

    MonthlyReportCard {
        Text(
            text = "Preview snapshot",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = EzcarNavy
        )
        Spacer(modifier = Modifier.height(10.dp))
        Text(
            text = preview.title,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = EzcarNavy
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = preview.periodLabel,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "${preview.organizationName} • ${preview.timezone}",
            style = MaterialTheme.typography.bodySmall,
            color = EzcarBlueBright
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "Generated $generatedAtLabel",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(16.dp))
        MonthlyReportMetricRow(
            leftTitle = "Total revenue",
            leftValue = preview.totalRevenue,
            rightTitle = "Sales profit",
            rightValue = preview.realizedSalesProfit
        )
        Spacer(modifier = Modifier.height(10.dp))
        MonthlyReportMetricRow(
            leftTitle = "Monthly expenses",
            leftValue = preview.monthlyExpenses,
            rightTitle = "Net cash movement",
            rightValue = preview.netCashMovement
        )
    }
}

@Composable
private fun MonthlyReportMetricRow(
    leftTitle: String,
    leftValue: String,
    rightTitle: String,
    rightValue: String
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        MonthlyReportMetricCard(
            title = leftTitle,
            value = leftValue,
            modifier = Modifier.weight(1f)
        )
        MonthlyReportMetricCard(
            title = rightTitle,
            value = rightValue,
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun MonthlyReportMetricCard(
    title: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.36f)
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = value,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = EzcarNavy
            )
        }
    }
}

@Composable
private fun MonthlyReportRecipientRow(recipient: MonthlyReportRecipient) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .background(EzcarBlueBright.copy(alpha = 0.12f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.People,
                contentDescription = null,
                tint = EzcarBlueBright
            )
        }
        Spacer(modifier = Modifier.size(12.dp))
        Column {
            Text(
                text = recipient.email,
                style = MaterialTheme.typography.bodyLarge,
                color = EzcarNavy
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = recipient.role.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString() },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun MonthlyReportActionButton(
    icon: ImageVector,
    title: String,
    subtitle: String,
    isLoading: Boolean,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        enabled = !isLoading,
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 14.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(imageVector = icon, contentDescription = null)
            Spacer(modifier = Modifier.size(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall
                )
            }
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    strokeWidth = 2.dp,
                    color = Color.White
                )
            }
        }
    }
}

@Composable
private fun MonthlyReportDetailRow(title: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top
    ) {
        Box(
            modifier = Modifier
                .size(32.dp)
                .background(EzcarOrange.copy(alpha = 0.12f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = when (title) {
                    "Schedule" -> Icons.Default.Schedule
                    "Scope", "Format", "Profit display" -> Icons.Default.Description
                    else -> Icons.Default.Schedule
                },
                contentDescription = null,
                tint = EzcarOrange
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = value,
                style = MaterialTheme.typography.bodyLarge,
                color = EzcarNavy
            )
        }
    }
}

@Composable
private fun MonthlyReportStatusCard(
    text: String,
    color: Color,
    onDismiss: () -> Unit
) {
    Surface(
        shape = RoundedCornerShape(18.dp),
        color = color.copy(alpha = 0.12f)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = text,
                style = MaterialTheme.typography.bodyMedium,
                color = color,
                modifier = Modifier.weight(1f)
            )
            Spacer(modifier = Modifier.size(12.dp))
            Button(
                onClick = onDismiss,
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp)
            ) {
                Text("Dismiss")
            }
        }
    }
}

@Composable
private fun MonthlyReportCard(
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(24.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.Top,
            content = content
        )
    }
}
