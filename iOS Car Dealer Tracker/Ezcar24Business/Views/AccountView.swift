import SwiftUI
import Supabase
import UIKit

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
    @State private var showInviteShareSheet = false
    @State private var inviteShareItems: [Any] = []
    @State private var referralCode: String?
    @State private var isFetchingReferralCode = false
    @State private var inviteAlertMessage: String?

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
            .sheet(isPresented: $showInviteShareSheet) {
                ShareSheet(items: inviteShareItems)
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

            if permissionService.can(.viewFinancials) {
                Divider().padding(.leading, 52)
                NavigationLink {
                    HoldingCostSettingsView()
                } label: {
                    MenuRow(icon: "flame.fill", title: "holding_cost_settings".localizedKey, color: .orange)
                }
            }
            
            if permissionService.currentRole == "owner" || permissionService.currentRole == "admin" {
                Divider().padding(.leading, 52)
                NavigationLink {
                    FinancialAccountsView()
                } label: {
                    MenuRow(icon: "banknote", title: "financial_accounts".localizedKey, color: .green)
                }
                
                Divider().padding(.leading, 52)
                NavigationLink {
                    NotionExportView()
                } label: {
                    MenuRow(icon: "square.and.arrow.up", title: "export_to_notion".localizedKey, color: .black)
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

                    if permissionService.currentRole == "owner" {
                        NavigationLink {
                            BackupCenterView()
                        } label: {
                            MenuRow(icon: "externaldrive.badge.checkmark", title: "backup_export".localizedKey, color: .orange)
                        }
                        Divider().padding(.leading, 52)
                    }
                    
                    if permissionService.can(.manageTeam) { // Admin/Owner
                         NavigationLink {
                            DataHealthView()
                        } label: {
                            MenuRow(icon: "stethoscope", title: "data_health".localizedKey, color: .teal)
                        }
                        Divider().padding(.leading, 52)
                        
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
                // Minimal sync section for regular employees if not in management
                 menuSection(title: "sync".localizedKey) {
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
        VStack(spacing: 20) {
            // Avatar is now handled inside AccountUserProfileView
//            ZStack {
//                Circle()
//                    .strokeBorder(ColorTheme.primary.opacity(0.1), lineWidth: 1)
//                    .background(Circle().fill(ColorTheme.cardBackground)) // Ensure solid background behind avatar
//                    .frame(width: 90, height: 90)
//                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
//                
//                Text(userInitials)
//                    .font(.system(size: 34, weight: .bold, design: .rounded))
//                    .foregroundColor(ColorTheme.primary)
//            }
//            .padding(.top, 8)
            
            VStack(spacing: 12) {
                if case .signedIn(let authUser) = sessionStore.status {
                    AccountUserProfileView(userId: authUser.id, authEmail: authUser.email)
                } else {
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
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(ColorTheme.cardBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 15, x: 0, y: 8)
        }
        .padding(.horizontal, 4)
    }
    
    @ViewBuilder
    private var subscriptionCard: some View {
        HStack {
            Image(systemName: subscriptionManager.isProAccessActive ? "crown.fill" : "circle")
                .foregroundColor(subscriptionManager.isProAccessActive ? .yellow : .gray)
                .font(.system(size: 24))
            
            VStack(alignment: .leading, spacing: 2) {
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
                        .font(.caption)
                        .foregroundColor(.secondary)
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
        .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
    }

    @ViewBuilder
    private var referralCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "gift.fill")
                    .foregroundColor(.pink)
                Text("invite_dealer".localizedString)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)
            }

            Text("invite_dealer_subtitle".localizedString)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let bonusUntil = subscriptionManager.bonusAccessUntil, bonusUntil > Date() {
                Text(String(format: "referral_bonus_until".localizedString, bonusUntil.formatted(date: .numeric, time: .omitted)))
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if let code = referralCode {
                HStack {
                    Text(code)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(ColorTheme.background.opacity(0.7))
                        .cornerRadius(10)

                    Spacer()

                    Button("copy".localizedString) {
                        UIPasteboard.general.string = code
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            Button {
                Task { await shareDealerInvite() }
            } label: {
                HStack {
                    if isFetchingReferralCode {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("invite_dealer".localizedString)
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(ColorTheme.primary)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isFetchingReferralCode)

            NavigationLink {
                ReferralStatsView()
            } label: {
                Text("referral_view_stats".localizedString)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ColorTheme.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
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
        guard case .signedIn(let user) = sessionStore.status else {
            await MainActor.run { inviteAlertMessage = "Please sign in to generate an invite link." }
            return
        }
        let dealerId = sessionStore.activeOrganizationId ?? CloudSyncEnvironment.currentDealerId ?? user.id
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

        let link = "https://ezcar24.com/dealer-invite?code=\(code)"
        let message = "Join EZCar24 Business using my invite code \(code). Subscribe and we both get an extra month free."
        var items: [Any] = [message]
        if let url = URL(string: link) {
            items.append(url)
        }
        await MainActor.run {
            inviteShareItems = items
            showInviteShareSheet = true
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
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var showingCreateSheet = false
    @State private var newOrgName = ""
    @State private var isCreating = false
    @State private var createError: String?

    var body: some View {
        Menu {
            if sessionStore.organizations.isEmpty {
                Text("No organizations yet")
            } else {
                ForEach(sessionStore.organizations) { org in
                    Button {
                        Task { await sessionStore.switchOrganization(to: org.organization_id) }
                    } label: {
                        HStack {
                            Text(org.organization_name)
                            Spacer()
                            Text(org.role.capitalized)
                                .foregroundColor(.secondary)
                            if org.organization_id == sessionStore.activeOrganizationId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Create Business") {
                showingCreateSheet = true
            }
            .disabled(!isSignedIn)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sessionStore.activeOrganizationName ?? "Select Business")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(ColorTheme.primaryText)
                        .lineLimit(1)
                    if let role = sessionStore.activeOrganizationRole {
                        Text(role.capitalized)
                            .font(.caption)
                            .foregroundColor(ColorTheme.primary.opacity(0.9))
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(ColorTheme.secondaryBackground)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(ColorTheme.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .frame(maxWidth: 260)
        .sheet(isPresented: $showingCreateSheet) {
            NavigationView {
                Form {
                    Section(header: Text("Business Name")) {
                        TextField("Enter business name", text: $newOrgName)
                            .autocapitalization(.words)
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
                                let newId = try await sessionStore.createOrganization(name: newOrgName)
                                await sessionStore.switchOrganization(to: newId)
                                showingCreateSheet = false
                                newOrgName = ""
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
}
struct AccountUserProfileView: View {
    let userId: UUID
    let authEmail: String?
    
    @FetchRequest var users: FetchedResults<Ezcar24Business.User>
    @State private var showingEditProfile = false
    
    init(userId: UUID, authEmail: String?) {
        self.userId = userId
        self.authEmail = authEmail
        self._users = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "id == %@", userId as CVarArg)
        )
    }
    
    var body: some View {
        let displayEmail: String? = {
            if let user = users.first, let email = user.email, !email.isEmpty {
                return email
            }
            return authEmail
        }()

        VStack(spacing: 12) {
            // Avatar
            Button {
                showingEditProfile = true
            } label: {
                ZStack {
                    if let user = users.first, let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 90, height: 90)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(ColorTheme.primary.opacity(0.1), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                    } else {
                        // Fallback
                        ZStack {
                            Circle()
                                .strokeBorder(ColorTheme.primary.opacity(0.1), lineWidth: 1)
                                .background(Circle().fill(ColorTheme.cardBackground))
                                .frame(width: 90, height: 90)
                                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                            
                            Text(getInitials())
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundColor(ColorTheme.primary)
                        }
                    }
                    
                    // Edit badge
                    Circle()
                        .fill(ColorTheme.primary)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundColor(.white)
                        )
                        .offset(x: 32, y: 32)
                }
            }
            .padding(.top, 8)

            // Name & Email
            VStack(spacing: 4) {
                if let user = users.first, let name = user.name, !name.isEmpty {
                    Text(name)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(ColorTheme.primaryText)
                        .multilineTextAlignment(.center)
                    
                    if let displayEmail, !displayEmail.isEmpty {
                        Text(displayEmail)
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                } else {
                    Text(displayEmail ?? "User")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(ColorTheme.primaryText)
                        .multilineTextAlignment(.center)
                }
            }
            
            // Phone if available
            if let user = users.first, let phone = user.phone, !phone.isEmpty {
                 Text(phone)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }

            AccountOrgSwitcher()
            
            // Member Since
            if let user = users.first {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(String(format: "Member since %@", (user.createdAt ?? Date()).formatted(date: .abbreviated, time: .omitted)))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(ColorTheme.secondaryText)
                .padding(.top, 4)
            }
        }
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
}
