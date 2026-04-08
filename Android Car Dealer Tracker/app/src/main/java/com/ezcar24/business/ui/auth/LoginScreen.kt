package com.ezcar24.business.ui.auth

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.ui.theme.EzcarDanger
import com.ezcar24.business.ui.theme.EzcarSuccess

@Composable
fun LoginScreen(
    onLoginSuccess: () -> Unit,
    onGuestMode: () -> Unit = {},
    viewModel: AuthViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    var passwordVisible by rememberSaveable { mutableStateOf(false) }
    var showingOptionalCodes by rememberSaveable { mutableStateOf(uiState.mode == AuthMode.SIGN_UP && uiState.hasOptionalCodes) }

    LaunchedEffect(uiState.isSuccess, uiState.isGuestMode) {
        if (uiState.isSuccess) {
            if (uiState.isGuestMode) {
                onGuestMode()
            } else {
                onLoginSuccess()
            }
        }
    }

    LaunchedEffect(uiState.mode, uiState.referralCode, uiState.teamInviteCode) {
        if (uiState.mode != AuthMode.SIGN_UP) {
            showingOptionalCodes = false
        } else if (uiState.hasOptionalCodes) {
            showingOptionalCodes = true
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        MaterialTheme.colorScheme.background,
                        MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
                        MaterialTheme.colorScheme.background
                    )
                )
            )
    ) {
        AuthBackground()

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding()
                .padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(32.dp))

            Surface(
                modifier = Modifier.size(80.dp),
                shape = CircleShape,
                color = Color.White.copy(alpha = 0.78f),
                shadowElevation = 14.dp
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = Icons.Default.DirectionsCar,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(42.dp)
                    )
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            Text(
                text = "Car Dealer Tracker",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onBackground
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = if (uiState.mode == AuthMode.SIGN_IN) "Welcome Back" else "Create your account",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(modifier = Modifier.height(32.dp))

            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .widthIn(max = 420.dp),
                shape = RoundedCornerShape(32.dp),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f)
                ),
                elevation = CardDefaults.cardElevation(defaultElevation = 18.dp)
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .border(
                            width = 1.dp,
                            color = Color.White.copy(alpha = 0.62f),
                            shape = RoundedCornerShape(32.dp)
                        )
                        .padding(28.dp),
                    verticalArrangement = Arrangement.spacedBy(24.dp)
                ) {
                    uiState.pendingInviteMessage?.let { message ->
                        AuthStatusChip(title = message)
                    }

                    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        AuthTextField(
                            value = uiState.email,
                            onValueChange = viewModel::onEmailChange,
                            placeholder = "Email address",
                            leadingIcon = Icons.Default.Email,
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.Email,
                                imeAction = ImeAction.Next
                            )
                        )

                        if (uiState.mode == AuthMode.SIGN_UP) {
                            AuthTextField(
                                value = uiState.phone,
                                onValueChange = viewModel::onPhoneChange,
                                placeholder = "Phone number",
                                leadingIcon = Icons.Default.Phone,
                                keyboardOptions = KeyboardOptions(
                                    keyboardType = KeyboardType.Phone,
                                    imeAction = ImeAction.Next
                                )
                            )
                        }

                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            AuthTextField(
                                value = uiState.password,
                                onValueChange = viewModel::onPasswordChange,
                                placeholder = "Password",
                                leadingIcon = Icons.Default.Lock,
                                keyboardOptions = KeyboardOptions(
                                    keyboardType = KeyboardType.Password,
                                    imeAction = if (uiState.mode == AuthMode.SIGN_UP) ImeAction.Next else ImeAction.Done
                                ),
                                visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
                                trailingContent = {
                                    IconButton(onClick = { passwordVisible = !passwordVisible }) {
                                        Icon(
                                            imageVector = if (passwordVisible) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                                            contentDescription = if (passwordVisible) "Hide password" else "Show password",
                                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                }
                            )

                            if (uiState.mode == AuthMode.SIGN_IN) {
                                TextButton(
                                    onClick = viewModel::requestPasswordReset,
                                    enabled = !uiState.isLoading,
                                    modifier = Modifier.wrapContentWidth(Alignment.End).align(Alignment.End),
                                    contentPadding = ButtonDefaults.TextButtonContentPadding
                                ) {
                                    Text(
                                        text = "Forgot password?",
                                        style = MaterialTheme.typography.bodySmall,
                                        fontWeight = FontWeight.SemiBold,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                }
                            }
                        }
                    }

                    if (uiState.mode == AuthMode.SIGN_UP) {
                        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            TextButton(
                                onClick = { showingOptionalCodes = !showingOptionalCodes },
                                contentPadding = ButtonDefaults.TextButtonContentPadding
                            ) {
                                Icon(
                                    imageVector = if (showingOptionalCodes) Icons.Default.ExpandMore else Icons.Default.ChevronRight,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.size(18.dp)
                                )
                                Text(
                                    text = "Have an invite code?",
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.Medium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }

                            AnimatedVisibility(
                                visible = showingOptionalCodes,
                                enter = fadeIn() + slideInVertically(initialOffsetY = { -it / 3 }),
                                exit = fadeOut() + slideOutVertically(targetOffsetY = { -it / 3 })
                            ) {
                                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                    AuthTextField(
                                        value = uiState.referralCode,
                                        onValueChange = viewModel::onReferralCodeChange,
                                        placeholder = "Referral code",
                                        leadingIcon = Icons.Default.CardGiftcard,
                                        keyboardOptions = KeyboardOptions(
                                            keyboardType = KeyboardType.Ascii,
                                            capitalization = KeyboardCapitalization.Characters,
                                            imeAction = ImeAction.Next
                                        )
                                    )

                                    AuthTextField(
                                        value = uiState.teamInviteCode,
                                        onValueChange = viewModel::onTeamInviteCodeChange,
                                        placeholder = "Team access code",
                                        leadingIcon = Icons.Default.People,
                                        keyboardOptions = KeyboardOptions(
                                            keyboardType = KeyboardType.Ascii,
                                            capitalization = KeyboardCapitalization.Characters,
                                            imeAction = ImeAction.Done
                                        )
                                    )
                                }
                            }
                        }
                    }

                    uiState.error?.let { error ->
                        AuthMessageBanner(
                            message = error,
                            backgroundColor = EzcarDanger.copy(alpha = 0.1f),
                            contentColor = EzcarDanger
                        )
                    }

                    uiState.message?.let { message ->
                        AuthMessageBanner(
                            message = message,
                            backgroundColor = EzcarSuccess.copy(alpha = 0.12f),
                            contentColor = EzcarSuccess
                        )
                    }

                    PrimaryAuthButton(
                        title = if (uiState.mode == AuthMode.SIGN_IN) "Sign In" else "Create Account",
                        isLoading = uiState.isLoading,
                        enabled = !uiState.isLoading && uiState.isFormValid,
                        onClick = viewModel::authenticate
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = if (uiState.mode == AuthMode.SIGN_IN) {
                                "Don't have an account?"
                            } else {
                                "Already have an account?"
                            },
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )

                        TextButton(
                            onClick = {
                                viewModel.onModeChange(
                                    if (uiState.mode == AuthMode.SIGN_IN) AuthMode.SIGN_UP else AuthMode.SIGN_IN
                                )
                            },
                            contentPadding = ButtonDefaults.TextButtonContentPadding
                        ) {
                            Text(
                                text = if (uiState.mode == AuthMode.SIGN_IN) "Sign Up" else "Sign In",
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onBackground
                            )
                        }
                    }

                    TextButton(
                        onClick = viewModel::startGuestMode,
                        enabled = !uiState.isLoading,
                        modifier = Modifier.align(Alignment.CenterHorizontally),
                        contentPadding = ButtonDefaults.TextButtonContentPadding
                    ) {
                        Text(
                            text = "Continue as Guest",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(40.dp))
        }
    }
}

@Composable
private fun AuthBackground() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        MaterialTheme.colorScheme.background,
                        Color.White.copy(alpha = 0.65f)
                    )
                )
            )
    ) {
        Box(
            modifier = Modifier
                .offset(x = (-120).dp, y = (-180).dp)
                .size(320.dp)
                .shadow(0.dp, CircleShape)
                .background(
                    color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
                    shape = CircleShape
                )
        )
        Box(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .offset(x = 120.dp, y = 120.dp)
                .size(400.dp)
                .background(
                    color = MaterialTheme.colorScheme.secondary.copy(alpha = 0.08f),
                    shape = CircleShape
                )
        )
    }
}

@Composable
private fun AuthTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    leadingIcon: ImageVector,
    keyboardOptions: KeyboardOptions,
    modifier: Modifier = Modifier,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    trailingContent: @Composable (() -> Unit)? = null
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = Color.White.copy(alpha = 0.62f),
        tonalElevation = 0.dp,
        shadowElevation = 0.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .border(
                    width = 0.5.dp,
                    color = Color.White.copy(alpha = 0.48f),
                    shape = RoundedCornerShape(16.dp)
                )
                .padding(horizontal = 16.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = leadingIcon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(20.dp)
            )

            Spacer(modifier = Modifier.size(12.dp))

            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                modifier = Modifier.weight(1f),
                singleLine = true,
                keyboardOptions = keyboardOptions,
                visualTransformation = visualTransformation,
                textStyle = MaterialTheme.typography.bodyLarge.copy(
                    color = MaterialTheme.colorScheme.onSurface
                ),
                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                decorationBox = { innerTextField ->
                    Box(modifier = Modifier.fillMaxWidth()) {
                        if (value.isEmpty()) {
                            Text(
                                text = placeholder,
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        innerTextField()
                    }
                }
            )

            if (trailingContent != null) {
                Spacer(modifier = Modifier.size(8.dp))
                trailingContent()
            }
        }
    }
}

@Composable
private fun AuthStatusChip(title: String) {
    Surface(
        shape = RoundedCornerShape(50),
        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.1f)
    ) {
        Text(
            text = title,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.primary
        )
    }
}

@Composable
private fun AuthMessageBanner(
    message: String,
    backgroundColor: Color,
    contentColor: Color
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = backgroundColor
    ) {
        Text(
            text = message,
            modifier = Modifier.padding(14.dp),
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium,
            color = contentColor
        )
    }
}

@Composable
private fun PrimaryAuthButton(
    title: String,
    isLoading: Boolean,
    enabled: Boolean,
    onClick: () -> Unit
) {
    val gradient = if (enabled) {
        Brush.horizontalGradient(
            colors = listOf(
                MaterialTheme.colorScheme.primary,
                MaterialTheme.colorScheme.secondary
            )
        )
    } else {
        Brush.horizontalGradient(
            colors = listOf(
                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.24f),
                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.24f)
            )
        )
    }

    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp)
            .shadow(
                elevation = if (enabled) 14.dp else 0.dp,
                shape = RoundedCornerShape(16.dp),
                clip = false
            ),
        shape = RoundedCornerShape(16.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = Color.Transparent,
            disabledContainerColor = Color.Transparent,
            contentColor = Color.White,
            disabledContentColor = MaterialTheme.colorScheme.onSurfaceVariant
        ),
        contentPadding = ButtonDefaults.ContentPadding
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(gradient, RoundedCornerShape(16.dp)),
            contentAlignment = Alignment.Center
        ) {
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(22.dp),
                    strokeWidth = 2.dp,
                    color = Color.White
                )
            } else {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}
