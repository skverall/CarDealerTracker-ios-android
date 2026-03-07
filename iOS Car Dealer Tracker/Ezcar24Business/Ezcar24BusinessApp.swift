//
//  Ezcar24BusinessApp.swift
//  Ezcar24Business
//
//  Created for UAE Car Resale Business Management
//

import SwiftUI
import Supabase
import RevenueCat
import FirebaseCore
import Network
import UserNotifications

private enum AppRuntime {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isConnected = true

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "NetworkMonitor")

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        if !AppRuntime.isRunningTests {
            FirebaseApp.configure()
        }
        return true
    }
}

@main
struct Ezcar24BusinessApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    @StateObject private var sessionStore: SessionStore
    @StateObject private var appSessionState: AppSessionState
    @StateObject private var cloudSyncManager: CloudSyncManager
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var regionSettings = RegionSettingsManager.shared
    @StateObject private var remoteConfig = RemoteConfigService.shared
    @StateObject private var persistenceController = PersistenceController.shared
    
    @State private var showRegionSelection = false

    init() {
        // Initialize Supabase and Core Data
        let provider = SupabaseClientProvider()
        let sessionStore = SessionStore(client: provider.client)
        let context = PersistenceController.shared.viewContext
        let syncManager = CloudSyncManager(client: provider.client, context: context)

        CloudSyncManager.shared = syncManager
        SessionStoreEnvironment.shared = sessionStore
        
        // Configure Permissions and Remote Config with client
        PermissionService.shared.configure(client: provider.client)
        RemoteConfigService.shared.configure(client: provider.client)

        _sessionStore = StateObject(wrappedValue: sessionStore)
        _appSessionState = StateObject(wrappedValue: AppSessionState(sessionStore: sessionStore))
        _cloudSyncManager = StateObject(wrappedValue: syncManager)

        if !AppRuntime.isRunningTests {
            _ = LocalNotificationManager.shared
            Purchases.logLevel = .debug
            let currentAppUserId = provider.client.auth.currentSession?.user.id.uuidString
            Purchases.configure(withAPIKey: RevenueCatKeyProvider.currentKey, appUserID: currentAppUserId)
        }
    }

    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                .environmentObject(sessionStore)
                .environmentObject(appSessionState)
                .environmentObject(cloudSyncManager)
                .environmentObject(networkMonitor)
                .environmentObject(regionSettings)
                .environment(\.managedObjectContext, persistenceController.viewContext)
                .environment(\.locale, regionSettings.selectedLanguage.locale)
                .id("\(regionSettings.selectedLanguage.id)-\(persistenceController.activeStoreKey)")
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
                    guard !AppRuntime.isRunningTests else { return }
                    await remoteConfig.checkForUpdate()
                    await LocalNotificationManager.shared.refreshAll(context: persistenceController.container.viewContext)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        guard !AppRuntime.isRunningTests else { return }
                        UNUserNotificationCenter.current().setBadgeCount(0)

                        Task {
                            await remoteConfig.checkForUpdate()
                            await LocalNotificationManager.shared.refreshAll(context: persistenceController.container.viewContext)
                            await sessionStore.refreshPermissionsIfPossible()
                        }
                    }
                }
                .onAppear {
                    if !regionSettings.hasSelectedRegion {
                        showRegionSelection = true
                    }
                }
                .fullScreenCover(isPresented: $remoteConfig.isUpdateRequired) {
                    ForceUpdateView(remoteConfig: remoteConfig)
                }
                .fullScreenCover(isPresented: $showRegionSelection) {
                    RegionSelectionSheet()
                        .environmentObject(regionSettings)
                }
        }
    }
}
