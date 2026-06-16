package com.ezcar24.business.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.repository.AppFeedbackRequest
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarDanger
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarPurple
import com.ezcar24.business.util.localizedUiString
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeedbackBoardScreen(
    onBack: () -> Unit,
    onRequireSignIn: () -> Unit,
    viewModel: FeedbackBoardViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    var showComposer by remember { mutableStateOf(false) }
    var requestPendingDelete by remember { mutableStateOf<AppFeedbackRequest?>(null) }
    val signInRequired = uiState.errorMessage?.contains("sign in", ignoreCase = true) == true &&
        uiState.requests.isEmpty()

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = localizedUiString("Ideas & Voting"),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold
                    )
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
                    IconButton(onClick = viewModel::load, enabled = !uiState.isLoading) {
                        Icon(
                            imageVector = Icons.Default.Refresh,
                            contentDescription = localizedUiString("Refresh")
                        )
                    }
                    IconButton(onClick = { showComposer = true }, enabled = !signInRequired) {
                        Icon(
                            imageVector = Icons.Default.Add,
                            contentDescription = localizedUiString("Add idea")
                        )
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
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            item {
                FeedbackIntroCard(onCreate = { showComposer = true })
            }

            if (signInRequired) {
                item {
                    FeedbackStateCard(
                        icon = Icons.Default.Lightbulb,
                        title = localizedUiString("Sign in to share ideas"),
                        message = localizedUiString("Every registered dealer can suggest improvements and vote, even without Pro."),
                        actionTitle = localizedUiString("Sign In"),
                        color = EzcarBlueBright,
                        onAction = onRequireSignIn
                    )
                }
            } else if (uiState.errorMessage != null) {
                item {
                    FeedbackStateCard(
                        icon = Icons.Default.Error,
                        title = localizedUiString("Could not load ideas"),
                        message = uiState.errorMessage ?: "",
                        actionTitle = localizedUiString("Try Again"),
                        color = EzcarDanger,
                        onAction = viewModel::load
                    )
                }
            }

            if (uiState.isLoading && uiState.requests.isEmpty()) {
                item {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 32.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator()
                    }
                }
            } else if (uiState.requests.isEmpty() && !signInRequired && uiState.errorMessage == null) {
                item {
                    FeedbackStateCard(
                        icon = Icons.Default.Lightbulb,
                        title = localizedUiString("No ideas yet"),
                        message = localizedUiString("Be the first to suggest what would make the app better for your dealership."),
                        actionTitle = localizedUiString("Add Idea"),
                        color = EzcarOrange,
                        onAction = { showComposer = true }
                    )
                }
            } else {
                items(uiState.requests, key = { it.id }) { request ->
                    FeedbackRequestCard(
                        request = request,
                        isTogglingVote = uiState.togglingVotes.contains(request.id),
                        isDeleting = uiState.deletingRequests.contains(request.id),
                        isUpdatingStatus = uiState.updatingStatuses.contains(request.id),
                        onVote = { viewModel.toggleVote(request.id) },
                        onDelete = { requestPendingDelete = request },
                        onMarkDone = { viewModel.markDone(request.id) }
                    )
                }
            }
        }
    }

    if (showComposer) {
        FeedbackComposerDialog(
            isSubmitting = uiState.isSubmitting,
            errorMessage = uiState.composerError,
            onDismiss = {
                if (!uiState.isSubmitting) {
                    viewModel.clearComposerError()
                    showComposer = false
                }
            },
            onSubmit = { title, details ->
                viewModel.createRequest(
                    title = title,
                    details = details,
                    language = regionState.selectedLanguage.tag,
                    onSuccess = { showComposer = false }
                )
            }
        )
    }

    requestPendingDelete?.let { request ->
        AlertDialog(
            onDismissRequest = { requestPendingDelete = null },
            title = { Text(localizedUiString("Delete this idea?")) },
            text = { Text(localizedUiString("Your idea will be removed from the board. Completed ideas stay visible.")) },
            confirmButton = {
                TextButton(
                    onClick = {
                        requestPendingDelete = null
                        viewModel.deleteRequest(request.id)
                    }
                ) {
                    Text(localizedUiString("Delete"), color = EzcarDanger)
                }
            },
            dismissButton = {
                TextButton(onClick = { requestPendingDelete = null }) {
                    Text(localizedUiString("Cancel"))
                }
            }
        )
    }
}

@Composable
private fun FeedbackIntroCard(onCreate: () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(24.dp),
        shadowElevation = 8.dp
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(52.dp)
                        .background(EzcarBlueBright.copy(alpha = 0.12f), RoundedCornerShape(16.dp)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Default.Lightbulb,
                        contentDescription = null,
                        tint = EzcarBlueBright
                    )
                }
                Spacer(modifier = Modifier.width(14.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = localizedUiString("Help decide what we build next"),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = localizedUiString("Post one clear idea, then vote on requests from other dealers."),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Button(
                onClick = onCreate,
                shape = RoundedCornerShape(16.dp),
                colors = ButtonDefaults.buttonColors(containerColor = EzcarOrange),
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(imageVector = Icons.Default.Add, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text(localizedUiString("Add Idea"))
            }
        }
    }
}

@Composable
private fun FeedbackRequestCard(
    request: AppFeedbackRequest,
    isTogglingVote: Boolean,
    isDeleting: Boolean,
    isUpdatingStatus: Boolean,
    onVote: () -> Unit,
    onDelete: () -> Unit,
    onMarkDone: () -> Unit
) {
    Surface(
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(22.dp),
        shadowElevation = 6.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.Top
        ) {
            Surface(
                color = if (request.hasVoted) EzcarBlueBright.copy(alpha = 0.12f) else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.60f),
                shape = RoundedCornerShape(16.dp),
                modifier = Modifier
                    .size(width = 60.dp, height = 68.dp)
                    .clickable(enabled = !isTogglingVote && request.status != "shipped", onClick = onVote)
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    if (isTogglingVote) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                            color = EzcarBlueBright
                        )
                    } else {
                        Icon(
                            imageVector = if (request.hasVoted) Icons.Default.ThumbUp else Icons.Outlined.ThumbUp,
                            contentDescription = localizedUiString(if (request.hasVoted) "Remove vote" else "Vote"),
                            tint = if (request.hasVoted) EzcarBlueBright else MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(20.dp)
                        )
                    }
                    Spacer(modifier = Modifier.height(5.dp))
                    Text(
                        text = request.voteCount.toString(),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = if (request.hasVoted) EzcarBlueBright else MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Spacer(modifier = Modifier.width(14.dp))
            Column(modifier = Modifier.weight(1f)) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    FeedbackStatusBadge(status = request.status)
                    if (request.isMine) {
                        FeedbackPill(
                            text = localizedUiString("Mine"),
                            color = EzcarBlueBright
                        )
                    }
                }
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = request.title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                if (!request.details.isNullOrBlank()) {
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        text = request.details,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = formatFeedbackDate(request.createdAt),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (request.canDelete || (request.canAdmin && request.status != "shipped") || request.status == "shipped") {
                    Spacer(modifier = Modifier.height(12.dp))
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (request.status == "shipped") {
                            Row(
                                modifier = Modifier.weight(1f),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Default.CheckCircle,
                                    contentDescription = null,
                                    tint = EzcarGreen,
                                    modifier = Modifier.size(17.dp)
                                )
                                Text(
                                    text = localizedUiString("Developer added this"),
                                    style = MaterialTheme.typography.labelMedium,
                                    fontWeight = FontWeight.Bold,
                                    color = EzcarGreen
                                )
                            }
                        } else {
                            Spacer(modifier = Modifier.weight(1f))
                        }

                        if (request.canAdmin && request.status != "shipped") {
                            TextButton(
                                onClick = onMarkDone,
                                enabled = !isUpdatingStatus
                            ) {
                                if (isUpdatingStatus) {
                                    CircularProgressIndicator(
                                        modifier = Modifier.size(14.dp),
                                        strokeWidth = 2.dp,
                                        color = EzcarGreen
                                    )
                                    Spacer(modifier = Modifier.width(6.dp))
                                } else {
                                    Icon(
                                        imageVector = Icons.Default.CheckCircle,
                                        contentDescription = null,
                                        tint = EzcarGreen,
                                        modifier = Modifier.size(17.dp)
                                    )
                                    Spacer(modifier = Modifier.width(5.dp))
                                }
                                Text(localizedUiString("Mark done"), color = EzcarGreen)
                            }
                        }

                        if (request.canDelete) {
                            TextButton(
                                onClick = onDelete,
                                enabled = !isDeleting
                            ) {
                                if (isDeleting) {
                                    CircularProgressIndicator(
                                        modifier = Modifier.size(14.dp),
                                        strokeWidth = 2.dp,
                                        color = EzcarDanger
                                    )
                                    Spacer(modifier = Modifier.width(6.dp))
                                } else {
                                    Icon(
                                        imageVector = Icons.Default.Delete,
                                        contentDescription = null,
                                        tint = EzcarDanger,
                                        modifier = Modifier.size(17.dp)
                                    )
                                    Spacer(modifier = Modifier.width(5.dp))
                                }
                                Text(localizedUiString("Delete"), color = EzcarDanger)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun FeedbackStatusBadge(status: String) {
    val title = when (status) {
        "planned" -> localizedUiString("Planned")
        "in_progress" -> localizedUiString("In Progress")
        "shipped" -> localizedUiString("Done")
        "closed" -> localizedUiString("Closed")
        else -> localizedUiString("Open")
    }
    val color = when (status) {
        "planned" -> EzcarPurple
        "in_progress" -> Color(0xFFFFB300)
        "shipped" -> EzcarGreen
        "closed" -> MaterialTheme.colorScheme.onSurfaceVariant
        else -> EzcarBlueBright
    }
    FeedbackPill(text = title, color = color)
}

@Composable
private fun FeedbackPill(text: String, color: Color) {
    Surface(
        color = color.copy(alpha = 0.12f),
        shape = CircleShape
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            color = color,
            modifier = Modifier.padding(horizontal = 9.dp, vertical = 5.dp)
        )
    }
}

@Composable
private fun FeedbackStateCard(
    icon: ImageVector,
    title: String,
    message: String,
    actionTitle: String,
    color: Color,
    onAction: () -> Unit
) {
    Surface(
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(22.dp),
        shadowElevation = 6.dp
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(22.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(36.dp)
            )
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
            TextButton(onClick = onAction) {
                Text(actionTitle)
                Spacer(modifier = Modifier.width(6.dp))
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                    contentDescription = null,
                    modifier = Modifier.size(17.dp)
                )
            }
        }
    }
}

@Composable
private fun FeedbackComposerDialog(
    isSubmitting: Boolean,
    errorMessage: String?,
    onDismiss: () -> Unit,
    onSubmit: (String, String?) -> Unit
) {
    var title by remember { mutableStateOf("") }
    var details by remember { mutableStateOf("") }
    val trimmedTitle = title.trim()
    val trimmedDetails = details.trim().ifBlank { null }
    val titleIsValid = trimmedTitle.length in 4..120
    val detailsIsValid = details.length <= 1200
    val canSubmit = titleIsValid && detailsIsValid && !isSubmitting

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedUiString("New Idea")) },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                OutlinedTextField(
                    value = title,
                    onValueChange = { title = it },
                    enabled = !isSubmitting,
                    label = { Text(localizedUiString("Short title")) },
                    placeholder = { Text(localizedUiString("Example: Add home screen widgets")) },
                    singleLine = true,
                    supportingText = {
                        Text(localizedUiString("4 to 120 characters"))
                    },
                    isError = title.isNotEmpty() && !titleIsValid,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = details,
                    onValueChange = { details = it },
                    enabled = !isSubmitting,
                    label = { Text(localizedUiString("Details")) },
                    placeholder = { Text(localizedUiString("Explain why this would help your dealership.")) },
                    minLines = 5,
                    supportingText = {
                        Text("${details.length}/1200")
                    },
                    isError = !detailsIsValid,
                    modifier = Modifier.fillMaxWidth()
                )
                if (!errorMessage.isNullOrBlank()) {
                    Text(
                        text = errorMessage,
                        style = MaterialTheme.typography.bodySmall,
                        color = EzcarDanger
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = { onSubmit(trimmedTitle, trimmedDetails) },
                enabled = canSubmit
            ) {
                if (isSubmitting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = Color.White
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                }
                Text(localizedUiString("Submit"))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isSubmitting) {
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = null,
                    modifier = Modifier.size(17.dp)
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(localizedUiString("Cancel"))
            }
        }
    )
}

private fun formatFeedbackDate(date: Date): String {
    return SimpleDateFormat("MMM d, yyyy", Locale.getDefault()).format(date)
}
