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
                try await sessionStore.signUp(email: trimmedEmail, password: password, phone: phoneValue, referralCode: codeValue)
            }
            if let inviteCodeValue {
                _ = await sessionStore.submitTeamInviteCode(inviteCodeValue)
            }
            isGuestMode = false
            clearSensitiveFields()
        } catch {
            // Error already handled in sessionStore
        }
    }

    private func recalculateValidation() {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        isFormValid = !trimmed.isEmpty && password.count >= 6
    }

    func startGuestMode() {
        isGuestMode = true
        mode = .signIn
        email = ""
        password = ""
        phone = ""
        referralCode = ""
        teamInviteCode = ""
        // Drop any cached RevenueCat state so guests never inherit a previous user's subscription
        SubscriptionManager.shared.logOut()
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
}
