import SwiftUI

struct SyncHUDOverlay: View {
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @State private var isSpinning = false

    var body: some View {
        Group {
            switch cloudSyncManager.syncHUDState {
            case .some(.syncing):
                hudView(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: ColorTheme.primary,
                    title: "Synchronizing",
                    subtitle: "Please wait..."
                )
                .onAppear { isSpinning = true }

            case .some(.success):
                hudView(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    title: "Synced",
                    subtitle: "All data is up to date"
                )
                .onAppear { isSpinning = false }

            case .some(.failure):
                hudView(
                    icon: "xmark.octagon.fill",
                    iconColor: .red,
                    title: "Sync failed",
                    subtitle: "Please try again"
                )
                .onAppear { isSpinning = false }

            case .none:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: cloudSyncManager.syncHUDState)
    }

    @ViewBuilder
    private func hudView(icon: String, iconColor: Color, title: String, subtitle: String?) -> some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: icon)
                // Use .degrees(isSpinning ? 360 : 0) directly if compatible, or handle animation carefully
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(iconColor)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(
                        isSpinning
                        ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                        : .default,
                        value: isSpinning
                    )

                Text(title)
                    .font(.headline)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
            .padding(20)
            .frame(maxWidth: 260)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 8)
        }
        .transition(.opacity.combined(with: .scale))
    }
}
