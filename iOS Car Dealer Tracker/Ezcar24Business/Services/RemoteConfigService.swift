import Foundation
import UIKit
import Supabase

struct RemoteAppConfig: Codable {
    let minVersion: String
    let latestVersion: String
    let forceUpdate: Bool
    let maintenanceMode: Bool
    let blockLevel: String
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
        
        do {
            // Fetch Config from Supabase
            let configJson: RemoteAppConfig = try await client
                .rpc("get_app_config", params: ["config_key": "ios_kill_switch"])
                .execute()
                .value
            
            print("✅ [RemoteConfig] Fetched: \(configJson)")
            
            self.latestVersion = configJson.latestVersion
            self.configMessage = configJson.message
            
            // Check Maintenance Mode
            if configJson.maintenanceMode {
                self.isMaintenanceMode = true
                self.isUpdateRequired = true // Or handle separate blocking view
                return
            }
            
            // Check Min Version (Kill Switch)
            if isVersion(currentVersion, lessThan: configJson.minVersion) {
                print("🛑 [RemoteConfig] Kill Switch Active. Current: \(currentVersion) < Min: \(configJson.minVersion)")
                self.isUpdateRequired = true
                return
            }
            
            // Check Force Update Flag
            if configJson.forceUpdate && isVersion(currentVersion, lessThan: configJson.latestVersion) {
                 print("⚠️ [RemoteConfig] Force Update Active.")
                 self.isUpdateRequired = true
                 return
            }
            
            self.isUpdateRequired = false
            
        } catch {
            print("❌ [RemoteConfig] Failed to fetch config: \(error)")
        }
        
        // Use App Store check as fallback for URL?
        // Fetch URL dynamically from iTunes API to avoid hardcoding ID
        if appStoreURL == nil {
            await fetchAppStoreInfo()
        }
    }
    
    // MARK: - App Store Lookup
    
    private func fetchAppStoreInfo() async {
        let urlString = "https://itunes.apple.com/lookup?bundleId=\(bundleId)"
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
            
            if let first = result.results.first {
                self.appStoreTrackId = first.trackId
                self.appStoreURL = makeAppStoreURL(trackId: first.trackId, trackViewUrl: first.trackViewUrl)
                print("✅ [RemoteConfig] Found App Store URL: \(self.appStoreURL?.absoluteString ?? "nil")")
            }
        } catch {
            print("⚠️ [RemoteConfig] Failed to fetch App Store info: \(error)")
        }
    }
    
    @Published private(set) var appStoreTrackId: Int?
    
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
