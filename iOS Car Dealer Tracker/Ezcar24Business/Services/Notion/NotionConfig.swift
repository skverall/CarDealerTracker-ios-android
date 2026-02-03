import Foundation

struct NotionConfig {
    static let clientId = "YOUR_NOTION_CLIENT_ID"
    static let clientSecret = "YOUR_NOTION_CLIENT_SECRET"
    static let redirectUri = "ezcar24://notion/callback"
    static let apiBaseURL = "https://api.notion.com/v1"
    static let notionVersion = "2022-06-28"
    
    static var authUrl: URL? {
        var components = URLComponents(string: "https://api.notion.com/v1/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "owner", value: "user")
        ]
        return components?.url
    }
    
    static var tokenExchangeUrl: URL? {
        URL(string: "\(apiBaseURL)/oauth/token")
    }
}

enum NotionError: Error, LocalizedError {
    case notAuthenticated
    case exportFailed
    case invalidResponse
    case databaseNotFound
    case rateLimited
    case invalidToken
    case networkError(Error)
    case encodingError
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with Notion"
        case .exportFailed:
            return "Export to Notion failed"
        case .invalidResponse:
            return "Invalid response from Notion API"
        case .databaseNotFound:
            return "Database not found"
        case .rateLimited:
            return "Rate limited by Notion API. Please try again later."
        case .invalidToken:
            return "Invalid or expired token"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .encodingError:
            return "Failed to encode request data"
        case .decodingError:
            return "Failed to decode response data"
        }
    }
}

struct ExportResult {
    let successCount: Int
    let failedCount: Int
    let failedIdentifiers: [String]
    let databaseUrl: String?
}

struct ExportResults {
    let vehiclesResult: ExportResult?
    let leadsResult: ExportResult?
    let salesResult: ExportResult?
    
    var totalSuccessCount: Int {
        (vehiclesResult?.successCount ?? 0) +
        (leadsResult?.successCount ?? 0) +
        (salesResult?.successCount ?? 0)
    }
    
    var totalFailedCount: Int {
        (vehiclesResult?.failedCount ?? 0) +
        (leadsResult?.failedCount ?? 0) +
        (salesResult?.failedCount ?? 0)
    }
}