import Foundation
import Supabase

struct SupabaseClientProvider {
    let client: SupabaseClient

    init() {
        do {
            let configuration = try SupabaseClientProvider.loadConfiguration()
            let authOptions = SupabaseClientOptions.AuthOptions(
                redirectToURL: URL(string: "com.ezcar24.business://login-callback"),
                emitLocalSessionAsInitialSession: true
            )
            let options = SupabaseClientOptions(auth: authOptions)

            client = SupabaseClient(
                supabaseURL: configuration.url,
                supabaseKey: configuration.anonKey,
                options: options
            )
        } catch {
            print("CRITICAL ERROR: Failed to create SupabaseClient: \(error.localizedDescription). Check SupabaseConfig.plist or environment variables.")
            // Fallback to avoid crash, but app won't work correctly.
            // In a real app, you might want to show an error screen.
            let dummyURL = URL(string: "https://example.com")!
            let dummyKey = "dummy"
            client = SupabaseClient(supabaseURL: dummyURL, supabaseKey: dummyKey)
        }
    }
}

private extension SupabaseClientProvider {
    struct Configuration {
        let url: URL
        let anonKey: String
    }

    struct PlistPayload: Decodable {
        let supabaseURL: String
        let supabaseAnonKey: String
    }

    enum ConfigurationError: LocalizedError {
        case missingCredentials
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "SUPABASE_URL and SUPABASE_ANON_KEY are missing."
            case .invalidURL:
                return "SUPABASE_URL has an invalid format."
            }
        }
    }

    static func loadConfiguration() throws -> Configuration {
        if let envURL = ProcessInfo.processInfo.environment["SUPABASE_URL"],
           let envKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"],
           !envURL.isEmpty,
           !envKey.isEmpty,
           let url = URL(string: envURL) {
            return Configuration(url: url, anonKey: envKey)
        }

        guard let fileURL = Bundle.main.url(forResource: "SupabaseConfig", withExtension: "plist") else {
            throw ConfigurationError.missingCredentials
        }

        let data = try Data(contentsOf: fileURL)
        let payload = try PropertyListDecoder().decode(PlistPayload.self, from: data)

        guard !payload.supabaseURL.isEmpty, !payload.supabaseAnonKey.isEmpty else {
            throw ConfigurationError.missingCredentials
        }

        guard let url = URL(string: payload.supabaseURL) else {
            throw ConfigurationError.invalidURL
        }

        return Configuration(
            url: url,
            anonKey: payload.supabaseAnonKey
        )
    }
}
