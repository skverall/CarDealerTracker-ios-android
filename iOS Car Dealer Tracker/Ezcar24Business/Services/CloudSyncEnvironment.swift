import Foundation
import Supabase

@MainActor
enum CloudSyncEnvironment {
    static var currentDealerId: UUID? {
        guard let sessionStore = SessionStoreEnvironment.shared else { return nil }
        if case .signedIn(let user) = sessionStore.status {
            return user.id
        }
        return nil
    }
}

@MainActor
enum SessionStoreEnvironment {
    static weak var shared: SessionStore?
}

