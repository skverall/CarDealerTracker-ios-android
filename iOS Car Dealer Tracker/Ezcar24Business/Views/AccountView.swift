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
    @State private var showingPaywall = false
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
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
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
    }
    
    private var generalSettingsSection: some View {
        menuSection(title: "settings".localizedKey) {
            NavigationLink {
                RegionLanguageSettingsView()
            } label: {
                MenuRow(icon: "globe", title: "region_language".localizedKey, color: .indigo)
            }
            
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
        HStack(spacing: 16) {
            ZStack {
                LinearGradient(colors: subscriptionManager.isProAccessActive ? [.yellow, .orange] : [.gray.opacity(0.5), .gray.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                Image(systemName: subscriptionManager.isProAccessActive ? "crown.fill" : "star.fill")
                    .foregroundColor(.white)
                    .font(.title3)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(subscriptionManager.isProAccessActive ? "dealer_pro".localizedString : "free_plan".localizedString)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)
                
                if subscriptionManager.isProAccessActive {
                    if let expirationDate = subscriptionManager.expirationDate {
                        let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
                        
                        if daysRemaining <= 7 {
                            Text(String(format: "subscription_ends_in_days".localizedString, max(0, daysRemaining)))
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text(String(format: "subscription_active_until".localizedString, expirationDate.formatted(date: .numeric, time: .omitted)))
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    } else {
                        Text("active_subscription".localizedString)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                } else {
                    Text("upgrade_to_unlock".localizedString)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
            
            Spacer()
            
            Button {
                if subscriptionManager.isProAccessActive {
                    subscriptionManager.showManageSubscriptions()
                } else {
                    if case .signedIn = sessionStore.status {
                        showingPaywall = true
                    } else {
                        appSessionState.exitGuestModeForLogin()
                        showingLogin = true
                    }
                }
            } label: {
                Text(subscriptionManager.isProAccessActive ? "manage".localizedString : "upgrade".localizedString)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(subscriptionManager.isProAccessActive ? .blue : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(subscriptionManager.isProAccessActive ? Color.blue.opacity(0.1) : Color.blue)
                    .cornerRadius(20)
            }
        }
        .padding(16)
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    @ViewBuilder
    private var referralCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                ZStack {
                    LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    Image(systemName: "gift.fill")
                        .font(.title3)
                        .foregroundColor(.white)
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
                HStack {
                    if isFetchingReferralCode {
                        ProgressView().tint(.white).padding(.trailing, 4)
                    }
                    Text("invite_dealer".localizedString)
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(ColorTheme.primary)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
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
            await MainActor.run { inviteAlertMessage = "Please sign in to generate an invite link." }
            return
        }
        guard let dealerId = await sessionStore.resolveDealerIdForReferral() else {
            await MainActor.run {
                inviteAlertMessage = "Unable to determine your organization. Please try again."
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
                inviteAlertMessage = "Unable to generate an invite link. Please try again."
            }
            return
        }

        let link = "https://ezcar24.com/?ref=\(code)"
        let message = "Join EZCar24 Business using my invite code \(code). Subscribe and we both get an extra month free."
        var items: [Any] = [message]
        if let url = URL(string: link) {
            let icon = UIImage(systemName: "car.fill")
            let source = ShareLinkItemSource(url: url, title: "EZCar24 Business Invite", icon: icon)
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
            predicate: NSPredicate(format: "id == %@", userId as CVarArg)
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
