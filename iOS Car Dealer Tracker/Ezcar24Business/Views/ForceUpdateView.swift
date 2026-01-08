import SwiftUI

/// Full-screen blocking view that requires user to update the app
struct ForceUpdateView: View {
    @ObservedObject var versionChecker: AppStoreVersionChecker
    
    private var canOpenAppStore: Bool {
        versionChecker.appStoreURL != nil || versionChecker.appStoreTrackId != nil
    }
    
    var body: some View {
        ZStack {
            // Background
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Icon
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse)
                
                // Title
                VStack(spacing: 12) {
                    Text("Update Required")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("A new version of Car Dealer Tracker is available. Please update to continue using the app.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // Version info
                if let appStoreVersion = versionChecker.appStoreVersion {
                    VStack(spacing: 4) {
                        Text("Current: \(versionChecker.currentVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Available: \(appStoreVersion)")
                            .font(.caption)
                            .foregroundColor(.green)
                            .fontWeight(.medium)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
                
                Spacer()
                
                // Update Button
                Button(action: {
                    versionChecker.openAppStore()
                }) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Update Now")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .disabled(!canOpenAppStore)
                .opacity(canOpenAppStore ? 1 : 0.6)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .interactiveDismissDisabled()
    }
}

#Preview {
    ForceUpdateView(versionChecker: AppStoreVersionChecker.shared)
}
