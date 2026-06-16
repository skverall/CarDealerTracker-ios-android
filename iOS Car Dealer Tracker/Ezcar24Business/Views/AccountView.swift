import SwiftUI
import UIKit
import Supabase

struct AccountView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSessionState: AppSessionState
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var permissionService = PermissionService.shared
    @State private var isSigningOut = false
    @State private var isSyncing = false
    @State private var syncComplete = false
    @State private var showingLogin = false
    @State private var presentedPaywallMode: PaywallMode?
    @State private var showingDeleteAlert = false
    @State private var dedupState: DedupState = .idle
    @AppStorage(NotificationPreference.enabledKey) private var notificationsEnabled = false
    @AppStorage(NotificationPreference.inventoryStaleThresholdKey) private var inventoryStaleThreshold = NotificationPreference.defaultInventoryStaleThreshold
    @State private var showNotificationSettingsAlert = false
    @State private var notificationAlertMessage = ""
    @State private var showMailError = false
    @State private var inviteSharePayload: InviteSharePayload?
    @State private var referralCode: String?
    @State private var isFetchingReferralCode = false
    @State private var inviteAlertMessage: String?
    @State private var showingJoinTeamByCodeSheet = false

    private struct InviteSharePayload: Identifiable {
        let id = UUID()
        let items: [Any]
    }

    private var inviteAlertBinding: Binding<Bool> {
        Binding(
            get: { inviteAlertMessage != nil },
            set: { if !$0 { inviteAlertMessage = nil } }
        )
    }

    fileprivate enum DedupState: Equatable {
        case idle
        case running
        case success
        case error(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorTheme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        accountHeader

                        subscriptionCard

                        if shouldShowFeedbackBoardPrompt {
                            feedbackBoardPromptCard
                        }

                        referralCard

                        // MARK: - General Settings
                        generalSettingsSection
                        
                        // MARK: - Management & Data
                        managementDataSection
                        
                        // MARK: - Security
                        securitySection
                        
                        // MARK: - Support
                        supportSection
                        
                        // MARK: - Legal
                        legalSection
                        
                        // MARK: - Sign Out
                        signOutButton
                        
                        // MARK: - Version
                        appVersionView
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 700 : .infinity)
                }
            }
            .navigationTitle("account".localizedString)
            .sheet(item: $presentedPaywallMode) { mode in
                PaywallView(mode: mode)
            }
            .sheet(item: $inviteSharePayload) { payload in
                ShareSheet(items: payload.items)
            }
            .sheet(isPresented: $showingJoinTeamByCodeSheet) {
                JoinTeamByCodeSheet()
                    .environmentObject(sessionStore)
            }
            .alert("invite_dealer".localizedString, isPresented: inviteAlertBinding) {
                Button("OK") {
                    inviteAlertMessage = nil
                }
            } message: {
                Text(inviteAlertMessage ?? "")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.system(size: 24))
                    }
                }
            }
            .sheet(isPresented: $showingLogin) {
                LoginView(
                    isGuest: Binding(
                        get: { appSessionState.isGuestMode },
                        set: { appSessionState.isGuestMode = $0 }
                    )
                )
            }
            .onChange(of: sessionStore.status) { _, newStatus in
                if case .signedIn = newStatus {
                    showingLogin = false
                }
            }
            .onChange(of: notificationsEnabled) { _, newValue in
                Task {
                    await handleNotificationsToggle(isEnabled: newValue)
                }
            }
            .onChange(of: inventoryStaleThreshold) { _, _ in
                guard notificationsEnabled else { return }
                Task {
                    await LocalNotificationManager.shared.refreshAll(context: viewContext)
                }
            }
            .alert("notifications".localizedString, isPresented: $showNotificationSettingsAlert) {
                Button("open_settings".localizedString) {
                    LocalNotificationManager.shared.openSystemSettings()
                }
                Button("cancel".localizedString, role: .cancel) { }
            } message: {
                Text(notificationAlertMessage)
            }

            .overlay(alignment: .top) {
                if dedupState != .idle {
                    StatusBanner(state: dedupState)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut, value: dedupState)
                        .padding(.top, 8)
                }
            }
            .alert("contact_developer".localizedString, isPresented: $showMailError) {
                Button("copy_email".localizedString) {
                    UIPasteboard.general.string = "aydmaxx@gmail.com"
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text(String(format: "mail_error_message".localizedString, "aydmaxx@gmail.com"))
            }
        }
        .preferredColorScheme(regionSettings.selectedTheme.colorScheme)
        .environment(\.colorScheme, regionSettings.selectedTheme.colorScheme)
    }
    
    private var generalSettingsSection: some View {
        menuSection(title: "settings".localizedKey) {
            NavigationLink {
                RegionLanguageSettingsView()
            } label: {
                MenuRow(icon: "globe", title: "region_language".localizedKey, color: .indigo)
            }

            themeToggleRow
            
            Divider().padding(.leading, 52)
            notificationsRow
            
            partsToggleRow

            if permissionService.can(.viewFinancials) {
                Divider().padding(.leading, 52)
                NavigationLink {
                    HoldingCostSettingsView()
                } label: {
                    MenuRow(icon: "flame.fill", title: "holding_cost_settings".localizedKey, color: .orange)
                }
            }

            if permissionService.can(.createSale) || permissionService.currentRole == "owner" || permissionService.currentRole == "admin" {
                Divider().padding(.leading, 52)
                NavigationLink {
                    DealDeskSettingsView()
                } label: {
                    MenuRow(icon: "doc.text.magnifyingglass", title: LocalizedStringKey("Deal Desk"), color: .blue)
                }
            }
            
            if permissionService.currentRole == "owner" || permissionService.currentRole == "admin" {
                Divider().padding(.leading, 52)
                NavigationLink {
                    FinancialAccountsView()
                } label: {
                    MenuRow(icon: "banknote", title: "financial_accounts".localizedKey, color: .green)
                }
            }
        }
    }
    
    private var managementDataSection: some View {
        Group {
            if showManagementSection {
                menuSection(title: "management".localizedKey) {
                    if permissionService.can(.manageTeam) {
                        NavigationLink {
                            TeamManagementView()
                        } label: {
                            MenuRow(icon: "person.2.fill", title: "team_members".localizedKey, color: .blue)
                        }
                        Divider().padding(.leading, 52)
                    }

                    if MonthlyReportSettingsViewModel.canAccess(role: permissionService.currentRole) {
                        NavigationLink {
                            MonthlyReportSettingsView()
                        } label: {
                            MenuRow(icon: "envelope.badge.fill", title: LocalizedStringKey("Email Reports"), color: .indigo)
                        }
                        Divider().padding(.leading, 52)
                    }

                    if permissionService.currentRole == "owner" {
                        NavigationLink {
                            BackupCenterView()
                        } label: {
                            MenuRow(icon: "externaldrive.badge.checkmark", title: "backup_export".localizedKey, color: .orange)
                        }
                        Divider().padding(.leading, 52)
                    }

                    NavigationLink {
                        DataHealthView()
                    } label: {
                        MenuRow(icon: "stethoscope", title: "data_health".localizedKey, color: .teal)
                    }
                    Divider().padding(.leading, 52)

                    if permissionService.can(.manageTeam) { // Admin/Owner
                        Button {
                            Task {
                                await runDeduplication()
                            }
                        } label: {
                            MenuRow(icon: "arrow.triangle.merge", title: "clean_up_duplicates".localizedKey, color: .purple)
                        }
                        Divider().padding(.leading, 52)
                    }
                    
                    syncRow
                }
            } else {
                menuSection(title: "sync".localizedKey) {
                    NavigationLink {
                        DataHealthView()
                    } label: {
                        MenuRow(icon: "stethoscope", title: "data_health".localizedKey, color: .teal)
                    }
                    Divider().padding(.leading, 52)
                    syncRow
                }
            }
        }
    }
    
    private var securitySection: some View {
        menuSection(title: "security".localizedKey) {
            NavigationLink {
                ChangePasswordView()
            } label: {
                MenuRow(icon: "lock.rotation", title: "change_password".localizedKey, color: .purple)
            }
            
            if permissionService.currentRole == "owner" {
                Divider().padding(.leading, 52)
                NavigationLink {
                    DeleteAccountView()
                } label: {
                    MenuRow(icon: "trash", title: "delete_account".localizedKey, color: .red)
                }
            }
        }
    }
    
    private var supportSection: some View {
        menuSection(title: "support_section".localizedKey) {
            NavigationLink {
                FeedbackBoardView()
            } label: {
                MenuRow(icon: "lightbulb.fill", title: "feedback_board_title".localizedKey, color: .orange)
            }
            Divider().padding(.leading, 52)
            Button {
                sendSupportEmail()
            } label: {
                MenuRow(icon: "envelope.fill", title: "contact_developer".localizedKey, color: .blue)
            }
        }
    }
    
    private var legalSection: some View {
        menuSection(title: "legal".localizedKey) {
            Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                MenuRow(icon: "doc.text", title: "terms_of_use".localizedKey, color: .gray)
            }
            Divider().padding(.leading, 52)
            Link(destination: URL(string: "https://www.ezcar24.com/en/privacy-policy")!) {
                MenuRow(icon: "hand.raised.fill", title: "privacy_policy".localizedKey, color: .gray)
            }
            Divider().padding(.leading, 52)
            NavigationLink {
                UserGuideView()
            } label: {
                MenuRow(icon: "book.closed", title: "user_guide".localizedKey, color: .gray)
            }
        }
    }
    
    private var signOutButton: some View {
        Button(action: signOut) {
            HStack {
                Text("sign_out".localizedString)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if isSyncing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.red)
                        Text("syncing".localizedString)
                            .font(.caption)
                    }
                } else if syncComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                } else if isSigningOut || sessionStore.isAuthenticating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.red)
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
            }
            .foregroundColor(.red)
            .padding()
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .disabled(isSigningOut || sessionStore.isAuthenticating || isSyncing)
        .padding(.bottom, 20)
    }
    
    private var showManagementSection: Bool {
        permissionService.can(.manageTeam) || permissionService.currentRole == "owner"
    }

    private var shouldShowFeedbackBoardPrompt: Bool {
        if case .signedIn = sessionStore.status { return true }
        return false
    }

    private var feedbackBoardPromptCard: some View {
        NavigationLink {
            FeedbackBoardView()
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(ColorTheme.accent.opacity(0.14))
                            .frame(width: 48, height: 48)

                        Image(systemName: "lightbulb.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(ColorTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text("feedback_board_prompt_title".localizedString)
                                .font(.headline.weight(.bold))
                                .foregroundColor(ColorTheme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("new_badge".localizedString)
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(ColorTheme.accent)
                                .clipShape(Capsule())
                        }

                        Text("feedback_board_prompt_subtitle".localizedString)
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                HStack {
                    Text("feedback_board_open".localizedString)
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundColor(ColorTheme.primary)
            }
            .padding(18)
            .background(ColorTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(ColorTheme.accent.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.hapticScale)
    }


    @ViewBuilder
    private var accountHeader: some View {
        VStack(spacing: 0) {
            if case .signedIn(let authUser) = sessionStore.status {
                AccountUserProfileView(
                    userId: authUser.id,
                    authEmail: authUser.email,
                    authPendingEmail: sessionStore.pendingEmailChange
                )
            } else {
                VStack(spacing: 12) {
                    Text("not_signed_in".localizedString)
                        .font(.headline)
                        .foregroundColor(ColorTheme.secondaryText)
                    
                    Button("sign_in".localizedString) {
                        appSessionState.exitGuestModeForLogin()
                        showingLogin = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ColorTheme.primary)
                    .controlSize(.regular)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 20)
            }
        }
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    @ViewBuilder
    private var subscriptionCard: some View {
        Button {
            openSubscriptionDestination()
        } label: {
            if subscriptionManager.isProAccessActive {
                activeSubscriptionCard
            } else {
                freeSubscriptionCard
            }
        }
        .buttonStyle(.hapticScale)
    }

    private var freeSubscriptionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 50, height: 50)

                    Image(systemName: "crown.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("free_plan".localizedString)
                        .font(.headline.weight(.bold))
                        .foregroundColor(.white)

                    Text("upgrade_to_unlock".localizedString)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text("upgrade".localizedString)
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }
            .font(.headline.weight(.bold))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(Capsule())
            .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .padding(20)
        .background(
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.1)
                
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 150)
                    .blur(radius: 40)
                    .offset(x: 80, y: -40)
                
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 150)
                    .blur(radius: 40)
                    .offset(x: -80, y: 40)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.0), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 8)
    }

    private var activeSubscriptionCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 50, height: 50)

                Image(systemName: "crown.fill")
                    .foregroundColor(.white)
                    .font(.title3)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("dealer_pro".localizedString)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)

                if let expirationDate = subscriptionManager.expirationDate {
                    let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0

                    if daysRemaining <= 7 {
                        Text(String(format: "subscription_ends_in_days".localizedString, max(0, daysRemaining)))
                            .font(.caption.weight(.medium))
                            .foregroundColor(.orange)
                    } else {
                        Text(String(format: "subscription_active_until".localizedString, expirationDate.formatted(date: .numeric, time: .omitted)))
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                } else {
                    Text("active_subscription".localizedString)
                        .font(.caption.weight(.medium))
                        .foregroundColor(Color(red: 0.16, green: 0.8, blue: 0.4))
                }
            }

            Spacer()

            ProManageCallToAction(title: "manage".localizedString)
        }
        .padding(20)
        .background(
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.1)
                
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 150)
                    .blur(radius: 40)
                    .offset(x: 80, y: -40)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.0), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 8)
    }

    private struct ProManageCallToAction: View {
        let title: String
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isAnimating = false

        var body: some View {
            HStack(spacing: 7) {
                Text(title)
                    .font(.subheadline.weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
            }
            .foregroundColor(ColorTheme.primary)
            .padding(.horizontal, 17)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white,
                                ColorTheme.warning.opacity(0.55),
                                Color.white
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(shimmerOverlay.clipShape(Capsule()))
            .overlay(
                Capsule()
                    .stroke(ColorTheme.accent.opacity(0.35), lineWidth: 1)
            )
            .shadow(
                color: ColorTheme.accent.opacity(canAnimate && isAnimating ? 0.42 : 0.22),
                radius: canAnimate && isAnimating ? 16 : 8,
                x: 0,
                y: 5
            )
            .scaleEffect(canAnimate && isAnimating ? 1.045 : 1)
            .onAppear {
                isAnimating = true
            }
            .animation(canAnimate ? .easeInOut(duration: 1.15).repeatForever(autoreverses: true) : .snappy(duration: 0.2), value: isAnimating)
        }

        private var canAnimate: Bool {
            !reduceMotion
        }

        @ViewBuilder
        private var shimmerOverlay: some View {
            if canAnimate {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.80),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(32, proxy.size.width * 0.35), height: proxy.size.height * 1.7)
                    .rotationEffect(.degrees(18))
                    .offset(x: isAnimating ? proxy.size.width * 1.2 : -proxy.size.width * 0.55)
                    .animation(.linear(duration: 1.9).repeatForever(autoreverses: false), value: isAnimating)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func openSubscriptionDestination() {
        if subscriptionManager.isProAccessActive {
            presentedPaywallMode = .manage
        } else {
            if case .signedIn = sessionStore.status {
                presentedPaywallMode = .upgrade
            } else {
                appSessionState.exitGuestModeForLogin()
                showingLogin = true
            }
        }
    }

    @ViewBuilder
    private var referralCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ColorTheme.purple.opacity(0.12))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "gift.fill")
                        .font(.title3)
                        .foregroundColor(ColorTheme.purple)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("invite_dealer".localizedString)
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText)
                    
                    Text("invite_dealer_subtitle".localizedString)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
            .padding(16)
            
            if let bonusUntil = subscriptionManager.bonusAccessUntil, bonusUntil > Date() {
                Text(String(format: "referral_bonus_until".localizedString, bonusUntil.formatted(date: .numeric, time: .omitted)))
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if let code = referralCode {
                HStack {
                    Text(code)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(ColorTheme.primaryText)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(ColorTheme.secondaryBackground)
                        .cornerRadius(6)
                    Spacer()
                    Button("copy".localizedString) {
                        UIPasteboard.general.string = code
                    }
                    .font(.footnote.weight(.bold))
                    .foregroundColor(ColorTheme.primary)
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
            }

            Button {
                Task { await shareDealerInvite() }
            } label: {
                HStack(spacing: 8) {
                    if isFetchingReferralCode {
                        ProgressView()
                            .tint(ColorTheme.primary)
                    }
                    Text("invite_dealer".localizedString)
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(ColorTheme.primary.opacity(0.08))
                .foregroundColor(ColorTheme.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(ColorTheme.primary.opacity(0.14), lineWidth: 1)
                )
            }
            .buttonStyle(.hapticScale)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .disabled(isFetchingReferralCode)
            
            Divider()
            
            NavigationLink {
                ReferralStatsView()
            } label: {
                HStack {
                    Text("referral_view_stats".localizedString)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.primaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundColor(ColorTheme.tertiaryText)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Divider().padding(.leading, 16)
            
            Button {
                showingJoinTeamByCodeSheet = true
            } label: {
                HStack {
                    Text("Join Team by Code")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.primaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundColor(ColorTheme.tertiaryText)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    private func menuSection<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .textCase(.uppercase)
                .foregroundColor(ColorTheme.secondaryText)
                .padding(.leading, 8)
            
            VStack(spacing: 0) {
                content()
            }
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
        }
    }
    
    private var syncRow: some View {
        VStack(spacing: 0) {
             Button {
                Task { await runManualSync() }
            } label: {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 36, height: 36)
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("sync_now".localizedString)
                            .font(.body)
                            .foregroundColor(ColorTheme.primaryText)
                        
                        Text(String(format: "last_sync".localizedString, lastSyncText))
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                    
                    Spacer()
                    
                    if cloudSyncManager.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(ColorTheme.tertiaryText)
                    }
                }
                .padding(16)
            }
            .disabled(cloudSyncManager.isSyncing)
        }
    }
    
    private var notificationsRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("notifications".localizedString)
                        .font(.body)
                        .foregroundColor(ColorTheme.primaryText)
                    Text("clients_and_debts".localizedString)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }

                Spacer()

                Toggle("", isOn: $notificationsEnabled)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .orange))
            }
            .padding(16)
            
            if notificationsEnabled {
                Divider().padding(.leading, 52)
                
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.1))
                            .frame(width: 36, height: 36)
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("inventory_alert_threshold".localizedString)
                            .font(.body)
                            .foregroundColor(ColorTheme.primaryText)
                        Text("inventory_alert_threshold_hint".localizedString)
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("\(inventoryStaleThreshold) " + "days".localizedString)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ColorTheme.primaryText)
                        
                        Stepper("", value: $inventoryStaleThreshold, in: 10...120, step: 5)
                            .labelsHidden()
                    }
                }
                .padding(16)
            }
        }
    }

    private var themeToggleRow: some View {
        VStack(spacing: 0) {
            Divider().padding(.leading, 52)

            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                regionSettings.selectedTheme = regionSettings.selectedTheme == .light ? .dark : .light
            } label: {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(ColorTheme.primary.opacity(0.1))
                            .frame(width: 36, height: 36)
                        Image(systemName: regionSettings.selectedTheme == .light ? "sun.max.fill" : "moon.fill")
                            .font(.system(size: 16))
                            .foregroundColor(ColorTheme.primary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("appearance_theme".localizedString)
                            .font(.body)
                            .foregroundColor(ColorTheme.primaryText)
                        Text(regionSettings.selectedTheme.displayName)
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                    }

                    Spacer()

                    Text(regionSettings.selectedTheme == .light ? "theme_dark".localizedString : "theme_light".localizedString)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(ColorTheme.primary.opacity(0.12))
                        .clipShape(Capsule())
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var partsToggleRow: some View {
        VStack(spacing: 0) {
            Divider().padding(.leading, 52)
            
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "shippingbox")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("parts_tab_title".localizedString)
                        .font(.body)
                        .foregroundColor(ColorTheme.primaryText)
                }

                Spacer()

                Toggle("", isOn: $regionSettings.isPartsEnabled)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .orange))
            }
            .padding(16)
        }
    }

    private var userInitials: String {
        if case .signedIn(let user) = sessionStore.status, let email = user.email {
            return String(email.prefix(2)).uppercased()
        }
        return "??"
    }
    
    private var lastSyncText: String {
        if let date = cloudSyncManager.lastSyncAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return "never".localizedString
    }
    
    private var appVersionView: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        
        return Text("Car Dealer Tracker v\(version) (\(build))")
            .font(.caption2)
            .foregroundColor(ColorTheme.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, -10)
            .padding(.bottom, 20)
    }

    private func signOut() {
        guard !isSigningOut else { return }
        Task {
            await MainActor.run { isSyncing = true; syncComplete = false }
            if case .signedIn(let user) = sessionStore.status {
                let dealerId = CloudSyncEnvironment.currentDealerId ?? user.id
                await cloudSyncManager.processOfflineQueue(dealerId: dealerId)
            }
            await MainActor.run { isSyncing = false; syncComplete = true }
             try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run { isSigningOut = true }
            await sessionStore.signOut()
            await MainActor.run {
                appSessionState.mode = .signIn
                appSessionState.email = ""; appSessionState.password = ""; appSessionState.phone = ""
                isSigningOut = false
                syncComplete = false
            }
        }
    }

    private func deleteAccount() {
        Task {
            do {
                try await sessionStore.deleteAccount()
                await MainActor.run {
                    appSessionState.mode = .signIn
                    appSessionState.email = ""; appSessionState.password = ""; appSessionState.phone = ""
                }
            } catch {
                print("Error deleting account: \(error)")
            }
        }
    }

    private func shareDealerInvite() async {
        guard case .signedIn = sessionStore.status else {
            await MainActor.run { inviteAlertMessage = "referral_invite_requires_sign_in".localizedString }
            return
        }
        guard let dealerId = await sessionStore.resolveDealerIdForReferral() else {
            await MainActor.run {
                inviteAlertMessage = "referral_invite_missing_organization".localizedString
            }
            return
        }
        await MainActor.run { isFetchingReferralCode = true }
        let code = await sessionStore.getDealerReferralCode(dealerId: dealerId)
        await MainActor.run {
            isFetchingReferralCode = false
            referralCode = code
        }
        guard let code else {
            await MainActor.run {
                inviteAlertMessage = "referral_invite_generation_failed".localizedString
            }
            return
        }

        let link = "https://ezcar24.com/?ref=\(code)"
        let message = String(format: "referral_invite_share_message".localizedString, code)
        var items: [Any] = [message]
        if let url = URL(string: link) {
            let icon = UIImage(systemName: "car.fill")
            let source = ShareLinkItemSource(url: url, title: "referral_invite_share_title".localizedString, icon: icon)
            items.append(source)
        }
        await MainActor.run {
            inviteSharePayload = InviteSharePayload(items: items)
        }
    }
    
    @MainActor
    private func runDeduplication() async {
        guard case .signedIn(let user) = sessionStore.status else { return }
        dedupState = .running
        do {
            let dealerId = CloudSyncEnvironment.currentDealerId ?? user.id
            try await cloudSyncManager.deduplicateData(dealerId: dealerId)
            dedupState = .success
        } catch {
            dedupState = .error(error.localizedDescription)
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        dedupState = .idle
    }
    
    @MainActor
    private func runManualSync() async {
        guard case .signedIn(let user) = sessionStore.status else {
            appSessionState.exitGuestModeForLogin()
            showingLogin = true
            return
        }
        await cloudSyncManager.fullSync(user: user)
    }
    
    private func handleNotificationsToggle(isEnabled: Bool) async {
        if isEnabled {
            let granted = await LocalNotificationManager.shared.requestAuthorization()
            if granted {
                await LocalNotificationManager.shared.refreshAll(context: viewContext)
            } else {
                await MainActor.run {
                    notificationsEnabled = false
                    notificationAlertMessage = "enable_notifications_alert".localizedString
                    showNotificationSettingsAlert = true
                }
            }
        } else {
            await LocalNotificationManager.shared.clearAll()
        }
    }

    private func sendSupportEmail() {
        let email = "aydmaxx@gmail.com"
        let subject = "support_email_subject".localizedString
        
        // Gather device info
        let deviceModel = UIDevice.current.model
        let systemName = UIDevice.current.systemName
        let systemVersion = UIDevice.current.systemVersion
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        
        var userIdString = "Not Signed In"
        if case .signedIn(let user) = sessionStore.status {
            userIdString = user.id.uuidString
        }
        
        let body = """
        
        -----------------------------
        Please write your feedback above this line.
        
        Device: \(deviceModel)
        OS: \(systemName) \(systemVersion)
        App Version: \(appVersion) (\(buildNumber))
        User ID: \(userIdString)
        """
        
        // Encode URL components safely
        if let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "mailto:\(email)?subject=\(subjectEncoded)&body=\(bodyEncoded)") {
            
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                // Fallback or alert if Mail app is not configured?
                // For now, simpler is usually better; if they don't have mail, they can't email.
                print("Cannot open mail URL")
                showMailError = true
            }
        }
    }
}

// MARK: - Subviews
struct FeedbackBoardView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSessionState: AppSessionState
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @State private var requests: [AppFeedbackRequest] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingComposer = false
    @State private var showingLogin = false
    @State private var isSubmittingFeedback = false
    @State private var composerError: String?
    @State private var togglingVotes: Set<UUID> = []
    @State private var deletingRequests: Set<UUID> = []
    @State private var updatingStatuses: Set<UUID> = []
    @State private var requestPendingDeletion: AppFeedbackRequest?

    var body: some View {
        ZStack {
            ColorTheme.background.ignoresSafeArea()

            if isSignedIn {
                feedbackContent
            } else {
                signInRequiredView
            }
        }
        .navigationTitle("feedback_board_title".localizedString)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSignedIn {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        Task { await loadFeedback() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)

                    Button {
                        composerError = nil
                        showingComposer = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
        }
        .task {
            if isSignedIn, requests.isEmpty {
                await loadFeedback()
            }
        }
        .onChange(of: sessionStore.status) { _, _ in
            if isSignedIn {
                Task { await loadFeedback() }
            }
        }
        .sheet(isPresented: $showingComposer) {
            FeedbackComposerSheet(
                isSubmitting: isSubmittingFeedback,
                errorMessage: composerError,
                onSubmit: { title, details in
                    Task {
                        await submitFeedback(title: title, details: details)
                    }
                }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingLogin) {
            LoginView(
                isGuest: Binding(
                    get: { appSessionState.isGuestMode },
                    set: { appSessionState.isGuestMode = $0 }
                )
            )
        }
        .confirmationDialog(
            "feedback_delete_title".localizedString,
            isPresented: Binding(
                get: { requestPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        requestPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("delete".localizedString, role: .destructive) {
                if let request = requestPendingDeletion {
                    requestPendingDeletion = nil
                    Task { await deleteRequest(request.id) }
                }
            }
            Button("cancel".localizedString, role: .cancel) {}
        } message: {
            Text("feedback_delete_message".localizedString)
        }
        .preferredColorScheme(regionSettings.selectedTheme.colorScheme)
        .environment(\.colorScheme, regionSettings.selectedTheme.colorScheme)
    }

    private var isSignedIn: Bool {
        if case .signedIn = sessionStore.status { return true }
        return false
    }

    private var openFeedbackCount: Int {
        requests.filter { $0.status != "shipped" }.count
    }

    private var completedFeedbackCount: Int {
        requests.filter { $0.status == "shipped" }.count
    }

    private var openFeedbackRequests: [AppFeedbackRequest] {
        requests.filter { $0.status != "shipped" }
    }

    private var completedFeedbackRequests: [AppFeedbackRequest] {
        requests.filter { $0.status == "shipped" }
    }

    @ViewBuilder
    private var feedbackContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                FeedbackBoardIntroCard(
                    openCount: openFeedbackCount,
                    completedCount: completedFeedbackCount
                )

                FeedbackAddIdeaBar {
                    composerError = nil
                    showingComposer = true
                }

                if let errorMessage {
                    FeedbackStateCard(
                        icon: "exclamationmark.triangle.fill",
                        title: "feedback_load_failed".localizedString,
                        message: errorMessage,
                        actionTitle: "try_again".localizedString,
                        color: ColorTheme.danger,
                        action: {
                            Task { await loadFeedback() }
                        }
                    )
                }

                if isLoading && requests.isEmpty {
                    ProgressView("loading".localizedString)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                } else if requests.isEmpty && errorMessage == nil {
                    FeedbackStateCard(
                        icon: "sparkles",
                        title: "feedback_empty_title".localizedString,
                        message: "feedback_empty_message".localizedString,
                        actionTitle: "feedback_add_idea".localizedString,
                        color: ColorTheme.accent,
                        action: {
                            composerError = nil
                            showingComposer = true
                        }
                    )
                } else {
                    if !openFeedbackRequests.isEmpty {
                        FeedbackSectionHeader(
                            title: "feedback_status_open".localizedString,
                            count: openFeedbackRequests.count,
                            systemImage: "flame.fill",
                            tint: ColorTheme.primary
                        )

                        ForEach(openFeedbackRequests) { request in
                            FeedbackRequestCard(
                                request: request,
                                isTogglingVote: togglingVotes.contains(request.id),
                                isDeleting: deletingRequests.contains(request.id),
                                isUpdatingStatus: updatingStatuses.contains(request.id),
                                onVote: {
                                    Task { await toggleVote(for: request.id) }
                                },
                                onDelete: {
                                    requestPendingDeletion = request
                                },
                                onMarkDone: {
                                    Task { await markDone(request.id) }
                                }
                            )
                        }
                    }

                    if !completedFeedbackRequests.isEmpty {
                        FeedbackSectionHeader(
                            title: "feedback_status_shipped".localizedString,
                            count: completedFeedbackRequests.count,
                            systemImage: "checkmark.seal.fill",
                            tint: ColorTheme.success
                        )
                        .padding(.top, openFeedbackRequests.isEmpty ? 0 : 8)

                        ForEach(completedFeedbackRequests) { request in
                            FeedbackRequestCard(
                                request: request,
                                isTogglingVote: togglingVotes.contains(request.id),
                                isDeleting: deletingRequests.contains(request.id),
                                isUpdatingStatus: updatingStatuses.contains(request.id),
                                onVote: {
                                    Task { await toggleVote(for: request.id) }
                                },
                                onDelete: {
                                    requestPendingDeletion = request
                                },
                                onMarkDone: {
                                    Task { await markDone(request.id) }
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 720 : .infinity)
            .animation(.snappy(duration: 0.28, extraBounce: 0.04), value: requests)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await loadFeedback()
        }
    }

    private var signInRequiredView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(ColorTheme.primary.opacity(0.12))
                    .frame(width: 84, height: 84)

                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(ColorTheme.primary)
            }

            Text("feedback_sign_in_title".localizedString)
                .font(.title3.weight(.bold))
                .foregroundColor(ColorTheme.primaryText)
                .multilineTextAlignment(.center)

            Text("feedback_sign_in_message".localizedString)
                .font(.subheadline)
                .foregroundColor(ColorTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                appSessionState.exitGuestModeForLogin()
                showingLogin = true
            } label: {
                Text("sign_in".localizedString)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(ColorTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: ColorTheme.primary.opacity(0.30), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(.hapticScale)
        }
        .padding(28)
        .frame(maxWidth: 420)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.gray.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 6)
    }

    @MainActor
    private func loadFeedback() async {
        guard isSignedIn else { return }
        isLoading = true
        errorMessage = nil
        do {
            requests = try await sessionStore.fetchAppFeedbackRequests(limit: 100)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func submitFeedback(title: String, details: String?) async {
        isSubmittingFeedback = true
        composerError = nil
        do {
            try await sessionStore.createAppFeedbackRequest(
                title: title,
                details: details,
                platform: "ios",
                language: regionSettings.selectedLanguage.rawValue
            )
            showingComposer = false
            await loadFeedback()
        } catch {
            composerError = error.localizedDescription
        }
        isSubmittingFeedback = false
    }

    @MainActor
    private func toggleVote(for requestId: UUID) async {
        guard !togglingVotes.contains(requestId) else { return }
        togglingVotes.insert(requestId)
        do {
            if let result = try await sessionStore.toggleAppFeedbackVote(requestId: requestId),
               let index = requests.firstIndex(where: { $0.id == requestId }) {
                requests[index].hasVoted = result.voted
                requests[index].voteCount = result.voteCount
                requests.sort(by: feedbackRequestSort)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        togglingVotes.remove(requestId)
    }

    @MainActor
    private func deleteRequest(_ requestId: UUID) async {
        guard !deletingRequests.contains(requestId) else { return }
        deletingRequests.insert(requestId)
        do {
            try await sessionStore.deleteAppFeedbackRequest(requestId: requestId)
            requests.removeAll { $0.id == requestId }
        } catch {
            errorMessage = error.localizedDescription
        }
        deletingRequests.remove(requestId)
    }

    @MainActor
    private func markDone(_ requestId: UUID) async {
        guard !updatingStatuses.contains(requestId) else { return }
        updatingStatuses.insert(requestId)
        do {
            if let result = try await sessionStore.setAppFeedbackStatus(requestId: requestId, status: "shipped"),
               let index = requests.firstIndex(where: { $0.id == requestId }) {
                requests[index].status = result.status
                requests[index].completedAt = result.completedAt
                requests.sort(by: feedbackRequestSort)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        updatingStatuses.remove(requestId)
    }
}

private struct FeedbackBoardIntroCard: View {
    let openCount: Int
    let completedCount: Int

    private let hairline = Color.gray.opacity(0.12)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(ColorTheme.primary.opacity(0.12))
                        .frame(width: 44, height: 44)

                    Image(systemName: "lightbulb.max.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(ColorTheme.primary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("feedback_board_intro_title".localizedString)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(ColorTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("feedback_board_intro_subtitle".localizedString)
                        .font(.system(size: 13))
                        .foregroundColor(ColorTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 0) {
                FeedbackBoardStatPill(
                    title: "feedback_status_open".localizedString,
                    value: openCount,
                    dotColor: ColorTheme.primary
                )

                Rectangle()
                    .fill(hairline)
                    .frame(width: 1, height: 34)

                FeedbackBoardStatPill(
                    title: "feedback_status_shipped".localizedString,
                    value: completedCount,
                    dotColor: ColorTheme.success
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ColorTheme.primary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 5)
    }
}

private struct FeedbackAddIdeaBar: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(ColorTheme.primary)
                    .frame(width: 32, height: 32)
                    .background(Color.white)
                    .clipShape(Circle())

                Text("feedback_add_idea".localizedString)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)

                Spacer(minLength: 0)
            }
            .padding(.leading, 6)
            .padding(.trailing, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(ColorTheme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: ColorTheme.primary.opacity(0.30), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.hapticScale)
    }
}

private struct FeedbackSectionHeader: View {
    let title: String
    let count: Int
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(ColorTheme.secondaryText)
                .textCase(.uppercase)

            Text(String(count))
                .font(.caption2.weight(.heavy))
                .monospacedDigit()
                .foregroundColor(tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(tint.opacity(0.12))
                .clipShape(Capsule())

            Rectangle()
                .fill(Color.gray.opacity(0.12))
                .frame(height: 1)
        }
        .padding(.top, 6)
    }
}

private struct FeedbackBoardStatPill: View {
    let title: String
    let value: Int
    let dotColor: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)

                Text(String(value))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(ColorTheme.primaryText)
                    .contentTransition(.numericText(value: Double(value)))
            }

            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundColor(ColorTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

private struct FeedbackRequestCard: View {
    let request: AppFeedbackRequest
    let isTogglingVote: Bool
    let isDeleting: Bool
    let isUpdatingStatus: Bool
    let onVote: () -> Void
    let onDelete: () -> Void
    let onMarkDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                requestContent

                if isCompleted {
                    shippedSeal
                } else {
                    votePill
                }
            }

            if isCompleted {
                completedFooter
            } else if request.canDelete || request.canAdmin {
                actionRow
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isCompleted ? 0.03 : 0.04), radius: 8, x: 0, y: 4)
        .opacity(isCompleted ? 0.95 : 1)
    }

    private var isCompleted: Bool {
        request.status == "shipped"
    }

    private var borderColor: Color {
        if isCompleted { return ColorTheme.success.opacity(0.22) }
        return Color.gray.opacity(0.10)
    }

    private var cardBackground: some ShapeStyle {
        isCompleted
            ? AnyShapeStyle(ColorTheme.success.opacity(0.05))
            : AnyShapeStyle(ColorTheme.cardBackground)
    }

    private var voteTint: Color {
        request.hasVoted ? ColorTheme.primary : ColorTheme.secondaryText
    }

    private var votePill: some View {
        Button(action: onVote) {
            HStack(spacing: 5) {
                voteIcon

                Text(String(request.voteCount))
                    .font(.subheadline.weight(.heavy))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(request.voteCount)))
            }
            .foregroundColor(voteTint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(voteTint.opacity(request.hasVoted ? 0.13 : 0.09))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(voteTint.opacity(request.hasVoted ? 0.20 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.hapticScale)
        .disabled(isTogglingVote)
        .accessibilityLabel(request.hasVoted ? "feedback_remove_vote".localizedString : "feedback_vote".localizedString)
    }

    private var shippedSeal: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .bold))

            Text(String(request.voteCount))
                .font(.subheadline.weight(.heavy))
                .monospacedDigit()
        }
        .foregroundColor(ColorTheme.success)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(ColorTheme.success.opacity(0.12))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(ColorTheme.success.opacity(0.20), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var voteIcon: some View {
        if isTogglingVote {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: request.hasVoted ? "hand.thumbsup.fill" : "hand.thumbsup")
                .font(.system(size: 13, weight: .bold))
        }
    }

    private var requestContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                FeedbackStatusBadge(status: request.status)
                if request.isMine {
                    mineBadge
                }
                Spacer(minLength: 0)
            }

            Text(request.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(ColorTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(1)

            if let details = request.details, !details.isEmpty {
                Text(details)
                    .font(.footnote)
                    .foregroundColor(ColorTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            Label(request.createdAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                .font(.caption2.weight(.medium))
                .foregroundColor(ColorTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actionRow: some View {
        Divider()
            .opacity(0.35)

        HStack(spacing: 8) {
            Spacer(minLength: 0)

            if request.canAdmin {
                Button(action: onMarkDone) {
                    HStack(spacing: 6) {
                        if isUpdatingStatus {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                        }
                        Text("feedback_mark_done".localizedString)
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundColor(ColorTheme.success)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(ColorTheme.success.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.hapticScale)
                .disabled(isUpdatingStatus)
            }

            if request.canDelete {
                Button(role: .destructive, action: onDelete) {
                    HStack(spacing: 6) {
                        if isDeleting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "trash.fill")
                        }
                        Text("delete".localizedString)
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundColor(ColorTheme.danger)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(ColorTheme.danger.opacity(0.10))
                    .clipShape(Capsule())
                }
                .buttonStyle(.hapticScale)
                .disabled(isDeleting)
            }
        }
    }

    private var completedFooter: some View {
        HStack(spacing: 8) {
            Label("feedback_done_note".localizedString, systemImage: "checkmark.seal.fill")
                .font(.caption2.weight(.bold))
                .foregroundColor(ColorTheme.success)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(ColorTheme.success.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var mineBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(ColorTheme.accent)
                .frame(width: 5, height: 5)

            Text("feedback_mine_badge".localizedString)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .foregroundColor(ColorTheme.accent)
                .textCase(.uppercase)
                .lineLimit(1)
        }
    }
}

private struct FeedbackStatusBadge: View {
    let status: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(color)
                .textCase(.uppercase)
                .lineLimit(1)
        }
    }

    private var title: String {
        switch status {
        case "planned": return "feedback_status_planned".localizedString
        case "in_progress": return "feedback_status_in_progress".localizedString
        case "shipped": return "feedback_status_shipped".localizedString
        case "closed": return "feedback_status_closed".localizedString
        default: return "feedback_status_open".localizedString
        }
    }

    private var color: Color {
        switch status {
        case "planned": return ColorTheme.purple
        case "in_progress": return ColorTheme.warning
        case "shipped": return ColorTheme.success
        case "closed": return ColorTheme.secondaryText
        default: return ColorTheme.primary
        }
    }
}

private struct FeedbackStateCard: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(color)
            }

            Text(title)
                .font(.headline.weight(.bold))
                .foregroundColor(ColorTheme.primaryText)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundColor(ColorTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: action) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(
                        colors: [color, color.opacity(0.82)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: color.opacity(0.28), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.hapticScale)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.gray.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 5)
    }
}

private struct FeedbackComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @FocusState private var focusedField: FeedbackComposerField?
    let isSubmitting: Bool
    let errorMessage: String?
    let onSubmit: (String, String?) -> Void

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ColorTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        composerTopBar
                        composerHero
                        composerProgress
                        titleCard
                        detailsCard

                        if let errorMessage, !errorMessage.isEmpty {
                            errorCard(errorMessage)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 116)
                    .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 560 : .infinity)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom) {
                submitBar
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    focusedField = .title
                }
            }
        }
    }

    private var composerTopBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ColorTheme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(ColorTheme.cardBackground)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.gray.opacity(0.10), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.hapticScale)
            .disabled(isSubmitting)

            Spacer()

            Text("feedback_new_idea_title".localizedString)
                .font(.headline.weight(.bold))
                .foregroundColor(ColorTheme.primaryText)

            Spacer()

            ZStack {
                Circle()
                    .fill(ColorTheme.primary.opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: "lightbulb.max.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(ColorTheme.primary)
            }
        }
        .padding(.bottom, 2)
    }

    private var composerHero: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ColorTheme.primary.opacity(0.12))
                    .frame(width: 50, height: 50)

                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(ColorTheme.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("feedback_board_intro_title".localizedString)
                    .font(.headline.weight(.bold))
                    .foregroundColor(ColorTheme.primaryText)

                Text("feedback_board_intro_subtitle".localizedString)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ColorTheme.primary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 5)
    }

    private var composerProgress: some View {
        HStack(spacing: 8) {
            FeedbackComposerStepPill(
                title: "feedback_title_label".localizedString,
                systemImage: titleIsValid ? "checkmark.circle.fill" : "1.circle.fill",
                tint: titleIsValid ? ColorTheme.success : ColorTheme.primary,
                isActive: focusedField == .title || titleIsValid
            )

            FeedbackComposerStepPill(
                title: "feedback_details_label".localizedString,
                systemImage: !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "checkmark.circle.fill" : "2.circle.fill",
                tint: !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ColorTheme.success : ColorTheme.accent,
                isActive: focusedField == .details || !details.isEmpty
            )
        }
    }

    private var titleCard: some View {
        FeedbackComposerCard(
            title: "feedback_title_label".localizedString,
            trailing: "\(trimmedTitle.count)/120",
            tint: titleCardTint,
            isInvalid: titleIsInvalid
        ) {
            TextField("feedback_title_placeholder".localizedString, text: $title)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundColor(ColorTheme.primaryText)
                .focused($focusedField, equals: .title)
                .submitLabel(.next)
                .onSubmit {
                    focusedField = .details
                }

            Text("feedback_title_hint".localizedString)
                .font(.caption)
                .foregroundColor(titleIsInvalid ? ColorTheme.danger : ColorTheme.secondaryText)
        }
    }

    private var detailsCard: some View {
        FeedbackComposerCard(
            title: "feedback_details_label".localizedString,
            trailing: "\(details.count)/1200",
            tint: detailsCardTint,
            isInvalid: details.count > 1200
        ) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $details)
                    .font(.body)
                    .foregroundColor(ColorTheme.primaryText)
                    .frame(minHeight: 142)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, -4)
                    .padding(.vertical, -8)
                    .focused($focusedField, equals: .details)

                if details.isEmpty {
                    Text("feedback_details_placeholder".localizedString)
                        .font(.body)
                        .foregroundColor(ColorTheme.tertiaryText)
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(ColorTheme.danger)

            Text(message)
                .font(.footnote)
                .foregroundColor(ColorTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTheme.danger.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var submitBar: some View {
        VStack(spacing: 0) {
            Button {
                onSubmit(trimmedTitle, trimmedDetails)
            } label: {
                HStack(spacing: 10) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: canSubmit ? "paperplane.fill" : "lock.fill")
                            .font(.system(size: 15, weight: .bold))
                    }

                    Text("feedback_submit".localizedString)
                        .font(.headline.weight(.bold))
                }
                .foregroundColor(canSubmit ? .white : ColorTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
                .background(submitBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: canSubmit ? ColorTheme.primary.opacity(0.28) : .clear, radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.hapticScale)
            .disabled(!canSubmit || isSubmitting)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.gray.opacity(0.10))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var submitBackground: some View {
        if canSubmit {
            ColorTheme.primary
        } else {
            ColorTheme.secondaryText.opacity(0.14)
        }
    }

    private var titleCardTint: Color {
        titleIsInvalid ? ColorTheme.danger : (titleIsValid ? ColorTheme.success : ColorTheme.primary)
    }

    private var detailsCardTint: Color {
        details.count > 1200 ? ColorTheme.danger : (details.isEmpty ? ColorTheme.accent : ColorTheme.success)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDetails: String? {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var titleIsValid: Bool {
        (4...120).contains(trimmedTitle.count)
    }

    private var titleIsInvalid: Bool {
        !title.isEmpty && !titleIsValid
    }

    private var canSubmit: Bool {
        titleIsValid && details.count <= 1200
    }
}

private enum FeedbackComposerField {
    case title
    case details
}

private struct FeedbackComposerStepPill: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(isActive ? tint : ColorTheme.tertiaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(isActive ? tint.opacity(0.12) : ColorTheme.cardBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isActive ? tint.opacity(0.22) : Color.gray.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct FeedbackComposerCard<Content: View>: View {
    let title: String
    let trailing: String
    let tint: Color
    let isInvalid: Bool
    let content: Content

    init(
        title: String,
        trailing: String,
        tint: Color,
        isInvalid: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = trailing
        self.tint = tint
        self.isInvalid = isInvalid
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundColor(ColorTheme.secondaryText)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()

                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(isInvalid ? ColorTheme.danger : ColorTheme.tertiaryText)
            }

            content
        }
        .padding(16)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke((isInvalid ? ColorTheme.danger : tint).opacity(isInvalid ? 0.46 : 0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 5)
    }
}

private func feedbackStatusRank(_ status: String) -> Int {
    switch status {
    case "open": return 1
    case "planned": return 2
    case "in_progress": return 3
    case "closed": return 4
    case "shipped": return 5
    default: return 6
    }
}

private func feedbackRequestSort(_ lhs: AppFeedbackRequest, _ rhs: AppFeedbackRequest) -> Bool {
    if lhs.status != rhs.status {
        return feedbackStatusRank(lhs.status) < feedbackStatusRank(rhs.status)
    }
    if lhs.voteCount != rhs.voteCount {
        return lhs.voteCount > rhs.voteCount
    }
    return lhs.createdAt > rhs.createdAt
}

struct MenuRow: View {
    let icon: String
    let title: LocalizedStringKey
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                .fill(color.opacity(0.1))
                .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
            }
            
            Text(title)
            .font(.body)
            .foregroundColor(ColorTheme.primaryText)
            
            Spacer()
            
            Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundColor(ColorTheme.tertiaryText)
        }
        .padding(16)
    }
}

struct JoinTeamByCodeSheet: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var inviteCode = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("How to join") {
                    Text("1. Ask team admin for the Team Invite Code.")
                    Text("2. Enter code below and tap Join Team.")
                    Text("3. Switch organization from the app switcher.")
                }

                Section("Invite Code") {
                    TextField("Enter Team Invite Code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                        .keyboardType(.asciiCapable)
                        .textContentType(.oneTimeCode)
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }

                Button {
                    submitCode()
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Join Team")
                    }
                }
                .disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
            .navigationTitle("Join Team")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func submitCode() {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil
        Task {
            let success = await sessionStore.submitTeamInviteCode(code)
            await MainActor.run {
                isSubmitting = false
                if success {
                    dismiss()
                } else {
                    errorMessage = sessionStore.inviteToastMessage ?? sessionStore.errorMessage ?? "Unable to apply invite code."
                }
            }
        }
    }
}

private struct StatusBanner: View {
    let state: AccountView.DedupState
    
    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .running:
                ProgressView().progressViewStyle(.circular)
                Text("cleaning_duplicates".localizedString)
            case .success:
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("duplicates_removed".localizedString)
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                Text(message).lineLimit(2)
            case .idle:
                EmptyView()
            }
        }
        .font(.footnote)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .cornerRadius(14)
        .shadow(radius: 4)
        .padding(.horizontal)
    }
}

struct ChangePasswordView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showNewPassword = false
    @State private var showConfirmPassword = false

    var body: some View {
        Form {
            Section(
                header: Text("new_password".localizedString),
                footer: Text("change_password_footer".localizedString)
            ) {
                HStack {
                    if showNewPassword {
                        TextField("new_password_placeholder".localizedString, text: $newPassword)
                    } else {
                        SecureField("new_password_placeholder".localizedString, text: $newPassword)
                    }
                    Button(action: { showNewPassword.toggle() }) {
                        Image(systemName: showNewPassword ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    if showConfirmPassword {
                        TextField("confirm_password_placeholder".localizedString, text: $confirmPassword)
                    } else {
                        SecureField("confirm_password_placeholder".localizedString, text: $confirmPassword)
                    }
                    Button(action: { showConfirmPassword.toggle() }) {
                        Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let error = errorMessage {
                Text(error).foregroundColor(.red).font(.caption)
            }
            
            if let success = successMessage {
                Text(success).foregroundColor(.green).font(.caption)
            }
            
            Button(action: updatePassword) {
                if isLoading {
                    ProgressView()
                } else {
                    Text("update_password".localizedString)
                }
            }
            .disabled(newPassword.isEmpty || newPassword != confirmPassword || isLoading)
        }
        .navigationTitle("change_password".localizedString)
    }
    
    private func updatePassword() {
        guard newPassword == confirmPassword else {
            errorMessage = "passwords_do_not_match".localizedString
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await sessionStore.updatePassword(newPassword)
                await MainActor.run {
                    isLoading = false
                    successMessage = "password_updated_success".localizedString
                    newPassword = ""
                    confirmPassword = ""
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct DeleteAccountView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSessionState: AppSessionState
    @Environment(\.dismiss) private var dismiss
    
    @State private var confirmationText = ""
    @State private var emailConfirmation = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    
    private var userEmail: String {
        if case .signedIn(let user) = sessionStore.status { return user.email ?? "" }
        return ""
    }
    
    private var canDelete: Bool {
        confirmationText.uppercased() == "DELETE" && !userEmail.isEmpty && emailConfirmation.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == userEmail.lowercased()
    }
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("delete_account_warning_title".localizedString)
                        .font(.body).fontWeight(.semibold).foregroundColor(.primary)
                    Text("delete_account_warning_message".localizedString)
                        .font(.callout).foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("confirmation_header".localizedString)) {
                TextField("type_delete_placeholder".localizedString, text: $confirmationText)
                    .autocapitalization(.allCharacters)
                
                TextField("reenter_email_placeholder".localizedString, text: $emailConfirmation)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
            }
            
            if let error = errorMessage {
                Section { Text(error).font(.footnote).foregroundColor(.red) }
            }
            
            Section {
                Button(role: .destructive, action: deleteAccount) {
                    HStack {
                        if isDeleting { ProgressView() }
                        Text(isDeleting ? "deleting_progress".localizedString : "delete_button_title".localizedString)
                    }
                }
                .disabled(!canDelete || isDeleting)
            }
        }
        .navigationTitle("delete_account".localizedString)
        .alert("account_deleted_title".localizedString, isPresented: $showSuccess) {
            Button("OK") { dismiss() }
        } message: { Text("account_deleted_message".localizedString) }
    }
    
    private func deleteAccount() {
        guard canDelete else { return }
        isDeleting = true
        errorMessage = nil
        
        Task {
            do {
                try await sessionStore.deleteAccount()
                await MainActor.run {
                    isDeleting = false; showSuccess = true
                    appSessionState.mode = .signIn
                    appSessionState.email = ""; appSessionState.password = ""; appSessionState.phone = ""
                }
            } catch {
                await MainActor.run { isDeleting = false; errorMessage = error.localizedDescription }
            }
        }
    }
}

// MARK: - Account Org Switcher (Private)
private struct AccountOrgSwitcher: View {
    let userEmail: String?
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var showingOrgSheet = false
    @State private var showingCreateSheet = false
    @State private var newOrgName = ""
    @State private var newOrgBusinessRegion: DealDeskBusinessRegionCode = .generic
    @State private var isCreating = false
    @State private var createError: String?

    var body: some View {
        Button {
            showingOrgSheet = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ColorTheme.primary.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 16))
                        .foregroundColor(ColorTheme.primary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Business".localizedString)
                        .font(.caption.weight(.medium))
                        .foregroundColor(ColorTheme.secondaryText)

                    HStack(spacing: 8) {
                        Text(organizationTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ColorTheme.primaryText)
                            .lineLimit(1)

                        if let roleTitle, shouldShowRoleBadge {
                            Text(roleTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(ColorTheme.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(ColorTheme.primary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.tertiaryText)
            }
            .padding(14)
            .background(ColorTheme.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingOrgSheet) {
            NavigationStack {
                List {
                    Section {
                        if sessionStore.organizations.isEmpty {
                            Text("No organizations yet")
                                .foregroundColor(ColorTheme.secondaryText)
                        } else {
                            ForEach(sessionStore.organizations) { org in
                                Button {
                                    showingOrgSheet = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        Task { await sessionStore.switchOrganization(to: org.organization_id) }
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(org.organization_name)
                                                .font(.body.weight(org.organization_id == sessionStore.activeOrganizationId ? .semibold : .regular))
                                                .foregroundColor(ColorTheme.primaryText)
                                            Text(org.role.capitalized)
                                                .font(.caption)
                                                .foregroundColor(ColorTheme.secondaryText)
                                        }
                                        Spacer()
                                        if org.organization_id == sessionStore.activeOrganizationId {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(ColorTheme.primary)
                                                .font(.title3)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }

                    Section {
                        Button {
                            showingOrgSheet = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showingCreateSheet = true
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                Text("Create Business")
                            }
                            .foregroundColor(ColorTheme.primary)
                            .font(.body.weight(.medium))
                            .padding(.vertical, 2)
                        }
                        .disabled(!isSignedIn)
                    }
                }
                .navigationTitle("Select Business")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            showingOrgSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.fraction(0.4), .medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingCreateSheet) {
            NavigationView {
                Form {
                    Section(header: Text("Business Name")) {
                        TextField("Enter business name", text: $newOrgName)
                            .autocapitalization(.words)
                    }

                    Section(header: Text("Business Region")) {
                        Picker("Business Region", selection: $newOrgBusinessRegion) {
                            ForEach(DealDeskBusinessRegionCode.allCases) { region in
                                Text(region.displayName).tag(region)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if let createError {
                        Section {
                            Text(createError)
                                .foregroundColor(.red)
                        }
                    }

                    Button(isCreating ? "Creating..." : "Create") {
                        Task {
                            isCreating = true
                            defer { isCreating = false }
                            do {
                                let newId = try await sessionStore.createOrganization(
                                    name: newOrgName,
                                    businessRegionCode: newOrgBusinessRegion
                                )
                                await sessionStore.switchOrganization(to: newId)
                                showingCreateSheet = false
                                newOrgName = ""
                                newOrgBusinessRegion = .generic
                                createError = nil
                            } catch {
                                createError = error.localizedDescription
                            }
                        }
                    }
                    .disabled(newOrgName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
                .navigationTitle("Create Business")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingCreateSheet = false
                            newOrgName = ""
                            newOrgBusinessRegion = .generic
                            createError = nil
                        }
                    }
                }
            }
        }
    }

    private var isSignedIn: Bool {
        if case .signedIn = sessionStore.status { return true }
        return false
    }

    private var organizationTitle: String {
        if let organizationName = normalized(sessionStore.activeOrganizationName) {
            if let userEmail = normalized(userEmail), organizationName.caseInsensitiveCompare(userEmail) == .orderedSame {
                return roleTitle ?? "Business".localizedString
            }
            return organizationName
        }

        return "Select Business".localizedString
    }

    private var roleTitle: String? {
        normalized(sessionStore.activeOrganizationRole)?.capitalized
    }

    private var shouldShowRoleBadge: Bool {
        normalized(sessionStore.activeOrganizationName) != nil && organizationTitle != roleTitle
    }

    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
struct AccountUserProfileView: View {
    let userId: UUID
    let authEmail: String?
    let authPendingEmail: String?
    
    @FetchRequest var users: FetchedResults<Ezcar24Business.User>
    @State private var showingEditProfile = false
    
    init(userId: UUID, authEmail: String?, authPendingEmail: String?) {
        self.userId = userId
        self.authEmail = authEmail
        self.authPendingEmail = authPendingEmail
        self._users = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "id == %@ AND deletedAt == nil", userId as CVarArg)
        )
    }
    
    var body: some View {
        let user = users.first
        let displayName = normalized(user?.name)
        let displayEmail = resolvedEmail(for: user)
        let displayPhone = normalized(user?.phone)
        let pendingEmail = normalized(authPendingEmail)
        let avatarURL = resolvedAvatarURL(for: user)

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Button {
                    showingEditProfile = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        if let url = avatarURL {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                        } else {
                            ZStack {
                                Circle()
                                    .fill(ColorTheme.primary.opacity(0.12))
                                    .frame(width: 72, height: 72)
                                
                                Text(getInitials())
                                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                                    .foregroundColor(ColorTheme.primary)
                            }
                        }
                        Image(systemName: "camera.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(ColorTheme.primary)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(ColorTheme.cardBackground, lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    Text(displayName ?? displayEmail ?? "User")
                        .font(.title2.weight(.bold))
                        .foregroundColor(ColorTheme.primaryText)
                        .lineLimit(2)

                    if displayName != nil, let displayEmail {
                        Text(displayEmail)
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.secondaryText)
                            .lineLimit(1)
                    }

                    if let displayPhone {
                        HStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(ColorTheme.primary)

                            Text(displayPhone)
                                .font(.subheadline)
                                .foregroundColor(ColorTheme.secondaryText)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(ColorTheme.secondaryBackground)
                        .clipShape(Capsule())
                    }
                }

                Spacer()
            }

            if let pendingEmail {
                HStack(spacing: 10) {
                    Image(systemName: "clock.badge.exclamationmark.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pending confirmation".localizedString)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.orange)

                        Text(String(format: "Pending: %@".localizedString, pendingEmail))
                            .font(.footnote)
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(spacing: 12) {
                AccountOrgSwitcher(userEmail: displayEmail)

                if let memberSince = user?.createdAt {
                    AccountProfileMetaRow(
                        icon: "calendar",
                        tint: .gray,
                        title: "Member Since".localizedString,
                        value: memberSince.formatted(date: .abbreviated, time: .omitted)
                    )
                }
            }
        }
        .padding(18)
        .sheet(isPresented: $showingEditProfile) {
            if let user = users.first {
                EditProfileView(user: user)
            } else {
                Text("User profile not found locally. Please wait for sync.")
            }
        }
    }

    private func getInitials() -> String {
        if let user = users.first, let name = user.name, !name.isEmpty {
             let components = name.components(separatedBy: " ")
             if let first = components.first?.first, let last = components.last?.first, components.count > 1 {
                 return "\(first)\(last)"
             }
             return String(name.prefix(2)).uppercased()
        }
        return String((authEmail ?? "?").prefix(2)).uppercased()
    }

    private func resolvedEmail(for user: Ezcar24Business.User?) -> String? {
        if let authEmail = normalized(authEmail) {
            return authEmail
        }
        return normalized(user?.email)
    }

    private func resolvedAvatarURL(for user: Ezcar24Business.User?) -> URL? {
        guard let avatarUrl = normalized(user?.avatarUrl) else {
            return nil
        }
        return URL(string: avatarUrl)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

private struct AccountProfileMetaRow: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 42, height: 42)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(ColorTheme.secondaryText)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText)
            }

            Spacer()
        }
        .padding(14)
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
