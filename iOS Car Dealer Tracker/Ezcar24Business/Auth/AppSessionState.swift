import Foundation

@MainActor
final class AppSessionState: ObservableObject {
    enum Mode: Hashable {
        case signIn
        case signUp
    }

    @Published var isGuestMode: Bool = false
    @Published var email: String = "" {
        didSet { recalculateValidation() }
    }

    @Published var phone: String = ""
    @Published var referralCode: String = ""
    @Published var teamInviteCode: String = ""

    @Published var password: String = "" {
        didSet { recalculateValidation() }
    }

    @Published var mode: Mode = .signIn
    @Published var isProcessing: Bool = false
    @Published private(set) var isFormValid: Bool = false

    private let sessionStore: SessionStore

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
        self.referralCode = sessionStore.pendingReferralCode ?? ""
        self.teamInviteCode = sessionStore.pendingTeamInviteCode ?? ""
        recalculateValidation()
    }

    func authenticate() async {
        guard isFormValid else { return }
        let submittedMode = mode
        let submittedProperties = analyticsProperties(for: submittedMode)
        OnboardingAnalytics.capture(.authSubmitted, properties: submittedProperties)
        isProcessing = true
        defer { isProcessing = false }
        sessionStore.resetError()

        do {
            let inviteCodeValue = trimmedTeamInviteCode.isEmpty ? nil : trimmedTeamInviteCode
            switch mode {
            case .signIn:
                try await sessionStore.signIn(email: trimmedEmail, password: password)
            case .signUp:
                let phoneValue = trimmedPhone.isEmpty ? nil : trimmedPhone
                let codeValue = trimmedReferralCode.isEmpty ? nil : trimmedReferralCode
                try await sessionStore.signUp(email: trimmedEmail, password: password, phone: phoneValue, referralCode: codeValue, teamInviteCode: inviteCodeValue)
            }
            if let inviteCodeValue {
                _ = await sessionStore.submitTeamInviteCode(inviteCodeValue)
            }
            isGuestMode = false
            if case .signedIn(let user) = sessionStore.status {
                OnboardingAnalytics.identifyUser(user.id)
                OnboardingAnalytics.capture(.authCompleted, properties: submittedProperties)
            } else {
                OnboardingAnalytics.capture(.authPendingConfirmation, properties: submittedProperties)
            }
            clearSensitiveFields()
        } catch {
            OnboardingAnalytics.capture(.authFailed, properties: submittedProperties)
        }
    }

    private func recalculateValidation() {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        isFormValid = !trimmed.isEmpty && password.count >= 6
    }

    func startGuestMode() {
        OnboardingAnalytics.resetIdentity()
        isGuestMode = true
        mode = .signIn
        email = ""
        password = ""
        phone = ""
        referralCode = ""
        teamInviteCode = ""
        SubscriptionManager.shared.logOut()
        OnboardingAnalytics.capture(.guestStarted)
    }

    func exitGuestModeForLogin() {
        isGuestMode = false
        mode = .signIn
        phone = ""
        teamInviteCode = ""
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPhone: String {
        phone.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearSensitiveFields() {
        password = ""
        phone = ""
        referralCode = ""
        teamInviteCode = ""
    }

    private var trimmedReferralCode: String {
        referralCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTeamInviteCode: String {
        teamInviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func analyticsProperties(for mode: Mode) -> [String: Any] {
        [
            "auth_mode": mode.analyticsName,
            "auth_method": "email",
            "has_referral_code": !trimmedReferralCode.isEmpty,
            "has_team_invite_code": !trimmedTeamInviteCode.isEmpty,
            "has_phone": !trimmedPhone.isEmpty
        ]
    }
}

extension AppSessionState.Mode {
    var analyticsName: String {
        switch self {
        case .signIn: return "sign_in"
        case .signUp: return "sign_up"
        }
    }
}
