import AuthenticationServices
import CryptoKit
import Security
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
    @State private var appleSignInNonce: String?
    @State private var didTrackAuthScreen = false
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
        appSessionState.mode == .signIn ? "Sign In".localizedString : "Create Account".localizedString
    }

    private var pendingInviteMessage: String? {
        guard !trimmedTeamInviteCode.isEmpty else { return nil }
        if appSessionState.mode == .signIn {
            return "team_access_applied_after_sign_in".localizedString
        }
        return "team_access_ready_after_sign_up".localizedString
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
            .onAppear {
                guard !didTrackAuthScreen else { return }
                didTrackAuthScreen = true
                OnboardingAnalytics.capture(
                    .authScreenViewed,
                    properties: ["auth_mode": appSessionState.mode.analyticsName]
                )
            }
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
                OnboardingAnalytics.capture(.authModeChanged, properties: ["auth_mode": newMode.analyticsName])
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

                Text(appSessionState.mode == .signIn ? "Welcome Back".localizedString : "Create your account".localizedString)
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
                        Button("Forgot password?".localizedString) {
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
                Text(appSessionState.mode == .signIn ? "Don't have an account?".localizedString : "Already have an account?".localizedString)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ColorTheme.secondaryText)
                
                Button(appSessionState.mode == .signIn ? "Sign Up".localizedString : "Sign In".localizedString) {
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0.03)) {
                        appSessionState.mode = appSessionState.mode == .signIn ? .signUp : .signIn
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ColorTheme.primaryText)
            }
            .padding(.top, 4)

            socialAuthSection
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
                withAnimation(.snappy(duration: 0.24, extraBounce: 0.03)) {
                    showingOptionalCodes.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showingOptionalCodes ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                    Text("Have an invite code?".localizedString)
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

                    authField(icon: "person.badge.plus", placeholder: "Team Invite Code", text: $appSessionState.teamInviteCode)
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
                    TextField("Password".localizedString, text: $appSessionState.password)
                        .keyboardType(.asciiCapable)
                } else {
                    SecureField("Password".localizedString, text: $appSessionState.password)
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
            .accessibilityLabel((showPassword ? "hide_password" : "show_password").localizedString)
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
            
            TextField(placeholder.localizedString, text: text)
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

    private var socialAuthSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(ColorTheme.secondaryText.opacity(0.22))
                    .frame(height: 1)

                Text("or".localizedString)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(ColorTheme.secondaryText)
                    .textCase(.uppercase)

                Rectangle()
                    .fill(ColorTheme.secondaryText.opacity(0.22))
                    .frame(height: 1)
            }

            VStack(spacing: 12) {
                SignInWithAppleButton(.continue, onRequest: configureAppleSignIn, onCompletion: handleAppleSignIn)
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .disabled(sessionStore.isAuthenticating || appSessionState.isProcessing)

                Button(action: handleGoogleSignIn) {
                    HStack(spacing: 12) {
                        googleBrandMark
                        Text("Continue with Google".localizedString)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))

                        if sessionStore.isAuthenticating {
                            ProgressView()
                                .scaleEffect(0.82)
                        }
                    }
                    .foregroundStyle(ColorTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.86))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.75), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(sessionStore.isAuthenticating || appSessionState.isProcessing)
            }
        }
    }

    private var googleBrandMark: some View {
        ZStack {
            Circle()
                .fill(Color.white)
            Text("G")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
        }
        .frame(width: 24, height: 24)
        .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
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
        OnboardingAnalytics.capture(
            .passwordResetRequested,
            properties: ["has_email": !appSessionState.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty]
        )
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

    private func handleGoogleSignIn() {
        let properties = socialAuthProperties(method: "google")
        OnboardingAnalytics.capture(.authSubmitted, properties: properties)
        prepareSocialAuthContext()
        sessionStore.resetError()
        Task {
            do {
                try await sessionStore.signInWithGoogle()
                appSessionState.isGuestMode = false
                trackSocialAuthCompleted(properties: properties)
                clearSocialSensitiveFields()
            } catch {
                OnboardingAnalytics.capture(.authFailed, properties: properties)
            }
        }
    }

    private func configureAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        OnboardingAnalytics.capture(.authSubmitted, properties: socialAuthProperties(method: "apple"))
        prepareSocialAuthContext()
        let nonce = Self.randomNonceString()
        appleSignInNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        let properties = socialAuthProperties(method: "apple")
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let nonce = appleSignInNonce,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                sessionStore.errorMessage = "social_sign_in_failed".localizedString
                OnboardingAnalytics.capture(.authFailed, properties: properties)
                return
            }

            Task {
                do {
                    try await sessionStore.signInWithApple(idToken: idToken, nonce: nonce, fullName: credential.fullName)
                    appSessionState.isGuestMode = false
                    trackSocialAuthCompleted(properties: properties)
                    clearSocialSensitiveFields()
                } catch {
                    OnboardingAnalytics.capture(.authFailed, properties: properties)
                }
            }
        case .failure(let error):
            if let authorizationError = error as? ASAuthorizationError, authorizationError.code == .canceled {
                sessionStore.resetError()
            } else {
                sessionStore.errorMessage = "social_sign_in_failed".localizedString
                OnboardingAnalytics.capture(.authFailed, properties: properties)
            }
        }
    }

    private func prepareSocialAuthContext() {
        let referralCode = appSessionState.mode == .signUp ? trimmedReferralCode : nil
        let teamInviteCode = trimmedTeamInviteCode
        sessionStore.savePendingSocialAuthContext(
            referralCode: referralCode?.isEmpty == false ? referralCode : nil,
            teamInviteCode: teamInviteCode.isEmpty ? nil : teamInviteCode
        )
    }

    private func clearSocialSensitiveFields() {
        appSessionState.password = ""
        appSessionState.phone = ""
        appSessionState.referralCode = ""
        appSessionState.teamInviteCode = ""
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

    private func socialAuthProperties(method: String) -> [String: Any] {
        [
            "auth_mode": appSessionState.mode.analyticsName,
            "auth_method": method,
            "has_referral_code": !trimmedReferralCode.isEmpty,
            "has_team_invite_code": !trimmedTeamInviteCode.isEmpty
        ]
    }

    private func trackSocialAuthCompleted(properties: [String: Any]) {
        if case .signedIn(let user) = sessionStore.status {
            OnboardingAnalytics.identifyUser(user.id)
        }
        OnboardingAnalytics.capture(.authCompleted, properties: properties)
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                if Int(random) < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }
}
