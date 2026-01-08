import SwiftUI

/// Full-screen blocking view that requires user to update the app
struct ForceUpdateView: View {
    @ObservedObject var remoteConfig: RemoteConfigService
    
    var body: some View {
        ZStack {
            // Background
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Icon
                Image(systemName: remoteConfig.isMaintenanceMode ? "cone.fill" : "arrow.down.app.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: remoteConfig.isMaintenanceMode ? [.orange, .red] : [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse)
                
                // Title
                VStack(spacing: 12) {
                    Text(remoteConfig.isMaintenanceMode ? "Maintenance Break" : "Update Required")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text(remoteConfig.configMessage ?? (remoteConfig.isMaintenanceMode ? "We are performing scheduled maintenance. Please check back later." : "A new version of Car Dealer Tracker is available. Please update to continue using the app."))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // Version info
                if !remoteConfig.isMaintenanceMode, let latestVersion = remoteConfig.latestVersion {
                    VStack(spacing: 4) {
                        Text("Current: \(remoteConfig.currentVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Available: \(latestVersion)")
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
                if !remoteConfig.isMaintenanceMode {
                    Button(action: {
                        remoteConfig.openAppStore()
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
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

#Preview {
    ForceUpdateView(remoteConfig: RemoteConfigService.shared)
}
