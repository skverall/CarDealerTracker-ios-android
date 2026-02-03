import Foundation
import Security
import Combine

@MainActor
class NotionAuthManager: ObservableObject {
    static let shared = NotionAuthManager()
    
    @Published var isAuthenticated: Bool = false
    @Published var accessToken: String?
    @Published var isRefreshing: Bool = false
    
    private let keychainKey = "com.ezcar24.notion.token"
    private let tokenExpiryKey = "com.ezcar24.notion.tokenExpiry"
    private var refreshTask: Task<Void, Never>?
    
    init() {
        loadTokenFromKeychain()
    }
    
    func initiateOAuth() -> URL? {
        NotionConfig.authUrl
    }
    
    func handleCallback(url: URL) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            throw NotionError.invalidResponse
        }
        
        if queryItems.contains(where: { $0.name == "error" }) {
            throw NotionError.exportFailed
        }
        
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            throw NotionError.invalidResponse
        }
        
        try await exchangeCodeForToken(code)
    }
    
    private func exchangeCodeForToken(_ code: String) async throws {
        guard let url = NotionConfig.tokenExchangeUrl else {
            throw NotionError.invalidResponse
        }
        
        let credentials = "\(NotionConfig.clientId):\(NotionConfig.clientSecret)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw NotionError.encodingError
        }
        let base64Credentials = credentialsData.base64EncodedString()
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": NotionConfig.redirectUri
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw NotionError.rateLimited
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NotionError.invalidToken
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw NotionError.decodingError
        }
        
        await MainActor.run {
            self.accessToken = token
            self.isAuthenticated = true
        }
        
        saveTokenToKeychain(token)
        
        if let expiresIn = json["expires_in"] as? TimeInterval {
            let expiryDate = Date().addingTimeInterval(expiresIn)
            UserDefaults.standard.set(expiryDate, forKey: tokenExpiryKey)
        }
    }
    
    func refreshTokenIfNeeded() async throws {
        guard let expiryDate = UserDefaults.standard.object(forKey: tokenExpiryKey) as? Date else {
            return
        }
        
        let refreshThreshold: TimeInterval = 300
        if Date().addingTimeInterval(refreshThreshold) < expiryDate {
            return
        }
        
        if let existingTask = refreshTask {
            await existingTask.value
            return
        }
        
        refreshTask = Task {
            defer { refreshTask = nil }
            
            do {
                try await performTokenRefresh()
            } catch {
                await MainActor.run {
                    self.logout()
                }
            }
        }
        
        await refreshTask?.value
    }
    
    private func performTokenRefresh() async throws {
        guard accessToken != nil else {
            throw NotionError.notAuthenticated
        }
        
        isRefreshing = true
        defer { isRefreshing = false }
        
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    
    func logout() {
        accessToken = nil
        isAuthenticated = false
        deleteTokenFromKeychain()
        UserDefaults.standard.removeObject(forKey: tokenExpiryKey)
    }
    
    private func saveTokenToKeychain(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func loadTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return
        }
        
        accessToken = token
        isAuthenticated = true
    }
    
    private func deleteTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}