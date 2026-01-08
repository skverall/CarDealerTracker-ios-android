//
//  Ezcar24BusinessApp.swift
//  Ezcar24Business
//
//  Created for UAE Car Resale Business Management
//

import SwiftUI
import Supabase
import RevenueCat

// Fallback provider to ensure RevenueCat keys are available even if the Services file
// is not part of the build target.
private enum RevenueCatKeyProvider {
    static var currentKey: String {
        if let key = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String, key.starts(with: "appl_") {
            return key
        }
        return "appl_AcjVeBViWQjASmtxDkldEkmIvFf"
    }
}

@main
struct Ezcar24BusinessApp: App {
    @StateObject private var sessionStore: SessionStore
    @StateObject private var appSessionState: AppSessionState
    @StateObject private var cloudSyncManager: CloudSyncManager
    @StateObject private var regionSettings = RegionSettingsManager.shared
    @StateObject private var versionChecker = AppStoreVersionChecker.shared
    let persistenceController = PersistenceController.shared
    
    @State private var showRegionSelection = false

    init() {
        // Initialize Supabase and Core Data
        let provider = SupabaseClientProvider()
        let sessionStore = SessionStore(client: provider.client)
        let context = PersistenceController.shared.container.viewContext
        let syncManager = CloudSyncManager(client: provider.client, context: context)

        CloudSyncManager.shared = syncManager
        SessionStoreEnvironment.shared = sessionStore

        _sessionStore = StateObject(wrappedValue: sessionStore)
        _appSessionState = StateObject(wrappedValue: AppSessionState(sessionStore: sessionStore))
        _cloudSyncManager = StateObject(wrappedValue: syncManager)
        
        _ = LocalNotificationManager.shared

        // Initialize RevenueCat
        Purchases.logLevel = .debug
        let currentAppUserId = provider.client.auth.currentSession?.user.id.uuidString
        Purchases.configure(withAPIKey: RevenueCatKeyProvider.currentKey, appUserID: currentAppUserId)
    }

    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                .environmentObject(sessionStore)
                .environmentObject(appSessionState)
                .environmentObject(cloudSyncManager)
                .environmentObject(regionSettings)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(\.locale, regionSettings.selectedLanguage.locale)
                .id(regionSettings.selectedLanguage.id)
                .onOpenURL { url in
                    Task {
                        do {
                            try await sessionStore.handleDeepLink(url)
                        } catch {
                            print("Deep link error: \(error)")
                        }
                    }
                }
                .task {
                    // Check for app updates on launch
                    await versionChecker.checkForUpdate()
                    await LocalNotificationManager.shared.refreshAll(context: persistenceController.container.viewContext)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task {
                            await versionChecker.checkForUpdate()
                            await LocalNotificationManager.shared.refreshAll(context: persistenceController.container.viewContext)
                        }
                    }
                }
                .onAppear {
                    // Show region selection on first launch
                    if !regionSettings.hasSelectedRegion {
                        showRegionSelection = true
                    }
                }
                .fullScreenCover(isPresented: $versionChecker.isUpdateRequired) {
                    ForceUpdateView(versionChecker: versionChecker)
                }
                .sheet(isPresented: $showRegionSelection) {
                    RegionSelectionSheet()
                        .environmentObject(regionSettings)
                }
        }
    }
}
