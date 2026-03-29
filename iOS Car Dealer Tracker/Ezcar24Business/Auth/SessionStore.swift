import Foundation
import Supabase

struct ReferralStats: Equatable {
    let totalRewards: Int
    let lastRewardedAt: Date?
    let bonusAccessUntil: Date?
    let totalMonths: Int

    static let empty = ReferralStats(totalRewards: 0, lastRewardedAt: nil, bonusAccessUntil: nil, totalMonths: 0)
}

private struct DeleteAccountPayload: Encodable {}

private struct DeleteAccountResponse: Decodable {
    let success: Bool
}

enum AuthRedirect {
    static let callbackURL = URL(string: "com.ezcar24.business://login-callback")!
    static let universalLinkCallbackURLs = [
        URL(string: "https://ezcar24.com/login-callback")!,
        URL(string: "https://www.ezcar24.com/login-callback")!
    ]

    static func matchesCallback(_ url: URL) -> Bool {
        let normalizedURL = normalized(url)
        if normalizedURL == normalized(callbackURL) {
            return true
        }
        return universalLinkCallbackURLs.contains { normalizedURL == normalized($0) }
    }

    private static func normalized(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        let absoluteString = components?.url?.absoluteString ?? url.absoluteString
        return absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }
}

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
    @Published private(set) var pendingReferralCode: String?
    @Published private(set) var pendingTeamInviteCode: String?
    
    private var isPasswordRecoverySessionActive = false
    private let passwordRecoveryFlagKey = "passwordRecoveryInProgress"
    private let lastSignedInUserIdKey = "lastSignedInUserId"
    private let pendingInviteTokenKey = "pendingInviteToken"
    private let pendingInviteTokenTimestampKey = "pendingInviteTokenTimestamp"
    private let pendingTeamInviteCodeKey = "pendingTeamInviteCode"
    private let pendingTeamInviteCodeTimestampKey = "pendingTeamInviteCodeTimestamp"
    private let pendingReferralCodeKey = "pendingReferralCode"
    private let pendingReferralCodeTimestampKey = "pendingReferralCodeTimestamp"
    private let pendingProfilePhoneKeyPrefix = "pendingProfilePhone_"
    private let pendingProfileEmailKeyPrefix = "pendingProfileEmail_"
    private let activeOrganizationKeyPrefix = "activeOrganizationId"
    private let dealerReferralCodeKeyPrefix = "dealerReferralCode_"

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
        self.pendingReferralCode = UserDefaults.standard.string(forKey: pendingReferralCodeKey)
        self.pendingTeamInviteCode = SessionStore.readPendingTeamInviteCode(
            key: pendingTeamInviteCodeKey,
            timestampKey: pendingTeamInviteCodeTimestampKey
        )
        
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
        let metadata = user.userMetadata.reduce(into: [String: Any]()) { partialResult, item in
            partialResult[item.key] = item.value.value
        }
        return Self.shouldShowEmailReminderBanner(
            emailConfirmedAt: user.emailConfirmedAt,
            confirmedAt: user.confirmedAt,
            metadata: metadata
        )
    }

    var currentAuthEmail: String? {
        guard case .signedIn(let user) = status else { return nil }
        return Self.normalizedEmail(user.email)
    }

    var pendingEmailChange: String? {
        guard case .signedIn(let user) = status else { return nil }
        return Self.pendingEmailChange(currentEmail: user.email, newEmail: user.newEmail)
    }

    static func pendingEmailChange(currentEmail: String?, newEmail: String?) -> String? {
        let normalizedCurrent = normalizedEmail(currentEmail)
        let normalizedNew = normalizedEmail(newEmail)

        guard let normalizedNew else { return nil }
        guard normalizedNew != normalizedCurrent else { return nil }
        return normalizedNew
    }

    static func shouldShowEmailReminderBanner(
        emailConfirmedAt: Date?,
        confirmedAt: Date?,
        metadata: [String: Any]
    ) -> Bool {
        if emailConfirmedAt != nil || confirmedAt != nil {
            return false
        }

        func metadataValue(_ key: String) -> Any? {
            metadata[key]
        }

        func boolValue(_ key: String) -> Bool? {
            guard let raw = metadataValue(key) else { return nil }
            if let value = raw as? Bool {
                return value
            }
            if let number = raw as? NSNumber {
                return number.boolValue
            }
            if let string = raw as? String {
                switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "1", "yes":
                    return true
                case "false", "0", "no":
                    return false
                default:
                    return nil
                }
            }
            return nil
        }

        func stringValue(_ key: String) -> String? {
            guard let raw = metadataValue(key) else { return nil }
            if let value = raw as? String {
                return value
            }
            if let number = raw as? NSNumber {
                return number.stringValue
            }
            return nil
        }

        func doubleValue(_ key: String) -> Double? {
            guard let raw = metadataValue(key) else { return nil }
            if let value = raw as? Double {
                return value
            }
            if let value = raw as? NSNumber {
                return value.doubleValue
            }
            if let value = raw as? String {
                return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return nil
        }

        func dateValue(_ key: String) -> Date? {
            if let raw = metadataValue(key) as? Date {
                return raw
            }
            if let string = stringValue(key) {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let iso = ISO8601DateFormatter()
                return iso.date(from: trimmed)
            }
            if let epoch = doubleValue(key), epoch > 0 {
                return Date(timeIntervalSince1970: epoch)
            }
            return nil
        }

        if let emailConfirmed = boolValue("email_confirmed") {
            return !emailConfirmed
        }
        if let isVerified = boolValue("is_verified") {
            return !isVerified
        }

        if let confirmedAtString = stringValue("email_confirmed_at") {
            let trimmed = confirmedAtString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let iso = ISO8601DateFormatter()
                return iso.date(from: trimmed) == nil && Double(trimmed) == nil
            }
            return true
        }

        if let epoch = doubleValue("email_confirmed_at") {
            return epoch <= 0
        }

        if dateValue("email_confirmed_at") != nil {
            return false
        }

        return true
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
                // Load permissions immediately after organizations to prevent UI jumping
                let dealerId = activeOrganizationId ?? currentSession.user.id
                await PermissionService.shared.fetchPermissions(dealerId: dealerId)
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

    func signUp(email: String, password: String, phone: String?, referralCode: String?) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            if let referralCode, !referralCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cachePendingReferralCode(referralCode)
            }
            let response = try await client.auth.signUp(email: email, password: password)

            if let session = response.session {
                updateStatus(for: .signedIn, session: session)
                // Link RevenueCat user
                SubscriptionManager.shared.logIn(userId: session.user.id.uuidString)
                cachePendingProfile(userId: session.user.id, phone: phone, email: session.user.email ?? email)
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

    private func cachePendingProfile(userId: UUID, phone: String?, email: String?) {
        let defaults = UserDefaults.standard
        if let phone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.set(phone, forKey: "\(pendingProfilePhoneKeyPrefix)\(userId.uuidString)")
        }
        if let email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.set(email, forKey: "\(pendingProfileEmailKeyPrefix)\(userId.uuidString)")
        }
    }

    private static func normalizedEmail(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
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

    func updateEmail(_ newEmail: String) async throws -> Auth.User {
        isAuthenticating = true
        defer { isAuthenticating = false }

        let normalizedEmail = newEmail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let currentAuthEmail, currentAuthEmail == normalizedEmail, case .signedIn(let user) = status {
            errorMessage = nil
            return user
        }

        do {
            let updatedUser = try await client.auth.update(
                user: UserAttributes(email: normalizedEmail),
                redirectTo: AuthRedirect.callbackURL
            )
            if case .signedIn = status {
                status = .signedIn(user: updatedUser)
            }
            errorMessage = nil
            return updatedUser
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
            struct PasswordResetPayload: Encodable {
                let email: String
                let redirect_to: String
            }
            let payload = PasswordResetPayload(
                email: email,
                redirect_to: AuthRedirect.callbackURL.absoluteString
            )
            do {
                _ = try await client.functions.invoke(
                    "request_password_reset",
                    options: FunctionInvokeOptions(body: payload)
                )
            } catch {
                if case let FunctionsError.httpError(code, _) = error, code == 404 {
                    try await client.auth.resetPasswordForEmail(email, redirectTo: AuthRedirect.callbackURL)
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
        guard case .signedIn = status else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        
        do {
            let response: DeleteAccountResponse = try await client.functions.invoke(
                "delete_account",
                options: FunctionInvokeOptions(body: DeleteAccountPayload())
            )
            guard response.success else {
                throw NSError(
                    domain: "Auth",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "Account deletion did not complete."]
                )
            }
            try? await client.auth.signOut()
            errorMessage = nil
            cleanupAfterSignOut()
        } catch {
            errorMessage = functionErrorMessage(from: error).message
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
        if await handleReferralDeepLink(url) {
            return
        }
        if await handleInviteDeepLink(url) {
            return
        }

        // Check if this is a password recovery link
        let urlString = url.absoluteString.lowercased()
        print("Deep link received:", urlString)
        let isExplicitRecovery = urlString.contains("type=recovery") || urlString.contains("recovery")
        let isLoginCallback = AuthRedirect.matchesCallback(url)
        let hasPendingRecovery = UserDefaults.standard.bool(forKey: passwordRecoveryFlagKey)
        let expectsRecovery = isExplicitRecovery || (hasPendingRecovery && isLoginCallback)

        if expectsRecovery {
            // This is a password reset link
            beginPasswordRecoveryFlow()
        }

        do {
            let session = try await client.auth.session(from: url)
            updateStatus(for: .signedIn, session: session)
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

        if pendingTeamInviteCodeValue() != nil {
            _ = await acceptPendingTeamInviteCodeIfPossible()
            await loadOrganizations()
        }

        if storedReferralCode() != nil {
            _ = await claimPendingReferralIfPossible()
        }

        await refreshReferralBonus()

        if pendingInviteToken() != nil {
            clearPendingInviteToken()
        }
        if pendingTeamInviteCodeValue() != nil {
            clearPendingTeamInviteCode()
        }
    }

    func getDealerReferralCode(dealerId: UUID) async -> String? {
        let cached = cachedDealerReferralCode(dealerId: dealerId)
        do {
            let params: [String: AnyJSON] = [
                "p_dealer_id": .string(dealerId.uuidString)
            ]
            let code: String = try await client
                .rpc("get_or_create_dealer_referral_code", params: params)
                .execute()
                .value
            cacheDealerReferralCode(code, dealerId: dealerId)
            return code
        } catch {
            print("getDealerReferralCode error: \(error)")
            if let fallback = await fetchExistingDealerReferralCode(dealerId: dealerId) {
                cacheDealerReferralCode(fallback, dealerId: dealerId)
                return fallback
            }
            return cached
        }
    }

    func resolveDealerIdForReferral() async -> UUID? {
        guard case .signedIn(let user) = status else { return nil }
        if activeOrganizationId == nil || organizations.isEmpty {
            await loadOrganizations()
        }
        if let activeOrganizationId {
            return activeOrganizationId
        }
        if let first = organizations.first?.organization_id {
            return first
        }
        return user.id
    }

    func refreshReferralBonus() async {
        guard case .signedIn(let user) = status else { return }
        struct BonusRow: Decodable {
            let bonusAccessUntil: Date
            let totalMonths: Int
            enum CodingKeys: String, CodingKey {
                case bonusAccessUntil = "bonus_access_until"
                case totalMonths = "total_months"
            }
        }
        do {
            let row: BonusRow = try await client
                .from("referral_bonus_access")
                .select("bonus_access_until,total_months")
                .eq("user_id", value: user.id)
                .single()
                .execute()
                .value
            SubscriptionManager.shared.updateReferralBonus(until: row.bonusAccessUntil, months: row.totalMonths)
        } catch {
            SubscriptionManager.shared.updateReferralBonus(until: nil, months: nil)
        }
    }

    func fetchReferralStats() async -> ReferralStats {
        guard case .signedIn = status else { return .empty }
        struct StatsRow: Decodable {
            let totalRewards: Int
            let lastRewardedAt: Date?
            let bonusAccessUntil: Date?
            let totalMonths: Int

            enum CodingKeys: String, CodingKey {
                case totalRewards = "total_rewards"
                case lastRewardedAt = "last_rewarded_at"
                case bonusAccessUntil = "bonus_access_until"
                case totalMonths = "total_months"
            }
        }

        do {
            let row: StatsRow = try await client
                .rpc("get_referral_stats")
                .execute()
                .value
            return ReferralStats(
                totalRewards: row.totalRewards,
                lastRewardedAt: row.lastRewardedAt,
                bonusAccessUntil: row.bonusAccessUntil,
                totalMonths: row.totalMonths
            )
        } catch {
            return .empty
        }
    }

    func dismissInviteToast() {
        inviteToastMessage = nil
        inviteToastIsError = false
    }

    func submitTeamInviteCode(_ code: String) async -> Bool {
        let normalized = normalizeInviteCode(code)
        guard !normalized.isEmpty else { return false }
        cachePendingTeamInviteCode(normalized)

        guard case .signedIn = status else {
            showInviteToast(message: "Invite code saved. Sign in to apply.", isError: false)
            return true
        }

        return await acceptInvite(inviteCode: normalized)
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

    private func handleReferralDeepLink(_ url: URL) async -> Bool {
        guard let code = extractReferralCode(from: url) else { return false }
        cachePendingReferralCode(code)

        switch status {
        case .signedIn:
            _ = await claimPendingReferralIfPossible()
        default:
            showInviteToast(message: "Referral code saved. Sign in to claim.", isError: false)
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

    private func extractReferralCode(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
            ?? components?.queryItems?.first(where: { $0.name == "ref" })?.value
        let trimmed = code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        let isReferralPath = path.contains("dealer-invite") || path.contains("referral")
        let isUniversalHost = host.contains("ezcar24.com")
        let isCustomHost = host.contains("dealer-invite") || host.contains("referral")
        if isReferralPath || isCustomHost || isUniversalHost {
            return trimmed
        }
        return nil
    }

    private func acceptPendingInviteIfPossible() async -> Bool {
        guard let token = pendingInviteToken() else { return false }
        return await acceptInvite(token: token)
    }

    private func acceptPendingTeamInviteCodeIfPossible() async -> Bool {
        guard let code = pendingTeamInviteCodeValue() else { return false }
        return await acceptInvite(inviteCode: code)
    }

    private func claimPendingReferralIfPossible() async -> Bool {
        guard let code = storedReferralCode() else { return false }
        return await claimReferral(code: code)
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

    private func acceptInvite(inviteCode: String) async -> Bool {
        guard !isAcceptingInvite else { return false }
        guard case .signedIn = status else { return false }
        let normalized = normalizeInviteCode(inviteCode)
        guard !normalized.isEmpty else { return false }

        isAcceptingInvite = true
        defer { isAcceptingInvite = false }

        do {
            let _ = try await client
                .functions
                .invoke("accept_invite", options: FunctionInvokeOptions(body: ["invite_code": normalized]))
            clearPendingTeamInviteCode()
            await loadOrganizations()
            showInviteToast(message: "Invite code accepted. Use the switcher to change organizations.", isError: false)
            return true
        } catch {
            let resolved = functionErrorMessage(from: error)
            if shouldClearPendingTeamInviteCode(statusCode: resolved.statusCode, message: resolved.message) {
                clearPendingTeamInviteCode()
            }
            showInviteToast(message: resolved.message, isError: true)
            return false
        }
    }

    private func claimReferral(code: String) async -> Bool {
        guard case .signedIn = status else { return false }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return false }

        do {
            let params: [String: AnyJSON] = [
                "p_code": .string(trimmed)
            ]
            let result: Bool = try await client
                .rpc("claim_dealer_referral", params: params)
                .execute()
                .value
            if result {
                clearPendingReferralCode()
                showInviteToast(message: "Referral applied. Thanks for joining.", isError: false)
            } else {
                showInviteToast(message: "Referral already used.", isError: true)
            }
            return result
        } catch {
            let message = localized(error)
            if shouldClearPendingReferralCode(message: message) {
                clearPendingReferralCode()
            }
            showInviteToast(message: message, isError: true)
            return false
        }
    }

    private func cachePendingInviteToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: pendingInviteTokenKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: pendingInviteTokenTimestampKey)
    }

    private func cachePendingTeamInviteCode(_ code: String) {
        let normalized = normalizeInviteCode(code)
        guard !normalized.isEmpty else { return }
        pendingTeamInviteCode = normalized
        UserDefaults.standard.set(normalized, forKey: pendingTeamInviteCodeKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: pendingTeamInviteCodeTimestampKey)
    }

    private func cachePendingReferralCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return }
        pendingReferralCode = trimmed
        UserDefaults.standard.set(trimmed, forKey: pendingReferralCodeKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: pendingReferralCodeTimestampKey)
    }

    private func dealerReferralCodeKey(for dealerId: UUID) -> String {
        dealerReferralCodeKeyPrefix + dealerId.uuidString
    }

    private func cachedDealerReferralCode(dealerId: UUID) -> String? {
        UserDefaults.standard.string(forKey: dealerReferralCodeKey(for: dealerId))
    }

    private func cacheDealerReferralCode(_ code: String, dealerId: UUID) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: dealerReferralCodeKey(for: dealerId))
    }

    private func fetchExistingDealerReferralCode(dealerId: UUID) async -> String? {
        struct CodeRow: Decodable {
            let code: String
        }
        do {
            let rows: [CodeRow] = try await client
                .from("dealer_referral_codes")
                .select("code")
                .eq("dealer_id", value: dealerId)
                .eq("is_active", value: true)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            return rows.first?.code
        } catch {
            print("fetchExistingDealerReferralCode error: \(error)")
            return nil
        }
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

    private func pendingTeamInviteCodeValue() -> String? {
        if let cached = pendingTeamInviteCode, !cached.isEmpty {
            return cached
        }
        guard let code = SessionStore.readPendingTeamInviteCode(
            key: pendingTeamInviteCodeKey,
            timestampKey: pendingTeamInviteCodeTimestampKey
        ) else { return nil }
        pendingTeamInviteCode = code
        return code
    }

    private func storedReferralCode() -> String? {
        if let cached = pendingReferralCode, !cached.isEmpty {
            return cached
        }
        guard let code = UserDefaults.standard.string(forKey: pendingReferralCodeKey) else { return nil }
        let timestamp = UserDefaults.standard.object(forKey: pendingReferralCodeTimestampKey) as? Double
        guard let timestamp else {
            clearPendingReferralCode()
            return nil
        }
        let maxAge: TimeInterval = 30 * 24 * 60 * 60
        if Date().timeIntervalSince1970 - timestamp > maxAge {
            clearPendingReferralCode()
            return nil
        }
        pendingReferralCode = code
        return code
    }

    private func clearPendingInviteToken() {
        UserDefaults.standard.removeObject(forKey: pendingInviteTokenKey)
        UserDefaults.standard.removeObject(forKey: pendingInviteTokenTimestampKey)
    }

    private func clearPendingTeamInviteCode() {
        pendingTeamInviteCode = nil
        UserDefaults.standard.removeObject(forKey: pendingTeamInviteCodeKey)
        UserDefaults.standard.removeObject(forKey: pendingTeamInviteCodeTimestampKey)
    }

    private func clearPendingReferralCode() {
        pendingReferralCode = nil
        UserDefaults.standard.removeObject(forKey: pendingReferralCodeKey)
        UserDefaults.standard.removeObject(forKey: pendingReferralCodeTimestampKey)
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

    private func shouldClearPendingTeamInviteCode(statusCode: Int?, message: String) -> Bool {
        if let code = statusCode, (400..<500).contains(code) {
            return true
        }
        let lower = message.lowercased()
        return lower.contains("invalid") ||
            lower.contains("expired") ||
            lower.contains("already") ||
            lower.contains("revoked") ||
            lower.contains("mismatch")
    }

    private func shouldClearPendingReferralCode(message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("invalid") ||
            lower.contains("expired") ||
            lower.contains("self") ||
            lower.contains("not allowed")
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
        case .initialSession, .tokenRefreshed, .signedIn:
            // During password recovery we intentionally block automatic sign-in
            guard !isPasswordRecoverySessionActive else { return }
            if let session {
                handleAccountChangeIfNeeded(newUserId: session.user.id)
                status = .signedIn(user: session.user)
                errorMessage = nil
                Task {
                    await CloudSyncManager.shared?.syncCurrentUserProfile(user: session.user)
                }
            } else {
                status = .signedOut
                errorMessage = nil
            }
        case .userUpdated:
            guard !isPasswordRecoverySessionActive else { return }
            if let session {
                handleAccountChangeIfNeeded(newUserId: session.user.id)
                status = .signedIn(user: session.user)
                errorMessage = nil
                Task {
                    await CloudSyncManager.shared?.syncCurrentUserProfile(user: session.user)
                }
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
        pendingReferralCode = nil
        pendingTeamInviteCode = nil
        clearPendingReferralCode()
        clearPendingTeamInviteCode()
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

    private func normalizeInviteCode(_ code: String) -> String {
        code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func readPendingTeamInviteCode(key: String, timestampKey: String) -> String? {
        guard let code = UserDefaults.standard.string(forKey: key) else { return nil }
        let timestamp = UserDefaults.standard.object(forKey: timestampKey) as? Double
        guard let timestamp else {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.removeObject(forKey: timestampKey)
            return nil
        }
        let maxAge: TimeInterval = 7 * 24 * 60 * 60
        if Date().timeIntervalSince1970 - timestamp > maxAge {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.removeObject(forKey: timestampKey)
            return nil
        }
        return code
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
