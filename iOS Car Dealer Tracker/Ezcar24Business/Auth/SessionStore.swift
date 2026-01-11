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
    @Published private(set) var activeOrganizationId: UUID?
    @Published private(set) var organizations: [OrganizationMembership] = []
    @Published private(set) var inviteToastMessage: String?
    @Published private(set) var inviteToastIsError = false
    @Published private(set) var isAcceptingInvite = false
    
    private var isPasswordRecoverySessionActive = false
    private let passwordRecoveryFlagKey = "passwordRecoveryInProgress"
    private let lastSignedInUserIdKey = "lastSignedInUserId"
    private let pendingInviteTokenKey = "pendingInviteToken"
    private let pendingInviteTokenTimestampKey = "pendingInviteTokenTimestamp"
    private let activeOrganizationKeyPrefix = "activeOrganizationId"

    private let client: SupabaseClient
    private var authChangeTask: Task<Void, Never>?
    private var didBootstrap = false

    struct OrganizationMembership: Identifiable, Decodable, Equatable {
        let organization_id: UUID
        let organization_name: String
        let role: String
        let status: String

        var id: UUID { organization_id }
    }

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

    var activeOrganization: OrganizationMembership? {
        guard let activeOrganizationId else { return nil }
        return organizations.first(where: { $0.organization_id == activeOrganizationId })
    }

    var activeOrganizationName: String? {
        activeOrganization?.organization_name
    }

    var activeOrganizationRole: String? {
        activeOrganization?.role
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
                await loadOrganizations()
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
            guard client.auth.currentSession != nil else {
                let message = "auth_recovery_session_missing".localizedString
                errorMessage = message
                throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: message])
            }
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
            struct PasswordResetPayload: Encodable {
                let email: String
                let redirect_to: String
            }
            let payload = PasswordResetPayload(
                email: email,
                redirect_to: redirectURL?.absoluteString ?? ""
            )
            do {
                _ = try await client.functions.invoke(
                    "request_password_reset",
                    options: FunctionInvokeOptions(body: payload)
                )
            } catch {
                if case let FunctionsError.httpError(code, _) = error, code == 404 {
                    try await client.auth.resetPasswordForEmail(email, redirectTo: redirectURL)
                } else {
                    let resolved = functionErrorMessage(from: error)
                    errorMessage = resolved.message
                    throw error
                }
            }
            errorMessage = nil
        } catch {
            if errorMessage == nil {
                errorMessage = localized(error)
            }
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

    func refreshPermissionsIfPossible() async {
        guard case .signedIn = status else { return }
        guard let dealerId = activeOrganizationId else { return }
        await PermissionService.shared.fetchPermissions(dealerId: dealerId)
    }

    func handleDeepLink(_ url: URL) async throws {
        if await handleInviteDeepLink(url) {
            return
        }

        // Check if this is a password recovery link
        let urlString = url.absoluteString.lowercased()
        print("Deep link received:", urlString)
        let isExplicitRecovery = urlString.contains("type=recovery") || urlString.contains("recovery")
        let isLoginCallback = urlString.contains("com.ezcar24.business://login-callback")
        let hasPendingRecovery = UserDefaults.standard.bool(forKey: passwordRecoveryFlagKey)
        let expectsRecovery = isExplicitRecovery || (hasPendingRecovery && isLoginCallback)

        if expectsRecovery {
            // This is a password reset link
            beginPasswordRecoveryFlow()
        }

        do {
            _ = try await client.auth.session(from: url)
        } catch {
            if expectsRecovery {
                errorMessage = "auth_recovery_session_missing".localizedString
            } else {
                errorMessage = localized(error)
            }
            throw error
        }
    }

    func prepareForSync() async {
        await ensurePersonalOrganizationIfNeeded()
        await loadOrganizations()

        if pendingInviteToken() != nil {
            _ = await acceptPendingInviteIfPossible()
            await loadOrganizations()
        }

        if pendingInviteToken() != nil {
            clearPendingInviteToken()
        }
    }

    func dismissInviteToast() {
        inviteToastMessage = nil
        inviteToastIsError = false
    }

    private func loadOrganizations() async {
        guard case .signedIn(let user) = status else {
            organizations = []
            applyActiveOrganization(nil, persist: false)
            return
        }

        do {
            let list: [OrganizationMembership] = try await client
                .rpc("get_my_organizations")
                .execute()
                .value
            organizations = list

            let stored = restoreActiveOrganizationId(for: user.id)
            if let stored, list.contains(where: { $0.organization_id == stored }) {
                applyActiveOrganization(stored, persist: false)
                return
            }

            if let personal = list.first(where: { $0.organization_id == user.id }) {
                applyActiveOrganization(personal.organization_id, persist: true)
                return
            }

            if let first = list.first {
                applyActiveOrganization(first.organization_id, persist: true)
                return
            }

            applyActiveOrganization(nil, persist: false)
        } catch {
            organizations = []
            applyActiveOrganization(nil, persist: false)
        }
    }

    private func ensurePersonalOrganizationIfNeeded() async {
        guard case .signedIn = status else { return }
        do {
            _ = try await client.rpc("ensure_personal_organization").execute()
        } catch {
            // Non-fatal; user might already be configured
        }
    }

    func createOrganization(name: String) async throws -> UUID {
        let params = ["_name": name]
        let orgId: UUID = try await client
            .rpc("create_organization", params: params)
            .execute()
            .value
        await loadOrganizations()
        return orgId
    }

    func switchOrganization(to organizationId: UUID) async {
        applyActiveOrganization(organizationId, persist: true)

        if let dealerId = activeOrganizationId {
            ImageStore.shared.setActiveDealerId(dealerId)
            PermissionService.shared.configure(client: client, dealerId: dealerId)
            await PermissionService.shared.fetchPermissions(dealerId: dealerId)
        }

        if case .signedIn(let user) = status {
            CloudSyncManager.shared?.updateContext(PersistenceController.shared.viewContext)
            CloudSyncManager.shared?.refreshLastSyncForCurrentOrg()
            await CloudSyncManager.shared?.syncAfterLogin(user: user)
        }
    }

    private func applyActiveOrganization(_ orgId: UUID?, persist: Bool) {
        activeOrganizationId = orgId
        PersistenceController.shared.setActiveStore(organizationId: orgId)
        CloudSyncManager.shared?.updateContext(PersistenceController.shared.viewContext)
        CloudSyncManager.shared?.refreshLastSyncForCurrentOrg()
        ImageStore.shared.setActiveDealerId(orgId)
        PermissionService.shared.setActiveDealerId(orgId)
        if persist, let orgId, case .signedIn(let user) = status {
            persistActiveOrganizationId(orgId, for: user.id)
        }
    }

    private func persistActiveOrganizationId(_ orgId: UUID, for userId: UUID) {
        UserDefaults.standard.set(orgId.uuidString, forKey: activeOrganizationDefaultsKey(for: userId))
    }

    private func restoreActiveOrganizationId(for userId: UUID) -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: activeOrganizationDefaultsKey(for: userId)) else { return nil }
        return UUID(uuidString: raw)
    }

    private func activeOrganizationDefaultsKey(for userId: UUID) -> String {
        "\(activeOrganizationKeyPrefix)_\(userId.uuidString)"
    }

    private func handleInviteDeepLink(_ url: URL) async -> Bool {
        guard let token = extractInviteToken(from: url) else { return false }
        cachePendingInviteToken(token)

        switch status {
        case .signedIn:
            _ = await acceptInvite(token: token)
        default:
            errorMessage = "Invitation link saved. Sign in to accept."
        }

        return true
    }

    private func extractInviteToken(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let isUniversalInvite = host.contains("ezcar24.com") && path.contains("accept-invite")
        let isCustomInvite = host.contains("accept-invite")

        guard isUniversalInvite || isCustomInvite else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "token" })?.value
    }

    private func acceptPendingInviteIfPossible() async -> Bool {
        guard let token = pendingInviteToken() else { return false }
        return await acceptInvite(token: token)
    }

    private func acceptInvite(token: String) async -> Bool {
        guard !isAcceptingInvite else { return false }
        guard case .signedIn = status else { return false }
        isAcceptingInvite = true
        defer { isAcceptingInvite = false }

        do {
            let _ = try await client
                .functions
                .invoke("accept_invite", options: FunctionInvokeOptions(body: ["token": token]))
            clearPendingInviteToken()
            await loadOrganizations()
            showInviteToast(message: "Invitation accepted. Use the switcher to change organizations.", isError: false)
            return true
        } catch {
            let resolved = functionErrorMessage(from: error)
            if shouldClearPendingInviteToken(statusCode: resolved.statusCode, message: resolved.message) {
                clearPendingInviteToken()
            }
            showInviteToast(message: resolved.message, isError: true)
            return false
        }
    }

    private func cachePendingInviteToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: pendingInviteTokenKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: pendingInviteTokenTimestampKey)
    }

    private func pendingInviteToken() -> String? {
        guard let token = UserDefaults.standard.string(forKey: pendingInviteTokenKey) else { return nil }
        let timestamp = UserDefaults.standard.object(forKey: pendingInviteTokenTimestampKey) as? Double
        guard let timestamp else {
            clearPendingInviteToken()
            return nil
        }
        let maxAge: TimeInterval = 26 * 60 * 60
        if Date().timeIntervalSince1970 - timestamp > maxAge {
            clearPendingInviteToken()
            return nil
        }
        return token
    }

    private func clearPendingInviteToken() {
        UserDefaults.standard.removeObject(forKey: pendingInviteTokenKey)
        UserDefaults.standard.removeObject(forKey: pendingInviteTokenTimestampKey)
    }

    private func showInviteToast(message: String, isError: Bool) {
        inviteToastMessage = message
        inviteToastIsError = isError
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            if inviteToastMessage == message {
                inviteToastMessage = nil
                inviteToastIsError = false
            }
        }
    }

    private struct FunctionErrorPayload: Decodable {
        let error: String
    }

    private func functionErrorMessage(from error: Error) -> (message: String, statusCode: Int?) {
        if let functionsError = error as? FunctionsError {
            switch functionsError {
            case let .httpError(code, data):
                if let payload = try? JSONDecoder().decode(FunctionErrorPayload.self, from: data) {
                    let trimmed = payload.error.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return (prettify(trimmed), code)
                    }
                }
                return (localized(error), code)
            case .relayError:
                return (localized(error), nil)
            }
        }
        return (localized(error), nil)
    }

    private func shouldClearPendingInviteToken(statusCode: Int?, message: String) -> Bool {
        if let code = statusCode, (400..<500).contains(code) {
            return true
        }
        let lower = message.lowercased()
        return lower.contains("invalid") ||
            lower.contains("expired") ||
            lower.contains("already") ||
            lower.contains("mismatch")
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
        CloudSyncManager.shared?.updateContext(PersistenceController.shared.viewContext)
        Task {
            await SyncQueueManager.shared.clear()
        }
        CloudSyncManager.clearAllSyncTimestamps()
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
        activeOrganizationId = nil
        organizations = []
        inviteToastMessage = nil
        inviteToastIsError = false
        isAcceptingInvite = false
        PermissionService.shared.resetSession()
        UserDefaults.standard.removeObject(forKey: passwordRecoveryFlagKey)
        ImageStore.shared.setActiveDealerId(nil)
        // Logout from RevenueCat and clear any cached entitlement state
        SubscriptionManager.shared.logOut()
        // IMPORTANT: For this app we must fully isolate data between users/guests.
        // After sign out we wipe all local Core Data entities and clear the
        // offline sync queue so operations from the previous user are never
        // replayed for the next user.
        PersistenceController.shared.deleteAllData()
        CloudSyncManager.shared?.updateContext(PersistenceController.shared.viewContext)
        Task {
            await SyncQueueManager.shared.clear()
        }
        CloudSyncManager.clearAllSyncTimestamps()
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
