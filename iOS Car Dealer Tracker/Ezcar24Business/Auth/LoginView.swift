import SwiftUI
import Supabase

struct LoginView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSessionState: AppSessionState
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @Binding var isGuest: Bool
    @State private var showingPaywall = false
    @State private var showPassword = false
    @FocusState private var focusedField: Field?

    init(isGuest: Binding<Bool> = .constant(false)) {
        _isGuest = isGuest
    }

    private enum Field {
        case email
        case password
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        // Header
                        VStack(spacing: 8) {
                            Text("Ezcar24")
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .foregroundColor(.primary)
                            
                            Text("Business")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .tracking(2)
                        }
                        .padding(.top, 60)
                        .padding(.bottom, 20)
                        
                        // Auth Container
                        VStack(spacing: 25) {
                            // Mode Selector
                            HStack(spacing: 0) {
                                authModeButton(title: "Sign In", mode: .signIn)
                                authModeButton(title: "Sign Up", mode: .signUp)
                            }
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .padding(4)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                            
                            // Inputs
                            VStack(spacing: 16) {
                                // Email Input
                                HStack {
                                    Image(systemName: "envelope.fill")
                                        .foregroundColor(.secondary)
                                        .frame(width: 20)
                                    
                                    TextField("Email Address", text: $appSessionState.email)
                                        .keyboardType(.emailAddress)
                                        .textContentType(.username)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .focused($focusedField, equals: .email)
                                }
                                .padding()
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 1)
                                
                                // Password Input
                                VStack(alignment: .trailing, spacing: 8) {
                                    HStack {
                                        Image(systemName: "lock.fill")
                                            .foregroundColor(.secondary)
                                            .frame(width: 20)
                                        
                                        if showPassword {
                                            TextField("Password", text: $appSessionState.password)
                                                .keyboardType(.asciiCapable)
                                                .textContentType(appSessionState.mode == .signUp ? .newPassword : .password)
                                                .focused($focusedField, equals: .password)
                                        } else {
                                            SecureField("Password", text: $appSessionState.password)
                                                .keyboardType(.asciiCapable)
                                                .textContentType(appSessionState.mode == .signUp ? .newPassword : .password)
                                                .focused($focusedField, equals: .password)
                                        }
                                        
                                        Button(action: { showPassword.toggle() }) {
                                            Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding()
                                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                                    .cornerRadius(12)
                                    .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 1)
                                    
                                    if appSessionState.mode == .signIn {
                                        Button("Forgot Password?") {
                                            handlePasswordReset()
                                        }
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.accentColor)
                                        .padding(.trailing, 4)
                                    }
                                }
                            }
                            
                            // Error Message
                            if let message = sessionStore.errorMessage {
                                HStack {
                                    Image(systemName: message.contains("sent") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    Text(message)
                                        .font(.caption)
                                        .multilineTextAlignment(.leading)
                                }
                                .foregroundColor(message.contains("sent") ? .green : .red)
                                .padding(.horizontal)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            // Main Action Button
                            Button(action: triggerAuth) {
                                HStack {
                                    if appSessionState.isProcessing || sessionStore.isAuthenticating {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .tint(.white)
                                            .padding(.trailing, 8)
                                    }
                                    
                                    Text(appSessionState.mode == .signIn ? "Sign In" : "Create Account")
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    (appSessionState.isProcessing || sessionStore.isAuthenticating || !appSessionState.isFormValid)
                                    ? Color.gray.opacity(0.5)
                                    : Color.accentColor
                                )
                                .foregroundColor(.white)
                                .cornerRadius(14)
                                .shadow(color: Color.accentColor.opacity(0.3), radius: 5, x: 0, y: 3)
                            }
                            .disabled(appSessionState.isProcessing || sessionStore.isAuthenticating || !appSessionState.isFormValid)
                        }
                        .padding(.horizontal, 24)
                        
                        Spacer()
                            .frame(height: 20)
                        
                        // Guest Mode
                        Button(action: startGuestMode) {
                            HStack {
                                Text("Continue as Guest")
                                    .fontWeight(.medium)
                                Image(systemName: "arrow.right")
                            }
                            .foregroundColor(.secondary)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        }
                    }
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .onChange(of: appSessionState.mode) { _, _ in
                sessionStore.resetError()
            }
        }
    }
    
    private func authModeButton(title: String, mode: AppSessionState.Mode) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                appSessionState.mode = mode
            }
        }) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    appSessionState.mode == mode
                    ? Color(uiColor: .systemBackground)
                    : Color.clear
                )
                .foregroundColor(appSessionState.mode == mode ? .primary : .secondary)
                .cornerRadius(10)
                .shadow(color: appSessionState.mode == mode ? Color.black.opacity(0.1) : Color.clear, radius: 2, x: 0, y: 1)
        }
    }

    private func handlePasswordReset() {
        if appSessionState.email.isEmpty {
            sessionStore.errorMessage = "Please enter your email address to reset password."
        } else {
            Task {
                do {
                    try await sessionStore.resetPassword(email: appSessionState.email)
                    sessionStore.errorMessage = "Password reset email sent! Check your inbox."
                } catch {
                    // Error is already handled in sessionStore but we can ensure it's shown
                }
            }
        }
    }
    
    private func startGuestMode() {
        // Start a completely clean guest session:
        // - Wipe ALL local Core Data entities
        // - Clear offline sync queue so old operations are not replayed
        // - Reset last sync timestamp so future login will do a full clean sync
        PersistenceController.shared.deleteAllData()
        Task {
            await SyncQueueManager.shared.clear()
        }
        UserDefaults.standard.removeObject(forKey: "lastSyncTimestamp")
        ImageStore.shared.clearAll()
        appSessionState.startGuestMode()
        isGuest = true
    }

    private func triggerAuth() {
        // Allow auth even if not pro (check pro status after login)
        Task {
            await appSessionState.authenticate()
        }
    }
}
