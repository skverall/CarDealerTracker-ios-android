import SwiftUI
import Supabase

struct AccountView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSessionState: AppSessionState
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var isSigningOut = false
    @State private var isSyncing = false
    @State private var syncComplete = false
    @State private var showingLogin = false
    @State private var showingPaywall = false
    @State private var showingDeleteAlert = false
    @State private var dedupState: DedupState = .idle
    @AppStorage(NotificationPreference.enabledKey) private var notificationsEnabled = false
    @State private var showNotificationSettingsAlert = false
    @State private var notificationAlertMessage = ""

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
                        
                        // Subscription Status Card
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: subscriptionManager.isProAccessActive ? "star.circle.fill" : "circle")
                                    .foregroundColor(subscriptionManager.isProAccessActive ? .yellow : .gray)
                                    .font(.system(size: 24))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(subscriptionManager.isProAccessActive ? "dealer_pro".localizedString : "free_plan".localizedString)
                                        .font(.headline)
                                        .foregroundColor(ColorTheme.primaryText)
                                    
                                    if subscriptionManager.isProAccessActive {
                                        if let expirationDate = subscriptionManager.expirationDate {
                                            let isTrial = subscriptionManager.isTrial
                                            let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
                                            
                                            if daysRemaining <= 7 {
                                                Text("\(isTrial ? "trial".localizedString : "subscription".localizedString) ends in \(max(0, daysRemaining)) days")
                                                    .font(.caption)
                                                    .foregroundColor(.orange)
                                            } else {
                                                Text("\(isTrial ? "trial".localizedString : "subscription".localizedString) active until \(expirationDate, style: .date)")
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
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if case .signedIn = sessionStore.status {
                                        showingPaywall = true
                                    } else {
                                        appSessionState.exitGuestModeForLogin()
                                        showingLogin = true
                                    }
                                }
                                
                                Spacer()
                                
                                if subscriptionManager.isProAccessActive {
                                    Button("manage".localizedString) {
                                        subscriptionManager.showManageSubscriptions()
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                                } else {
                                    Button("upgrade".localizedString) {
                                        if case .signedIn = sessionStore.status {
                                            showingPaywall = true
                                        } else {
                                            appSessionState.exitGuestModeForLogin()
                                            showingLogin = true
                                        }
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .cornerRadius(20)
                                }
                            }
                            .padding(16)
                            .background(ColorTheme.cardBackground)
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
                        }
                        .padding(.horizontal, 16)
                        
                        VStack(spacing: 16) {
                            menuSection(title: "finance".localizedKey) {
                                NavigationLink {
                                    FinancialAccountsView()
                                } label: {
                                    MenuRow(icon: "banknote", title: "financial_accounts".localizedKey, color: .green)
                                }
                                
                                NavigationLink {
                                    RegionLanguageSettingsView()
                                } label: {
                                    MenuRow(icon: "globe", title: "region_language".localizedKey, color: .indigo)
                                }
                            }
                            
                            menuSection(title: "management".localizedKey) {
                                NavigationLink {
                                    UserManagementView()
                                } label: {
                                    MenuRow(icon: "person.2.fill", title: "team_members".localizedKey, color: .blue)
                                }

                                NavigationLink {
                                    BackupCenterView()
                                } label: {
                                    MenuRow(icon: "externaldrive.badge.checkmark", title: "backup_export".localizedKey, color: .orange)
                                }

                                NavigationLink {
                                    DataHealthView()
                                } label: {
                                    MenuRow(icon: "stethoscope", title: "data_health".localizedKey, color: .teal)
                                }
                                
                                Button {
                                    Task {
                                        await runDeduplication()
                                    }
                                } label: {
                                    MenuRow(icon: "arrow.triangle.merge", title: "clean_up_duplicates".localizedKey, color: .purple)
                                }

                                Button {
                                    Task { await runManualSync() }
                                } label: {
                                    HStack {
                                        MenuRow(icon: "arrow.clockwise", title: "sync_now".localizedKey, color: .blue)
                                        if cloudSyncManager.isSyncing {
                                            ProgressView()
                                                .progressViewStyle(.circular)
                                        }
                                    }
                                }
                                .disabled(cloudSyncManager.isSyncing)

                                HStack {
                                    Text("last_sync".localizedString)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(lastSyncText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 4)
                            }

                            menuSection(title: "notifications".localizedKey) {
                                notificationsRow
                            }
                            
                            menuSection(title: "account".localizedKey) {
                                Button(action: signOut) {
                                    HStack {
                                        MenuRow(icon: "rectangle.portrait.and.arrow.right", title: "sign_out".localizedKey, color: .red)
                                        
                                        Spacer()
                                        
                                        if isSyncing {
                                            HStack(spacing: 8) {
                                                ProgressView()
                                                    .progressViewStyle(.circular)
                                                Text("syncing".localizedString)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        } else if syncComplete {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.system(size: 20))
                                        }  else if isSigningOut || sessionStore.isAuthenticating {
                                            ProgressView()
                                                .progressViewStyle(.circular)
                                        }
                                    }
                                }
                                .disabled(isSigningOut || sessionStore.isAuthenticating)
                            }
                            
                            menuSection(title: "security".localizedKey) {
                                NavigationLink {
                                    ChangePasswordView()
                                } label: {
                                    MenuRow(icon: "lock.rotation", title: "change_password".localizedKey, color: .purple)
                                }
                                
                                NavigationLink {
                                    DeleteAccountView()
                                } label: {
                                    MenuRow(icon: "trash", title: "delete_account".localizedKey, color: .red)
                                }
                            }
                            
                            menuSection(title: "legal".localizedKey) {
                                Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                                    MenuRow(icon: "doc.text", title: "terms_of_use".localizedKey, color: .gray)
                                }
                                Link(destination: URL(string: "https://www.ezcar24.com/en/privacy-policy")!) { // Updated
                                    MenuRow(icon: "hand.raised.fill", title: "privacy_policy".localizedKey, color: .gray)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("account".localizedString)
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
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
            .alert("Notifications", isPresented: $showNotificationSettingsAlert) {
                Button("Open Settings") {
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

        }
    }

    @ViewBuilder
    private var accountHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(ColorTheme.primary.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Text(userInitials)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(ColorTheme.primary)
            }
            
            VStack(spacing: 4) {
                if case .signedIn(let user) = sessionStore.status {
                    Text(user.email ?? "User")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(ColorTheme.primaryText)
                    
                    Text("Member since \(user.createdAt, style: .date)")
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                    
                    if (user.emailConfirmedAt as Date?) != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(ColorTheme.success)
                            Text("verified_account".localizedString)
                                .foregroundColor(ColorTheme.success)
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.top, 4)
                    }
                } else {
                    Text("not_signed_in".localizedString)
                        .font(.headline)
                        .foregroundColor(ColorTheme.secondaryText)
                    
                    Button("Sign In / Enable Cloud Sync") {
                        appSessionState.exitGuestModeForLogin()
                        showingLogin = true
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(ColorTheme.cardBackground)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 16)
    }
    
    private func menuSection<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .textCase(.uppercase)
                .foregroundColor(ColorTheme.secondaryText)
                .padding(.leading, 8)
            
            VStack(spacing: 1) {
                content()
            }
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
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
        return "Never"
    }

    private func signOut() {
        guard !isSigningOut else { return }
        
        Task {
            // Step 1: Show syncing indicator
            await MainActor.run {
                isSyncing = true
                syncComplete = false
            }
            
            // Step 2: Process all pending offline operations
            if case .signedIn(let user) = sessionStore.status {
                await cloudSyncManager.processOfflineQueue(dealerId: user.id)
            }
            
            // Step 3: Show success checkmark
            await MainActor.run {
                isSyncing = false
                syncComplete = true
            }
            
            // Step 4: Wait a moment to show checkmark
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
            
            // Step 5: Start sign out
            await MainActor.run {
                isSigningOut = true
            }
            
            // Step 6: Sign out
            await sessionStore.signOut()

            // Step 7: Reset state
            await MainActor.run {
                appSessionState.mode = .signIn
                appSessionState.email = ""
                appSessionState.password = ""
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
                    appSessionState.email = ""
                    appSessionState.password = ""
                }
            } catch {
                print("Error deleting account: \(error)")
            }
        }
    }
    
    @MainActor
    private func runDeduplication() async {
        guard case .signedIn(let user) = sessionStore.status else { return }
        dedupState = .running
        do {
            try await cloudSyncManager.deduplicateData(dealerId: user.id)
            dedupState = .success
        } catch {
            dedupState = .error(error.localizedDescription)
        }
        // Auto-hide after a short delay
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
        // Use fullSync for "Sync Now" button to push local changes too
        await cloudSyncManager.fullSync(user: user)
    }

    private var notificationsRow: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(ColorTheme.primary.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 16))
                    .foregroundColor(ColorTheme.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Reminders & Due Dates")
                    .font(.body)
                    .foregroundColor(ColorTheme.primaryText)
                Text("clients_and_debts".localizedString)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }

            Spacer()

            Toggle("", isOn: $notificationsEnabled)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: ColorTheme.primary))
        }
        .padding(16)
    }

    private func handleNotificationsToggle(isEnabled: Bool) async {
        if isEnabled {
            let granted = await LocalNotificationManager.shared.requestAuthorization()
            if granted {
                await LocalNotificationManager.shared.refreshAll(context: viewContext)
            } else {
                await MainActor.run {
                    notificationsEnabled = false
                    notificationAlertMessage = "Enable notifications in Settings to receive client reminders and debt due alerts."
                    showNotificationSettingsAlert = true
                }
            }
        } else {
            await LocalNotificationManager.shared.clearAll()
        }
    }
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

private struct StatusBanner: View {
    let state: AccountView.DedupState
    
    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .running:
                ProgressView()
                    .progressViewStyle(.circular)
                Text("Cleaning duplicates…")
            case .success:
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("duplicates_removed".localizedString)
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                Text(message)
                    .lineLimit(2)
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
            Section(header: Text("new_password".localizedString)) {
                HStack {
                    if showNewPassword {
                        TextField("New Password", text: $newPassword)
                    } else {
                        SecureField("New Password", text: $newPassword)
                    }
                    Button(action: { showNewPassword.toggle() }) {
                        Image(systemName: showNewPassword ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    if showConfirmPassword {
                        TextField("Confirm Password", text: $confirmPassword)
                    } else {
                        SecureField("Confirm Password", text: $confirmPassword)
                    }
                    Button(action: { showConfirmPassword.toggle() }) {
                        Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            if let success = successMessage {
                Text(success)
                    .foregroundColor(.green)
                    .font(.caption)
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
            errorMessage = "Passwords do not match"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await sessionStore.updatePassword(newPassword)
                await MainActor.run {
                    isLoading = false
                    successMessage = "Password updated successfully"
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
        if case .signedIn(let user) = sessionStore.status {
            return user.email ?? ""
        }
        return ""
    }
    
    private var canDelete: Bool {
        confirmationText.uppercased() == "DELETE" && !userEmail.isEmpty && emailConfirmation.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == userEmail.lowercased()
    }
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This will permanently delete your account and all data.")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Type DELETE to confirm, and re-enter your account email to proceed.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("Confirmation")) {
                TextField("Type DELETE", text: $confirmationText)
                    .autocapitalization(.allCharacters)
                
                TextField("Re-enter your email", text: $emailConfirmation)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }
            
            Section {
                Button(role: .destructive, action: deleteAccount) {
                    HStack {
                        if isDeleting {
                            ProgressView()
                        }
                        Text(isDeleting ? "Deleting..." : "Delete Account")
                    }
                }
                .disabled(!canDelete || isDeleting)
            }
        }
        .navigationTitle("delete_account".localizedString)
        .alert("Account Deleted", isPresented: $showSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your account and data have been removed.")
        }
    }
    
    private func deleteAccount() {
        guard canDelete else { return }
        isDeleting = true
        errorMessage = nil
        
        Task {
            do {
                try await sessionStore.deleteAccount()
                await MainActor.run {
                    isDeleting = false
                    showSuccess = true
                    appSessionState.mode = .signIn
                    appSessionState.email = ""
                    appSessionState.password = ""
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
