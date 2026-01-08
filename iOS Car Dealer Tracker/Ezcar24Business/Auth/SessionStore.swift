import Foundation
import Supabase

@MainActor
final class SessionStore: ObservableObject {
    enum Status: Equatable {
        case loading
        case signedOut
        case signedIn(user: Auth.User)
    }

    @Published private(set) var status: Status = .loading
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?
    @Published var showPasswordReset = false
    
    private var isPasswordRecoverySessionActive = false
    private let passwordRecoveryFlagKey = "passwordRecoveryInProgress"
    private let lastSignedInUserIdKey = "lastSignedInUserId"

    private let client: SupabaseClient
    private var authChangeTask: Task<Void, Never>?
    private var didBootstrap = false

    init(client: SupabaseClient) {
        self.client = client
        
        if UserDefaults.standard.bool(forKey: passwordRecoveryFlagKey) {
            beginPasswordRecoveryFlow()
        }
        
        listenForAuthChanges()
    }

    deinit {
        authChangeTask?.cancel()
    }

    var shouldShowEmailReminderBanner: Bool {
        guard case .signedIn(let user) = status else { return false }

        // Supabase Swift exposes userMetadata as [String: AnyJSON]. Convert helpers
        func value<T>(_ key: String, as type: T.Type) -> T? {
            guard let any = user.userMetadata[key] else { return nil }
            // Try decoding the AnyJSON payload into the requested type
            if let val = any.value as? T { return val }
            // Fallback: try to serialize to Data then decode
            do {
                let data = try JSONSerialization.data(withJSONObject: any.value, options: [])
                if T.self == String.self, let str = String(data: data, encoding: .utf8) as? T { return str }
            } catch { }
            return nil
        }

        // 1) Booleans commonly used to mark confirmation
        if let emailConfirmed: Bool = value("email_confirmed", as: Bool.self) {
            return !emailConfirmed
        }
        if let isVerified: Bool = value("is_verified", as: Bool.self) {
            return !isVerified
        }

        // 2) Timestamp as ISO8601 string (Supabase often stores strings)
        if let confirmedAtString: String = value("email_confirmed_at", as: String.self) {
            let trimmed = confirmedAtString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let iso = ISO8601DateFormatter()
                if iso.date(from: trimmed) != nil { return false }
                return false
            }
        }

        // 3) Or sometimes a numeric epoch seconds
        if let epoch: Double = value("email_confirmed_at", as: Double.self) {
            if epoch > 0 { return false }
        }

        // 4) Or a Date object in metadata (rare)
        if let _: Date = value("email_confirmed_at", as: Date.self) {
            return false
        }

        // If unknown, do not show banner to avoid false positives
        return false
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        if let currentSession = client.auth.currentSession {
            if currentSession.isExpired {
                do {
                    let refreshed = try await client.auth.refreshSession()
                    updateStatus(for: .tokenRefreshed, session: refreshed)
                    errorMessage = nil
                } catch {
                    status = .signedOut
                    errorMessage = localized(error)
                }
            } else {
                updateStatus(for: .initialSession, session: currentSession)
                // Link RevenueCat user on launch
                SubscriptionManager.shared.logIn(userId: currentSession.user.id.uuidString)
                errorMessage = nil
            }
        } else {
            status = .signedOut
            errorMessage = nil
            // Ensure RevenueCat identity is cleared when there is no Supabase session
            SubscriptionManager.shared.logOut()
        }
    }

    func signIn(email: String, password: String) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            updateStatus(for: .signedIn, session: session)
            // Link RevenueCat user
            SubscriptionManager.shared.logIn(userId: session.user.id.uuidString)
            errorMessage = nil
        } catch {
            errorMessage = localized(error)
            throw error
        }
    }

    func signUp(email: String, password: String) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let response = try await client.auth.signUp(email: email, password: password)

            if let session = response.session {
                updateStatus(for: .signedIn, session: session)
                // Link RevenueCat user
                SubscriptionManager.shared.logIn(userId: session.user.id.uuidString)
                errorMessage = nil
                return
            }

            status = .signedOut
            errorMessage = "Please confirm your email via the link sent before signing in."
        } catch {
            errorMessage = localized(error)
            throw error
        }
    }

    func signOut() async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            try await client.auth.signOut()
            cleanupAfterSignOut()
        } catch {
            errorMessage = localized(error)
        }
    }

    func updatePassword(_ newPassword: String) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            try await client.auth.update(user: UserAttributes(password: newPassword))
            errorMessage = nil
        } catch {
            errorMessage = localized(error)
            throw error
        }
    }
    
    func completePasswordRecovery(newPassword: String) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            // Update password using the temporary recovery session
            try await client.auth.update(user: UserAttributes(password: newPassword))
            // Force sign-out so the user must authenticate manually with the new password
            try await client.auth.signOut()
            cleanupAfterSignOut()
            errorMessage = nil
        } catch {
            errorMessage = localized(error)
            throw error
        }
    }
    
    func cancelPasswordRecoveryFlow() async {
        isPasswordRecoverySessionActive = false
        showPasswordReset = false
        do {
            try await client.auth.signOut()
        } catch { }
        cleanupAfterSignOut()
    }
    
    func dismissPasswordResetUI() {
        showPasswordReset = false
    }

    func resetPassword(email: String) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            // Mark that a recovery flow was initiated so we can detect callbacks even if Supabase strips query params
            UserDefaults.standard.set(true, forKey: passwordRecoveryFlagKey)
            // Explicitly tell Supabase where to redirect back to the app
            // NOTE: This must exactly match an allowed Redirect URL in Supabase Auth settings.
            let redirectURL = URL(string: "com.ezcar24.business://login-callback")
            try await client.auth.resetPasswordForEmail(email, redirectTo: redirectURL)
            errorMessage = nil
        } catch {
            errorMessage = localized(error)
            throw error
        }
    }

    func deleteAccount() async throws {
        guard case .signedIn(let user) = status else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        
        do {
            // 1. Wipe all data from public tables first
            // This ensures we don't hit foreign key constraints when deleting the user
            try await CloudSyncManager.shared?.deleteAllRemoteData(dealerId: user.id)
            
            // 2. Request backend-led account cleanup; final auth deletion is handled server-side
            let params: [String: String] = ["user_id": user.id.uuidString]
            _ = try await client.rpc("delete_user_account", params: params).execute()
            
            status = .signedOut
            errorMessage = nil
            
            // Cleanup local state
            cleanupAfterSignOut()
            
        } catch {
            errorMessage = localized(error)
            throw error
        }
    }

    func resetError() {
        errorMessage = nil
    }

    func handleDeepLink(_ url: URL) async throws {
        // Check if this is a password recovery link
        let urlString = url.absoluteString.lowercased()
        print("Deep link received:", urlString)
        let isExplicitRecovery = urlString.contains("type=recovery") || urlString.contains("recovery")
        let isLoginCallback = urlString.contains("com.ezcar24.business://login-callback")
        let hasPendingRecovery = UserDefaults.standard.bool(forKey: passwordRecoveryFlagKey)

        if isExplicitRecovery || (hasPendingRecovery && isLoginCallback) {
            // This is a password reset link
            beginPasswordRecoveryFlow()
            // Drop any existing session before handling recovery link so we don't auto-enter the app
            do {
                try await client.auth.signOut()
            } catch { }
            client.handle(url)
        } else {
            // Regular magic link or other auth link
            client.handle(url)
        }
    }

    private func listenForAuthChanges() {
        authChangeTask?.cancel()
        authChangeTask = Task { [weak self] in
            guard let self else { return }

            for await change in client.auth.authStateChanges {
                self.updateStatus(for: change.event, session: change.session)
            }
        }
    }

    private func updateStatus(for event: AuthChangeEvent, session: Session?) {
        switch event {
        case .initialSession, .tokenRefreshed, .userUpdated, .signedIn:
            // During password recovery we intentionally block automatic sign-in
            guard !isPasswordRecoverySessionActive else { return }
            if let session {
                handleAccountChangeIfNeeded(newUserId: session.user.id)
                status = .signedIn(user: session.user)
                errorMessage = nil
            } else {
                status = .signedOut
                errorMessage = nil
            }
        case .signedOut, .userDeleted:
            status = .signedOut
            errorMessage = nil
            isPasswordRecoverySessionActive = false
            // Keep RevenueCat user in sync with auth state to avoid stale entitlements
            SubscriptionManager.shared.logOut()
        case .passwordRecovery:
            // User clicked password reset link - show the reset UI but keep them signed out
            beginPasswordRecoveryFlow()
        case .mfaChallengeVerified:
            break
        }
    }

    private func handleAccountChangeIfNeeded(newUserId: UUID) {
        let defaults = UserDefaults.standard
        if let previousId = defaults.string(forKey: lastSignedInUserIdKey),
           previousId != newUserId.uuidString {
            resetLocalStateForAccountChange()
        }
        defaults.set(newUserId.uuidString, forKey: lastSignedInUserIdKey)
    }

    private func resetLocalStateForAccountChange() {
        PersistenceController.shared.deleteAllData()
        Task {
            await SyncQueueManager.shared.clear()
        }
        UserDefaults.standard.removeObject(forKey: "lastSyncTimestamp")
        ImageStore.shared.clearAll()
        CloudSyncManager.shared?.resetSyncState()
    }

    private func beginPasswordRecoveryFlow() {
        isPasswordRecoverySessionActive = true
        UserDefaults.standard.set(true, forKey: passwordRecoveryFlagKey)
        showPasswordReset = true
        status = .signedOut
        errorMessage = nil
    }

    private func cleanupAfterSignOut() {
        status = .signedOut
        errorMessage = nil
        isPasswordRecoverySessionActive = false
        UserDefaults.standard.removeObject(forKey: passwordRecoveryFlagKey)
        // Logout from RevenueCat and clear any cached entitlement state
        SubscriptionManager.shared.logOut()
        // IMPORTANT: For this app we must fully isolate data between users/guests.
        // After sign out we wipe all local Core Data entities and clear the
        // offline sync queue so operations from the previous user are never
        // replayed for the next user.
        PersistenceController.shared.deleteAllData()
        Task {
            await SyncQueueManager.shared.clear()
        }
        UserDefaults.standard.removeObject(forKey: "lastSyncTimestamp")
        ImageStore.shared.clearAll()
    }

    private func localized(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return prettify(description)
        }
        return prettify(error.localizedDescription)
    }

    private func prettify(_ message: String) -> String {
        if message.contains("gmail.com") && message.contains("invalid") {
            return "Supabase rejects gmail addresses shorter than 6 characters before the @. Add characters before @ or use another email."
        }
        return message
    }
}
