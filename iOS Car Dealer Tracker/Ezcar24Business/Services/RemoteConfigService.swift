import Foundation
import UIKit
import Supabase

struct RemoteAppConfig: Codable {
    let minVersion: String?
    let latestVersion: String?
    let forceUpdate: Bool?
    let maintenanceMode: Bool?
    let blockLevel: String?
    let message: String?
    
    enum CodingKeys: String, CodingKey {
        case minVersion = "min_version"
        case latestVersion = "latest_version"
        case forceUpdate = "force_update"
        case maintenanceMode = "maintenance_mode"
        case blockLevel = "block_level"
        case message
    }
}

@MainActor
final class RemoteConfigService: ObservableObject {
    static let shared = RemoteConfigService()
    
    @Published var isUpdateRequired = false
    @Published var isMaintenanceMode = false
    @Published var configMessage: String?
    
    @Published private(set) var latestVersion: String?
    @Published private(set) var appStoreURL: URL?
    @Published private(set) var isChecking = false
    
    private var client: SupabaseClient?
    private let bundleId = Bundle.main.bundleIdentifier ?? "com.ezcar24.business"
    
    private init() {}
    
    func configure(client: SupabaseClient) {
        self.client = client
    }
    
    /// Current app version from Info.plist
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    
    func checkForUpdate() async {
        guard let client = client else { return }
        
        isChecking = true
        defer { isChecking = false }
        
        print("🔄 [RemoteConfig] Checking for updates...")
        
        var requiresUpdate = false
        var maintenance = false
        var configLatest: String?
        var configMin: String?
        var configMessage: String?
        var configForce = false
        var configBlockLevel: String?

        do {
            let configJson: RemoteAppConfig = try await client
                .rpc("get_app_config", params: ["config_key": "ios_kill_switch"])
                .execute()
                .value

            print("✅ [RemoteConfig] Fetched: \(configJson)")

            configLatest = configJson.latestVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
            configMin = configJson.minVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
            configMessage = configJson.message
            configForce = configJson.forceUpdate ?? false
            configBlockLevel = configJson.blockLevel
            maintenance = configJson.maintenanceMode ?? false
        } catch {
            print("❌ [RemoteConfig] Failed to fetch config: \(error)")
        }

        self.configMessage = configMessage

        if maintenance {
            self.isMaintenanceMode = true
            self.isUpdateRequired = true
            await ensureAppStoreInfo()
            return
        } else {
            self.isMaintenanceMode = false
        }

        let blockLevel = (configBlockLevel ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let blockRequiresUpdate = ["hard", "force", "required", "block"].contains(blockLevel)

        if let min = configMin, !min.isEmpty, isVersion(currentVersion, lessThan: min) {
            print("🛑 [RemoteConfig] Kill Switch Active. Current: \(currentVersion) < Min: \(min)")
            requiresUpdate = true
        }

        if let latest = configLatest, !latest.isEmpty {
            self.latestVersion = latest
            if (configForce || blockRequiresUpdate) && isVersion(currentVersion, lessThan: latest) {
                print("⚠️ [RemoteConfig] Force Update Active.")
                requiresUpdate = true
            }
        }

        await ensureAppStoreInfo()

        if let storeVersion = appStoreVersion, isVersion(currentVersion, lessThan: storeVersion) {
            if latestVersion == nil || latestVersion?.isEmpty == true || isVersion(latestVersion ?? "0.0.0", lessThan: storeVersion) {
                latestVersion = storeVersion
            }
            requiresUpdate = true
        }

        self.isUpdateRequired = requiresUpdate
    }
    
    // MARK: - App Store Lookup
    
    private func fetchAppStoreInfo() async {
        let urlString = "https://itunes.apple.com/lookup?bundleId=\(bundleId)"
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
            
            if let first = result.results.first {
                self.appStoreVersion = first.version
                self.appStoreTrackId = first.trackId
                self.appStoreURL = makeAppStoreURL(trackId: first.trackId, trackViewUrl: first.trackViewUrl)
                print("✅ [RemoteConfig] Found App Store URL: \(self.appStoreURL?.absoluteString ?? "nil")")
            }
        } catch {
            print("⚠️ [RemoteConfig] Failed to fetch App Store info: \(error)")
        }
    }
    
    @Published private(set) var appStoreTrackId: Int?
    @Published private(set) var appStoreVersion: String?

    private func ensureAppStoreInfo() async {
        if appStoreURL == nil || appStoreVersion == nil {
            await fetchAppStoreInfo()
        }
    }
    
    private func makeAppStoreURL(trackId: Int?, trackViewUrl: String?) -> URL? {
        if let trackId, let url = URL(string: "itms-apps://itunes.apple.com/app/id\(trackId)") {
            return url
        }
        if let trackViewUrl, let url = URL(string: trackViewUrl) {
            return url
        }
        return nil
    }

    func openAppStore() {
        if let url = appStoreURL {
            UIApplication.shared.open(url)
        }
    }
    
    /// Compare two version strings
    private func isVersion(_ v1: String, lessThan v2: String) -> Bool {
        return v1.compare(v2, options: .numeric) == .orderedAscending
    }
}

// Private Response Models
private struct AppStoreLookupResponse: Decodable {
    let resultCount: Int
    let results: [AppStoreResult]
}

private struct AppStoreResult: Decodable {
    let version: String
    let trackViewUrl: String?
    let trackId: Int?
}
