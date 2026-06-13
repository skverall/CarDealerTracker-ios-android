package com.ezcar24.business.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Calculate
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.repository.AccountRepository
import com.ezcar24.business.data.repository.DealDeskBusinessRegionCode
import com.ezcar24.business.data.repository.DealDeskLine
import com.ezcar24.business.data.repository.DealDeskLineCalculationType
import com.ezcar24.business.data.repository.DealDeskRepository
import com.ezcar24.business.data.repository.DealDeskSettings
import com.ezcar24.business.data.repository.DealDeskTemplateCatalog
import com.ezcar24.business.data.repository.DealDeskTemplateCode
import com.ezcar24.business.data.repository.OrganizationMembership
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.util.AppRegion
import com.ezcar24.business.util.UserFacingErrorContext
import com.ezcar24.business.util.UserFacingErrorMapper
import com.ezcar24.business.util.localizedUiString
import com.ezcar24.business.util.rememberRegionSettingsManager
import dagger.hilt.android.lifecycle.HiltViewModel
import java.math.BigDecimal
import java.util.Locale
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class DealDeskSettingsUiState(
    val organizationId: UUID? = null,
    val organizationName: String? = null,
    val role: String? = null,
    val settings: DealDeskSettings = DealDeskTemplateCatalog.defaultSettings(
        businessRegionCode = DealDeskBusinessRegionCode.GENERIC,
        isEnabled = false
    ),
    val taxLines: List<DealDeskLine> = DealDeskTemplateCatalog.defaultTaxLines(DealDeskTemplateCode.GENERIC),
    val feeLines: List<DealDeskLine> = DealDeskTemplateCatalog.defaultFeeLines(DealDeskTemplateCode.GENERIC),
    val taxLineInputs: List<String> = listOf("0"),
    val feeLineInputs: List<String> = listOf("0"),
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val errorMessage: String? = null,
    val infoMessage: String? = null
) {
    val canAccess: Boolean
        get() = role?.trim()?.lowercase(Locale.US) in setOf("owner", "admin")
}

@HiltViewModel
class DealDeskSettingsViewModel @Inject constructor(
    private val accountRepository: AccountRepository,
    private val dealDeskRepository: DealDeskRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(DealDeskSettingsUiState())
    val uiState: StateFlow<DealDeskSettingsUiState> = _uiState.asStateFlow()

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
                    errorMessage = "Only owner or admin can change these settings.",
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
        _uiState.update {
            it.copy(
                settings = it.settings.copy(isEnabled = enabled),
                errorMessage = null,
                infoMessage = null
            )
        }
    }

    fun setBusinessRegion(regionCode: DealDeskBusinessRegionCode, appRegion: AppRegion) {
        val templateCode = regionCode.defaultTemplateCode
        val taxLines = DealDeskTemplateCatalog.defaultTaxLines(templateCode, appRegion)
        val feeLines = DealDeskTemplateCatalog.defaultFeeLines(templateCode, appRegion)

        _uiState.update {
            it.copy(
                settings = it.settings.copy(
                    businessRegionCode = regionCode,
                    defaultTemplateCode = templateCode,
                    taxOverrides = taxLines,
                    feeOverrides = feeLines
                ),
                taxLines = taxLines,
                feeLines = feeLines,
                taxLineInputs = inputsFromLines(taxLines),
                feeLineInputs = inputsFromLines(feeLines),
                errorMessage = null,
                infoMessage = null
            )
        }
    }

    fun setTemplate(templateCode: DealDeskTemplateCode, appRegion: AppRegion) {
        val taxLines = DealDeskTemplateCatalog.defaultTaxLines(templateCode, appRegion)
        val feeLines = DealDeskTemplateCatalog.defaultFeeLines(templateCode, appRegion)

        _uiState.update {
            it.copy(
                settings = it.settings.copy(
                    defaultTemplateCode = templateCode,
                    taxOverrides = taxLines,
                    feeOverrides = feeLines
                ),
                taxLines = taxLines,
                feeLines = feeLines,
                taxLineInputs = inputsFromLines(taxLines),
                feeLineInputs = inputsFromLines(feeLines),
                errorMessage = null,
                infoMessage = null
            )
        }
    }

    fun updateTaxLineInput(index: Int, input: String) {
        updateLineInput(index, input, isTaxLine = true)
    }

    fun updateFeeLineInput(index: Int, input: String) {
        updateLineInput(index, input, isTaxLine = false)
    }

    fun saveSettings() {
        val organization = currentOrganization() ?: run {
            _uiState.update {
                it.copy(
                    errorMessage = "No active business found.",
                    infoMessage = null
                )
            }
            return
        }
        if (!canAccess(organization.role) || _uiState.value.isSaving) return

        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isSaving = true,
                    errorMessage = null,
                    infoMessage = null
                )
            }

            try {
                val current = _uiState.value
                val settingsToSave = current.settings.copy(
                    taxOverrides = current.taxLines,
                    feeOverrides = current.feeLines
                )
                val saved = dealDeskRepository.saveSettings(
                    organizationId = organization.organizationId,
                    settings = settingsToSave
                )
                val taxLines = saved.seededTaxLines
                val feeLines = saved.seededFeeLines
                _uiState.update {
                    it.copy(
                        settings = saved,
                        taxLines = taxLines,
                        feeLines = feeLines,
                        taxLineInputs = inputsFromLines(taxLines),
                        feeLineInputs = inputsFromLines(feeLines),
                        isSaving = false,
                        errorMessage = null,
                        infoMessage = "Deal Desk settings saved."
                    )
                }
            } catch (error: Exception) {
                _uiState.update {
                    it.copy(
                        isSaving = false,
                        errorMessage = UserFacingErrorMapper.map(
                            error,
                            UserFacingErrorContext.SAVE_DEAL_DESK_SETTINGS
                        ),
                        infoMessage = null
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

    private suspend fun handleOrganizationChanged(organization: OrganizationMembership?) {
        if (organization == null) {
            _uiState.update {
                DealDeskSettingsUiState()
            }
            return
        }

        _uiState.update {
            it.copy(
                organizationId = organization.organizationId,
                organizationName = organization.organizationName,
                role = organization.role
            )
        }

        if (!canAccess(organization.role)) {
            _uiState.update {
                it.copy(
                    isLoading = false,
                    errorMessage = null,
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

        try {
            val settings = dealDeskRepository.loadSettings(organization.organizationId)
            val taxLines = settings.seededTaxLines
            val feeLines = settings.seededFeeLines
            _uiState.update {
                it.copy(
                    settings = settings,
                    taxLines = taxLines,
                    feeLines = feeLines,
                    taxLineInputs = inputsFromLines(taxLines),
                    feeLineInputs = inputsFromLines(feeLines),
                    isLoading = false,
                    errorMessage = null
                )
            }
        } catch (error: Exception) {
            _uiState.update {
                it.copy(
                    isLoading = false,
                    errorMessage = UserFacingErrorMapper.map(
                        error,
                        UserFacingErrorContext.LOAD_DEAL_DESK_SETTINGS
                    )
                )
            }
        }
    }

    private fun updateLineInput(index: Int, input: String, isTaxLine: Boolean) {
        val sanitized = sanitizeDecimalInput(input)
        _uiState.update { state ->
            val sourceLines = if (isTaxLine) state.taxLines else state.feeLines
            if (index !in sourceLines.indices) return@update state

            val updatedLines = sourceLines.toMutableList().also { lines ->
                lines[index] = lines[index].copy(value = decimalFromInput(sanitized))
            }
            val sourceInputs = if (isTaxLine) state.taxLineInputs else state.feeLineInputs
            val updatedInputs = sourceInputs.toMutableList().also { inputs ->
                if (index in inputs.indices) {
                    inputs[index] = sanitized
                }
            }

            if (isTaxLine) {
                state.copy(
                    taxLines = updatedLines,
                    taxLineInputs = updatedInputs,
                    errorMessage = null,
                    infoMessage = null
                )
            } else {
                state.copy(
                    feeLines = updatedLines,
                    feeLineInputs = updatedInputs,
                    errorMessage = null,
                    infoMessage = null
                )
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

    private fun inputsFromLines(lines: List<DealDeskLine>): List<String> {
        return lines.map { formatDecimalInput(it.value) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DealDeskSettingsScreen(
    onBack: () -> Unit,
    viewModel: DealDeskSettingsViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val setupGuidance = remember(uiState.settings.defaultTemplateCode, uiState.taxLines, uiState.feeLines) {
        DealDeskTemplateCatalog.setupGuidanceMessage(
            templateCode = uiState.settings.defaultTemplateCode,
            taxLines = uiState.taxLines,
            feeLines = uiState.feeLines
        )
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(
                            text = localizedUiString("Deal Desk"),
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold
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
                            contentDescription = localizedUiString("Back")
                        )
                    }
                },
                actions = {
                    IconButton(
                        onClick = viewModel::refresh,
                        enabled = !uiState.isLoading && !uiState.isSaving && uiState.canAccess
                    ) {
                        if (uiState.isLoading) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                strokeWidth = 2.dp
                            )
                        } else {
                            Icon(
                                imageVector = Icons.Default.Refresh,
                                contentDescription = localizedUiString("Refresh")
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background
                )
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            uiState.errorMessage?.let { message ->
                item {
                    DealDeskStatusCard(
                        text = localizedUiString(message),
                        color = Color(0xFFC95A52),
                        onDismiss = viewModel::clearMessages
                    )
                }
            }

            uiState.infoMessage?.let { message ->
                item {
                    DealDeskStatusCard(
                        text = localizedUiString(message),
                        color = EzcarGreen,
                        onDismiss = viewModel::clearMessages
                    )
                }
            }

            if (!uiState.canAccess) {
                item {
                    DealDeskCard {
                        Text(
                            text = localizedUiString("Deal Desk settings are available to owners and admins only."),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            } else {
                item {
                    DealDeskHeaderCard(
                        settings = uiState.settings,
                        isBusy = uiState.isLoading || uiState.isSaving,
                        onEnabledChange = viewModel::setEnabled
                    )
                }

                item {
                    DealDeskCard {
                        Text(
                            text = localizedUiString("Default template"),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = EzcarNavy
                        )
                        Spacer(modifier = Modifier.height(14.dp))
                        DealDeskDropdownField(
                            label = "Business Region",
                            value = uiState.settings.businessRegionCode.displayName,
                            options = DealDeskBusinessRegionCode.entries,
                            optionLabel = { it.displayName },
                            enabled = !uiState.isLoading && !uiState.isSaving,
                            onSelect = { viewModel.setBusinessRegion(it, regionState.selectedRegion) }
                        )
                        Spacer(modifier = Modifier.height(10.dp))
                        DealDeskDropdownField(
                            label = "Template",
                            value = uiState.settings.defaultTemplateCode.displayName,
                            options = DealDeskTemplateCode.entries,
                            optionLabel = { it.displayName },
                            enabled = !uiState.isLoading && !uiState.isSaving,
                            onSelect = { viewModel.setTemplate(it, regionState.selectedRegion) }
                        )
                        setupGuidance?.let {
                            Spacer(modifier = Modifier.height(12.dp))
                            Text(
                                text = localizedUiString(it),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }

                if (uiState.taxLines.isNotEmpty()) {
                    item {
                        DealDeskLineSection(
                            title = "Default taxes",
                            currencySymbol = regionState.selectedRegion.currencySymbol,
                            lines = uiState.taxLines,
                            inputs = uiState.taxLineInputs,
                            enabled = !uiState.isLoading && !uiState.isSaving,
                            onInputChange = viewModel::updateTaxLineInput
                        )
                    }
                }

                if (uiState.feeLines.isNotEmpty()) {
                    item {
                        DealDeskLineSection(
                            title = "Default fees",
                            currencySymbol = regionState.selectedRegion.currencySymbol,
                            lines = uiState.feeLines,
                            inputs = uiState.feeLineInputs,
                            enabled = !uiState.isLoading && !uiState.isSaving,
                            onInputChange = viewModel::updateFeeLineInput
                        )
                    }
                }

                item {
                    Button(
                        onClick = viewModel::saveSettings,
                        enabled = !uiState.isLoading && !uiState.isSaving,
                        modifier = Modifier.fillMaxWidth(),
                        contentPadding = PaddingValues(horizontal = 18.dp, vertical = 16.dp),
                        shape = RoundedCornerShape(18.dp)
                    ) {
                        if (uiState.isSaving) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                strokeWidth = 2.dp,
                                color = MaterialTheme.colorScheme.onPrimary
                            )
                            Spacer(modifier = Modifier.width(10.dp))
                            Text(localizedUiString("Saving"))
                        } else {
                            Text(localizedUiString("Save settings"))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DealDeskHeaderCard(
    settings: DealDeskSettings,
    isBusy: Boolean,
    onEnabledChange: (Boolean) -> Unit
) {
    DealDeskCard {
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
                    imageVector = Icons.Default.Calculate,
                    contentDescription = null,
                    tint = EzcarBlueBright
                )
            }

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = localizedUiString("Deal Desk"),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = EzcarNavy
                )
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = localizedUiString("Build taxable sale totals from the same template system used on iOS."),
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
                    text = localizedUiString("Enable Deal Desk"),
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Medium
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = localizedUiString("Existing dealers stay off until someone turns this on. Old sales stay untouched."),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Switch(
                checked = settings.isEnabled,
                onCheckedChange = onEnabledChange,
                enabled = !isBusy,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = Color.White,
                    checkedTrackColor = EzcarGreen
                )
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
private fun DealDeskLineSection(
    title: String,
    currencySymbol: String,
    lines: List<DealDeskLine>,
    inputs: List<String>,
    enabled: Boolean,
    onInputChange: (Int, String) -> Unit
) {
    DealDeskCard {
        Text(
            text = localizedUiString(title),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = EzcarNavy
        )
        Spacer(modifier = Modifier.height(10.dp))
        lines.forEachIndexed { index, line ->
            if (index > 0) {
                HorizontalDivider(modifier = Modifier.padding(vertical = 10.dp))
            }
            DealDeskEditableLineRow(
                currencySymbol = currencySymbol,
                line = line,
                value = inputs.getOrElse(index) { formatDecimalInput(line.value) },
                enabled = enabled,
                onValueChange = { onInputChange(index, it) }
            )
        }
    }
}

@Composable
private fun DealDeskEditableLineRow(
    currencySymbol: String,
    line: DealDeskLine,
    value: String,
    enabled: Boolean,
    onValueChange: (String) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = localizedUiString(line.title),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium
            )
            Spacer(modifier = Modifier.height(3.dp))
            Text(
                text = localizedUiString(line.calculationType.labelSource),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        if (line.calculationType == DealDeskLineCalculationType.FIXED_AMOUNT) {
            Text(
                text = currencySymbol,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            enabled = enabled,
            singleLine = true,
            textStyle = TextStyle(textAlign = TextAlign.End),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            modifier = Modifier.width(104.dp)
        )

        if (line.calculationType == DealDeskLineCalculationType.PERCENT_OF_SALE_PRICE) {
            Text(
                text = "%",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun <T> DealDeskDropdownField(
    label: String,
    value: String,
    options: List<T>,
    optionLabel: (T) -> String,
    enabled: Boolean,
    onSelect: (T) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Column {
        Text(
            text = localizedUiString(label),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 4.dp, bottom = 6.dp)
        )
        Box {
            Surface(
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.48f),
                shape = RoundedCornerShape(16.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(enabled = enabled) { expanded = true }
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = localizedUiString(value),
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier.weight(1f)
                    )
                    Icon(
                        imageVector = Icons.Default.KeyboardArrowDown,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            DropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false }
            ) {
                options.forEach { option ->
                    DropdownMenuItem(
                        text = { Text(localizedUiString(optionLabel(option))) },
                        onClick = {
                            expanded = false
                            onSelect(option)
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun DealDeskStatusCard(
    text: String,
    color: Color,
    onDismiss: () -> Unit
) {
    Surface(
        color = color.copy(alpha = 0.12f),
        shape = RoundedCornerShape(18.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.CheckCircle,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.width(10.dp))
            Text(
                text = text,
                style = MaterialTheme.typography.bodyMedium,
                color = color,
                modifier = Modifier.weight(1f)
            )
            TextButton(onClick = onDismiss) {
                Text(
                    text = localizedUiString("Dismiss"),
                    style = MaterialTheme.typography.labelMedium,
                    color = color
                )
            }
        }
    }
}

@Composable
private fun DealDeskCard(
    content: @Composable ColumnScope.() -> Unit
) {
    Surface(
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(22.dp),
        shadowElevation = 8.dp,
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 18.dp, vertical = 18.dp),
            content = content
        )
    }
}

private fun sanitizeDecimalInput(value: String): String {
    val normalized = value.replace(',', '.')
    val result = StringBuilder()
    var hasDecimalSeparator = false

    normalized.forEach { character ->
        when {
            character.isDigit() -> result.append(character)
            character == '.' && !hasDecimalSeparator -> {
                result.append(character)
                hasDecimalSeparator = true
            }
        }
    }

    return result.toString()
}

private fun decimalFromInput(value: String): BigDecimal {
    return runCatching {
        BigDecimal(value.takeIf { it.isNotBlank() && it != "." } ?: "0")
    }.getOrDefault(BigDecimal.ZERO)
}

private fun formatDecimalInput(value: BigDecimal): String {
    return value.stripTrailingZeros().toPlainString()
}
