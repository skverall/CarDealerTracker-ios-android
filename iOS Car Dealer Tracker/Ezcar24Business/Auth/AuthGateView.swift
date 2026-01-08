import SwiftUI
import Supabase

struct AuthGateView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var appSessionState: AppSessionState
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var periodicSyncTask: Task<Void, Never>?

    private let periodicSyncInterval: TimeInterval = 5 * 60

    var body: some View {
        Group {
            // Priority 1: Show password reset if in recovery mode
            if sessionStore.showPasswordReset {
                PasswordResetView()
                    .environmentObject(sessionStore)
            }
            // Priority 2: Guest mode
            else if appSessionState.isGuestMode {
                ContentContainerView()
            }
            // Priority 3: Normal auth flow
            else {
                switch sessionStore.status {
                case .loading:
                    ProgressView("Checking session…")
                        .progressViewStyle(.circular)
                case .signedOut:
                    LoginView(
                        isGuest: Binding(
                            get: { appSessionState.isGuestMode },
                            set: { appSessionState.isGuestMode = $0 }
                        )
                    )
                case .signedIn(let user):
                    ContentContainerView()
                        .task {
                            await cloudSyncManager.syncAfterLogin(user: user)
                        }
                }
            }
        }
        .task {
            await sessionStore.bootstrap()
        }
        .animation(.easeInOut, value: sessionStore.status)
        .animation(.easeInOut, value: sessionStore.showPasswordReset)
        .animation(.easeInOut, value: appSessionState.isGuestMode)
        .onAppear {
            refreshPeriodicSync()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            triggerForegroundSyncIfNeeded()
        }
        .onChange(of: appSessionState.isGuestMode) { _, _ in
            refreshPeriodicSync()
        }
        .onChange(of: sessionStore.showPasswordReset) { _, _ in
            refreshPeriodicSync()
        }
        .onChange(of: sessionStore.status) { _, newStatus in
            if case .signedIn(let user) = newStatus {
                appSessionState.isGuestMode = false
                // Link RevenueCat user to restore subscription
                SubscriptionManager.shared.logIn(userId: user.id.uuidString)
                // Only sync if NOT in password recovery mode
                if !sessionStore.showPasswordReset {
                    Task {
                        await cloudSyncManager.syncAfterLogin(user: user)
                    }
                }
            }
            refreshPeriodicSync()
        }
    }

    private func triggerForegroundSyncIfNeeded() {
        guard !appSessionState.isGuestMode, !sessionStore.showPasswordReset else { return }
        guard case .signedIn(let user) = sessionStore.status else { return }
        Task {
            await cloudSyncManager.manualSync(user: user)
        }
    }

    private func refreshPeriodicSync() {
        guard !appSessionState.isGuestMode, !sessionStore.showPasswordReset else {
            stopPeriodicSync()
            return
        }
        guard case .signedIn = sessionStore.status else {
            stopPeriodicSync()
            return
        }
        startPeriodicSyncIfNeeded()
    }

    private func startPeriodicSyncIfNeeded() {
        guard periodicSyncTask == nil else { return }
        periodicSyncTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(periodicSyncInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                guard !appSessionState.isGuestMode, !sessionStore.showPasswordReset else { continue }
                guard case .signedIn(let user) = sessionStore.status else { continue }
                await cloudSyncManager.manualSync(user: user)
            }
        }
    }

    private func stopPeriodicSync() {
        periodicSyncTask?.cancel()
        periodicSyncTask = nil
    }
}

private struct ContentContainerView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        ContentView()
            .overlay(alignment: .top) {
                if sessionStore.shouldShowEmailReminderBanner {
                    EmailReminderBanner()
                }
            }
    }
}

private struct EmailReminderBanner: View {
    var body: some View {
        Text("Email is not verified yet. Please confirm your address to unlock all features.")
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.orange)
            .shadow(radius: 4)
            .padding()
    }
}
