import SwiftUI

struct LoginView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSessionState: AppSessionState
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @Binding var isGuest: Bool
    @State private var showingPaywall = false
    @State private var showPassword = false
    @State private var showingOptionalCodes = false
    @FocusState private var focusedField: Field?

    init(isGuest: Binding<Bool> = .constant(false)) {
        _isGuest = isGuest
    }

    private enum Field {
        case email
        case password
        case phone
        case referral
        case teamInvite
    }

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var trimmedReferralCode: String {
        appSessionState.referralCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTeamInviteCode: String {
        appSessionState.teamInviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasOptionalCodes: Bool {
        !trimmedReferralCode.isEmpty || !trimmedTeamInviteCode.isEmpty
    }

    private var primaryActionTitle: String {
        appSessionState.mode == .signIn ? "Sign In" : "Create Account"
    }

    private var pendingInviteMessage: String? {
        guard !trimmedTeamInviteCode.isEmpty else { return nil }
        if appSessionState.mode == .signIn {
            return "Team access will be applied after you sign in."
        }
        return "This sign-up is ready to join a team automatically."
    }

    var body: some View {
        NavigationStack {
            ZStack {
                authBackground

                ScrollView {
                    VStack(spacing: 32) {
                        Spacer(minLength: isIPad ? 60 : 40)
                        
                        headerView
                        
                        authCard
                            .frame(maxWidth: 420)
                            
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarHidden(true)
            .onReceive(sessionStore.$pendingReferralCode) { code in
                guard appSessionState.mode == .signUp else { return }
                if let code, !code.isEmpty, appSessionState.referralCode.isEmpty {
                    appSessionState.referralCode = code
                    syncOptionalCodeVisibility(forceOpen: true)
                }
            }
            .onReceive(sessionStore.$pendingTeamInviteCode) { code in
                guard let code, !code.isEmpty, appSessionState.teamInviteCode.isEmpty else { return }
                appSessionState.teamInviteCode = code
                syncOptionalCodeVisibility(forceOpen: appSessionState.mode == .signUp)
            }
            .onChange(of: appSessionState.mode) { _, newMode in
                sessionStore.resetError()
                syncOptionalCodeVisibility(forceOpen: newMode == .signUp && hasOptionalCodes)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
    }

    // MARK: - Layout Components

    private var authBackground: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.05, green: 0.06, blue: 0.12),
                        Color.black,
                        Color(red: 0.03, green: 0.04, blue: 0.08)
                    ]
                    : [
                        Color(red: 0.96, green: 0.97, blue: 0.99),
                        Color.white
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(ColorTheme.accent.opacity(colorScheme == .dark ? 0.25 : 0.12))
                .frame(width: 320, height: 320)
                .blur(radius: 100)
                .offset(x: -120, y: -250)

            Circle()
                .fill(ColorTheme.primary.opacity(colorScheme == .dark ? 0.2 : 0.08))
                .frame(width: 400, height: 400)
                .blur(radius: 120)
                .offset(x: 180, y: 300)
        }
        .ignoresSafeArea()
    }

    private var headerView: some View {
        VStack(spacing: 20) {
            Image(systemName: "car.fill")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(ColorTheme.primary)
                .frame(width: 80, height: 80)
                .background(
                    Circle()
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.8))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.6), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 15, x: 0, y: 8)

            VStack(spacing: 8) {
                Text("Car Dealer Tracker")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(ColorTheme.primaryText)

                Text(appSessionState.mode == .signIn ? "Welcome Back" : "Create your account")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(ColorTheme.secondaryText)
            }
        }
        .padding(.bottom, 8)
    }

    private var authCard: some View {
        VStack(spacing: 24) {
            if let pendingInviteMessage {
                statusChip(title: pendingInviteMessage, systemImage: "person.2.badge.plus")
            }

            VStack(spacing: 16) {
                authField(icon: "envelope", placeholder: "Email address", text: $appSessionState.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)

                if appSessionState.mode == .signUp {
                    authField(icon: "phone", placeholder: "Phone number", text: $appSessionState.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($focusedField, equals: .phone)
                }

                VStack(alignment: .trailing, spacing: 12) {
                    passwordField

                    if appSessionState.mode == .signIn {
                        Button("Forgot password?") {
                            handlePasswordReset()
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(ColorTheme.primary)
                        .padding(.trailing, 4)
                    }
                }
            }

            if appSessionState.mode == .signUp {
                optionalCodesSection
            }

            if let message = sessionStore.errorMessage {
                errorBanner(message: message)
            }

            Button(action: triggerAuth) {
                HStack(spacing: 8) {
                    if appSessionState.isProcessing || sessionStore.isAuthenticating {
                        ProgressView().tint(.white)
                    }
                    Text(primaryActionTitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(primaryButtonBackground)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: ColorTheme.primary.opacity(0.35), radius: 12, x: 0, y: 6)
            }
            .disabled(appSessionState.isProcessing || sessionStore.isAuthenticating || !appSessionState.isFormValid)
            
            HStack {
                Text(appSessionState.mode == .signIn ? "Don't have an account?" : "Already have an account?")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ColorTheme.secondaryText)
                
                Button(appSessionState.mode == .signIn ? "Sign Up" : "Sign In") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        appSessionState.mode = appSessionState.mode == .signIn ? .signUp : .signIn
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ColorTheme.primaryText)
            }
            .padding(.top, 4)

            Button("Continue as Guest") {
                startGuestMode()
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(ColorTheme.secondaryText)
            .padding(.top, 4)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.95 : 1.0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.6), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 32, x: 0, y: 16)
    }

    private var optionalCodesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showingOptionalCodes.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showingOptionalCodes ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                    Text("Have an invite code?")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(ColorTheme.secondaryText)
            }
            .buttonStyle(.plain)

            if showingOptionalCodes {
                VStack(spacing: 12) {
                    authField(icon: "gift", placeholder: "Referral code", text: $appSessionState.referralCode)
                        .textInputAutocapitalization(.characters)
                        .textContentType(.oneTimeCode)
                        .focused($focusedField, equals: .referral)

                    authField(icon: "person.badge.plus", placeholder: "Team access code", text: $appSessionState.teamInviteCode)
                        .textInputAutocapitalization(.characters)
                        .textContentType(.oneTimeCode)
                        .focused($focusedField, equals: .teamInvite)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var primaryButtonBackground: some ShapeStyle {
        if appSessionState.isProcessing || sessionStore.isAuthenticating || !appSessionState.isFormValid {
            return AnyShapeStyle(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.45))
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [ColorTheme.primary, ColorTheme.secondary],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    // MARK: - Input Components
    
    private var passwordField: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ColorTheme.secondaryText)
                .frame(width: 20)
            
            Group {
                if showPassword {
                    TextField("Password", text: $appSessionState.password)
                        .keyboardType(.asciiCapable)
                } else {
                    SecureField("Password", text: $appSessionState.password)
                        .keyboardType(.asciiCapable)
                }
            }
            .font(.system(size: 16, weight: .regular))
            .textContentType(appSessionState.mode == .signUp ? .newPassword : .password)
            .focused($focusedField, equals: .password)
            
            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ColorTheme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.5), lineWidth: 0.5)
        )
    }

    private func authField(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ColorTheme.secondaryText)
                .frame(width: 20)
            
            TextField(placeholder, text: text)
                .font(.system(size: 16, weight: .regular))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.5), lineWidth: 0.5)
        )
    }

    private func statusChip(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.system(.caption, design: .rounded, weight: .semibold))
        .foregroundStyle(ColorTheme.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(ColorTheme.primary.opacity(colorScheme == .dark ? 0.18 : 0.10))
        )
    }

    private func errorBanner(message: String) -> some View {
        let successMessage = "auth_reset_email_sent".localizedString
        let isSuccess = message == successMessage

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .bold))
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(isSuccess ? ColorTheme.success : ColorTheme.danger)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill((isSuccess ? ColorTheme.success : ColorTheme.danger).opacity(colorScheme == .dark ? 0.16 : 0.08))
        )
    }

    // MARK: - Actions

    private func syncOptionalCodeVisibility(forceOpen: Bool = false) {
        if appSessionState.mode != .signUp {
            showingOptionalCodes = false
            return
        }

        if forceOpen || hasOptionalCodes {
            showingOptionalCodes = true
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
                }
            }
        }
    }

    private func startGuestMode() {
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
        Task {
            await appSessionState.authenticate()
        }
    }
}
