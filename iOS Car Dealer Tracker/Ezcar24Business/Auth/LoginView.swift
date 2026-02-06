import SwiftUI
import Supabase

struct LoginView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSessionState: AppSessionState
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
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
    
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorTheme.background
                    .ignoresSafeArea()
                
                if isIPad {
                    ipadSplitLayout
                } else {
                    iphoneLayout
                }
            }
            .navigationBarHidden(true)
            .onReceive(sessionStore.$pendingReferralCode) { code in
                guard appSessionState.mode == .signUp else { return }
                if let code, !code.isEmpty, appSessionState.referralCode.isEmpty {
                    appSessionState.referralCode = code
                }
            }
            .onReceive(sessionStore.$pendingTeamInviteCode) { code in
                guard let code, !code.isEmpty, appSessionState.teamInviteCode.isEmpty else { return }
                appSessionState.teamInviteCode = code
            }
            .onChange(of: appSessionState.mode) { _, newMode in
                guard newMode == .signUp else { return }
                if let code = sessionStore.pendingReferralCode, !code.isEmpty, appSessionState.referralCode.isEmpty {
                    appSessionState.referralCode = code
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .onChange(of: appSessionState.mode) { _, _ in
                sessionStore.resetError()
            }
        }
    }
    
    // MARK: - iPad Layout (Split View)
    
    private var ipadSplitLayout: some View {
        HStack(spacing: 0) {
            // Left Panel: Branding
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [ColorTheme.primary, ColorTheme.accent]), // Assuming ColorTheme has accent, fallback if not
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    LinearGradient(
                        colors: [Color.black.opacity(0.1), Color.black.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Spacer()
                    
                    Image(systemName: "car.side.fill") // Placeholder logo if no asset
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                        .padding(.bottom, 16)
                    
                    Text("Ezcar24")
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Business")
                        .font(.system(size: 32, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .tracking(4)
                    
                    Text("Professional Dealer Management")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 8)
                    
                    Spacer()
                    
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text("Version \(version)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.bottom, 40)
                    }
                }
                .padding(40)
            }
            .frame(maxWidth: .infinity) // Takes remaining space
            
            // Right Panel: Auth Form
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 40) {
                        Spacer()
                            .frame(height: 60)
                        
                        authContent
                            .frame(maxWidth: 450) // Contrained width for readability
                        
                        Spacer()
                            .frame(height: 60)
                    }
                    .padding(.horizontal, 40)
                }
            }
            .frame(width: 550) // Fixed width or relative ratio for form side? Let's use flexible if we want 55/45, but fixed width is often safer for forms.
            // Let's stick to .frame(width: UIScreen.main.bounds.width * 0.45) if valid, or just simple flexible.
            // Better:
            .frame(minWidth: 450, maxWidth: 600)
        }
    }
    
    // MARK: - iPhone Layout
    
    private var iphoneLayout: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 8) {
                    Text("Ezcar24")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundColor(ColorTheme.primaryText)
                    
                    Text("Business")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(ColorTheme.secondaryText)
                        .tracking(2)
                }
                .padding(.top, 60)
                .padding(.bottom, 20)
                
                authContent
            }
            .padding(.bottom, 40)
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }
    
    // MARK: - Shared Auth Content
    
    private var authContent: some View {
        VStack(spacing: 25) {
            // Mode Selector
            HStack(spacing: 0) {
                authModeButton(title: "Sign In", mode: .signIn)
                authModeButton(title: "Sign Up", mode: .signUp)
            }
            .background(ColorTheme.cardBackground)
            .cornerRadius(12)
            .padding(4)
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            
            // InputsContainer
            VStack(spacing: 16) {
                if appSessionState.mode == .signUp {
                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundColor(.secondary)
                            .frame(width: 20)

                        TextField("Phone", text: $appSessionState.phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 1)

                    HStack {
                        Image(systemName: "gift.fill")
                            .foregroundColor(.secondary)
                            .frame(width: 20)

                        TextField("Referral Code (optional)", text: $appSessionState.referralCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled(true)
                            .keyboardType(.asciiCapable)
                            .textContentType(.oneTimeCode)
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 1)
                }

                HStack {
                    Image(systemName: "person.badge.plus.fill")
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    TextField("Team Invite Code (optional)", text: $appSessionState.teamInviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                        .keyboardType(.asciiCapable)
                        .textContentType(.oneTimeCode)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 1)

                Text("Already registered? You can also apply this code later in Account > Join Team by Code.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
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
                VStack(alignment: .trailing, spacing: 12) {
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
                        .foregroundColor(ColorTheme.primary)
                    }
                }
            }
            
            // Error Message
            if let message = sessionStore.errorMessage {
                let successMessage = "auth_reset_email_sent".localizedString
                let isSuccess = message == successMessage
                HStack {
                    Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    Text(message)
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                }
                .foregroundColor(isSuccess ? .green : .red)
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
                    : ColorTheme.primary
                )
                .foregroundColor(.white)
                .cornerRadius(14)
                .shadow(color: ColorTheme.primary.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(appSessionState.isProcessing || sessionStore.isAuthenticating || !appSessionState.isFormValid)
            
            Spacer()
                .frame(height: 10)
            
            // Guest Mode
            Button(action: startGuestMode) {
                HStack {
                    Text("Continue as Guest")
                        .fontWeight(.medium)
                    Image(systemName: "arrow.right")
                }
                .foregroundColor(ColorTheme.secondaryText)
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .background(ColorTheme.cardBackground)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
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
                    ? ColorTheme.background
                    : Color.clear
                )
                .foregroundColor(appSessionState.mode == mode ? ColorTheme.primaryText : ColorTheme.secondaryText)
                .cornerRadius(10)
                .shadow(color: appSessionState.mode == mode ? Color.black.opacity(0.1) : Color.clear, radius: 2, x: 0, y: 1)
        }
    }

    private func handlePasswordReset() {
        if appSessionState.email.isEmpty {
            sessionStore.errorMessage = "auth_reset_email_required".localizedString
        } else {
            Task {
                do {
                    try await sessionStore.resetPassword(email: appSessionState.email)
                    sessionStore.errorMessage = "auth_reset_email_sent".localizedString
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
        cloudSyncManager.updateContext(PersistenceController.shared.viewContext)
        Task {
            await SyncQueueManager.shared.clear()
        }
        CloudSyncManager.clearAllSyncTimestamps()
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
