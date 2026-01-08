import Foundation
import UIKit

/// Service to check App Store for latest version and determine if update is required
@MainActor
final class AppStoreVersionChecker: ObservableObject {
    static let shared = AppStoreVersionChecker()
    
    @Published var isUpdateRequired = false
    @Published private(set) var appStoreVersion: String?
    @Published private(set) var appStoreURL: URL?
    @Published private(set) var appStoreTrackId: Int?
    @Published private(set) var isChecking = false
    
    private let bundleId = Bundle.main.bundleIdentifier ?? "com.ezcar24.business"
    
    private init() {}
    
    /// Current app version from Info.plist
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    
    /// Check App Store for updates
    func checkForUpdate() async {
        isChecking = true
        defer { isChecking = false }
        
        print("🔄 [VersionCheck] Starting version check for \(bundleId) (Current: \(currentVersion))")
        
        
        // Priority:
        // 1. User's current device region (if available)
        // 2. UAE (primary market)
        // 3. Global (App Store default)
        // 4. Other key markets (RU, US)
        var countriesToCheck: [String?] = ["ae", nil, "ru", "us"]
        
        if let currentRegion = Locale.current.region?.identifier.lowercased() {
             // Insert user's region at the start if it's not already covered
            if !countriesToCheck.contains(currentRegion) && currentRegion != "ae" && currentRegion != "ru" && currentRegion != "us" {
                countriesToCheck.insert(currentRegion, at: 0)
            } else if let index = countriesToCheck.firstIndex(of: currentRegion) {
                // Move it to front if it exists
                countriesToCheck.remove(at: index)
                countriesToCheck.insert(currentRegion, at: 0)
            }
        }
        
        for country in countriesToCheck {
            print("🔄 [VersionCheck] Checking region: \(country ?? "Global")")
            if await performLookup(country: country) {
                print("✅ [VersionCheck] Version info found in \(country ?? "Global") store")
                return
            }
        }
        
        print("⚠️ [VersionCheck] App not found in any checked region")
    }
    
    /// Perform lookup for a specific country
    /// Returns true if app was found and state was updated
    private func performLookup(country: String?) async -> Bool {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        var queryItems = [URLQueryItem(name: "bundleId", value: bundleId)]
        if let country = country {
            queryItems.append(URLQueryItem(name: "country", value: country))
        }
        components?.queryItems = queryItems
        
        guard let url = components?.url else { return false }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("❌ [VersionCheck] HTTP Error: \(httpResponse.statusCode)")
                return false
            }
            
            let lookupResponse = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
            
            guard let result = lookupResponse.results.first else {
                return false
            }
            
            print("🔄 [VersionCheck] App Store Version: \(result.version)")
            
            self.appStoreVersion = result.version
            self.appStoreTrackId = result.trackId
            self.appStoreURL = makeAppStoreURL(trackId: result.trackId, trackViewUrl: result.trackViewUrl)
            
            let needsUpdate = isVersion(result.version, greaterThan: currentVersion)
            print("🔄 [VersionCheck] Needs update: \(needsUpdate)")
            
            self.isUpdateRequired = needsUpdate
            return true
            
        } catch {
            print("❌ [VersionCheck] Lookup error: \(error)")
            return false
        }
    }
    
    /// Open App Store page
    func openAppStore() {
        if let url = appStoreURL {
            UIApplication.shared.open(url)
            return
        }
        if let trackId = appStoreTrackId,
           let url = URL(string: "https://apps.apple.com/app/id\(trackId)") {
            UIApplication.shared.open(url)
        }
    }
    
    /// Compare two version strings (e.g., "1.2.3" vs "1.2.2")
    private func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let v1Components = v1.split(separator: ".").compactMap { Int($0) }
        let v2Components = v2.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(v1Components.count, v2Components.count)
        
        for i in 0..<maxCount {
            let v1Part = i < v1Components.count ? v1Components[i] : 0
            let v2Part = i < v2Components.count ? v2Components[i] : 0
            
            if v1Part > v2Part {
                return true
            } else if v1Part < v2Part {
                return false
            }
        }
        
        return false
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
}

// MARK: - App Store API Response Models

private struct AppStoreLookupResponse: Decodable {
    let resultCount: Int
    let results: [AppStoreResult]
}

private struct AppStoreResult: Decodable {
    let version: String
    let trackViewUrl: String?
    let trackId: Int?
}
