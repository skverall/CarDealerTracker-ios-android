import SwiftUI
import UIKit

struct DataHealthView: View {
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject private var permissionService = PermissionService.shared
    @State private var report: SyncDiagnosticsReport?
    @State private var isRunning = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var copied = false
    @State private var shareText: String?
    @State private var isSyncingNow = false
    @State private var isDeduplicating = false
    @State private var maintenanceMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                maintenanceControls

                diagnosticsControls

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(ColorTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .cardStyle()
                }

                if let report {
                    summaryCard(report)
                    if !report.offlineQueueSummary.isEmpty {
                        queueCard(report)
                    }
                    countsCard(report)
                }
            }
            .padding(16)
        }
        .background(ColorTheme.background.ignoresSafeArea())
        .navigationTitle("Sync & Maintenance".localizedString)
        .sheet(isPresented: Binding(
            get: { shareText != nil },
            set: { if !$0 { shareText = nil } }
        )) {
            if let shareText {
                ShareSheet(items: [shareText]) {
                    self.shareText = nil
                }
            }
        }
    }

    private var maintenanceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Maintenance".localizedString)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)

            Text("Sync your data with the cloud or clean up duplicate records.".localizedString)
                .font(.footnote)
                .foregroundColor(ColorTheme.secondaryText)

            Button {
                Task { await runSyncNow() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isSyncingNow ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isSyncingNow ? "Syncing...".localizedString : "sync_now".localizedString)
                            .fontWeight(.semibold)
                        Text(String(format: "last_sync".localizedString, lastSyncText))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Spacer()
                    if isSyncingNow {
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(ColorTheme.primary.opacity(isSyncingNow ? 0.4 : 0.9))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isSyncingNow || cloudSyncManager.isSyncing)

            if permissionService.can(.manageTeam) {
                Button {
                    Task { await runDeduplication() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isDeduplicating ? "hourglass" : "arrow.triangle.merge")
                        Text(isDeduplicating ? "cleaning_duplicates".localizedString : "clean_up_duplicates".localizedString)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(ColorTheme.purple.opacity(isDeduplicating ? 0.35 : 0.12))
                    .foregroundColor(isDeduplicating ? .white : ColorTheme.purple)
                    .cornerRadius(12)
                }
                .disabled(isDeduplicating)
            }

            if let maintenanceMessage {
                Text(maintenanceMessage)
                    .font(.footnote)
                    .foregroundColor(ColorTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .cardStyle()
    }

    private var lastSyncText: String {
        if let date = cloudSyncManager.lastSyncAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return "never".localizedString
    }

    private var diagnosticsControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync Diagnostics".localizedString)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)

            Text("Run a quick check to compare local data, remote data, and queued changes.".localizedString)
                .font(.footnote)
                .foregroundColor(ColorTheme.secondaryText)

            Button {
                Task { await runDiagnostics() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isRunning ? "hourglass" : "stethoscope")
                    Text(isRunning ? "Running..." : "Run Diagnostics")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(ColorTheme.primary.opacity(isRunning ? 0.4 : 0.9))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isRunning || isRefreshing)

            Button {
                Task { await runFullRefresh() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    Text(isRefreshing ? "Refreshing..." : "Force Full Refresh")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(ColorTheme.warning.opacity(isRefreshing ? 0.4 : 0.9))
                .foregroundColor(.black)
                .cornerRadius(12)
            }
            .disabled(isRunning || isRefreshing || cloudSyncManager.isSyncing)

            if report != nil {
                HStack(spacing: 12) {
                    Button {
                        copyReport()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Copied" : "Copy Report")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(ColorTheme.success.opacity(copied ? 0.35 : 0.12))
                        .foregroundColor(copied ? ColorTheme.success : ColorTheme.primaryText)
                        .cornerRadius(12)
                    }

                    Button {
                        shareReport()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Report".localizedString)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(ColorTheme.primary.opacity(0.12))
                        .foregroundColor(ColorTheme.primaryText)
                        .cornerRadius(12)
                    }
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    private func summaryCard(_ report: SyncDiagnosticsReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Summary".localizedString)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                healthBadge(report.health)
            }

            summaryRow(label: "Last Sync", value: formattedDate(report.lastSyncAt) ?? "Never")
            summaryRow(label: "Last Push", value: formattedDate(report.lastPushAt) ?? "Never")
            summaryRow(label: "Diagnostics", value: formattedDate(report.generatedAt) ?? "—")
            summaryRow(label: "Queue Items", value: "\(report.offlineQueueCount)")
            summaryRow(label: "Ready Now", value: "\(report.queueSnapshot.readyCount)")
            summaryRow(label: "Waiting Retry", value: "\(report.queueSnapshot.waitingCount)")
            summaryRow(label: "Dead Letters", value: "\(report.queueSnapshot.deadLetterCount)")

            if let oldestQueuedAt = report.queueSnapshot.oldestQueuedAt {
                summaryRow(label: "Oldest Queued", value: formattedDate(oldestQueuedAt) ?? "—")
            }

            if let nextRetryAt = report.queueSnapshot.nextRetryAt {
                summaryRow(label: "Next Retry", value: formattedDate(nextRetryAt) ?? "—")
            }

            if let remoteError = report.remoteFetchError {
                    Text(String(format: "Remote check failed: %@".localizedString, remoteError))
                    .font(.footnote)
                    .foregroundColor(ColorTheme.warning)
            }

            if let lastFailureMessage = report.lastFailureMessage {
                    Text(String(format: "Last issue: %@".localizedString, lastFailureMessage))
                    .font(.footnote)
                    .foregroundColor(report.health == .blocked ? ColorTheme.danger : ColorTheme.warning)

                if let lastFailureAt = report.lastFailureAt {
                    Text(String(format: "Issue detected at %@".localizedString, formattedDate(lastFailureAt) ?? "—"))
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    private func queueCard(_ report: SyncDiagnosticsReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Offline Queue".localizedString)
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack {
                queueStat(title: "Ready", value: report.queueSnapshot.readyCount, color: ColorTheme.primary)
                queueStat(title: "Waiting", value: report.queueSnapshot.waitingCount, color: ColorTheme.warning)
                queueStat(title: "Dead", value: report.queueSnapshot.deadLetterCount, color: ColorTheme.danger)
            }

            ForEach(report.offlineQueueSummary) { item in
                HStack {
                    Text(item.entity.displayName)
                        .font(.footnote)
                        .foregroundColor(ColorTheme.primaryText)
                    Spacer()
                    Text("\(item.operation.displayName): \(item.count)")
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    private func countsCard(_ report: SyncDiagnosticsReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Entity Counts".localizedString)
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(report.entityCounts) { item in
                HStack {
                    Text(item.entity.displayName)
                        .font(.footnote)
                        .foregroundColor(ColorTheme.primaryText)
                    Spacer()
                        Text(String(format: "Local %@".localizedString, "\(item.localCount)"))
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                    if let remote = item.remoteCount {
                        Text(String(format: "Remote %@".localizedString, "\(remote)"))
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                    } else {
                        Text(String(format: "Remote %@".localizedString, "—"))
                            .font(.caption)
                            .foregroundColor(ColorTheme.tertiaryText)
                    }
                    if let delta = item.delta, delta != 0 {
                        Text(delta > 0 ? "+\(delta)" : "\(delta)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(delta > 0 ? ColorTheme.warning : ColorTheme.success)
                    }
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundColor(ColorTheme.secondaryText)
            Spacer()
            Text(value)
                .font(.footnote)
                .foregroundColor(ColorTheme.primaryText)
        }
    }

    private func healthBadge(_ health: SyncHealthStatus) -> some View {
        Text(health.displayName)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(healthColor(health).opacity(0.16))
            .foregroundColor(healthColor(health))
            .clipShape(Capsule())
    }

    private func queueStat(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(ColorTheme.secondaryText)
            Text("\(value)")
                .font(.headline)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func healthColor(_ health: SyncHealthStatus) -> Color {
        switch health {
        case .healthy:
            return ColorTheme.success
        case .degraded:
            return ColorTheme.warning
        case .blocked:
            return ColorTheme.danger
        }
    }

    private func formattedDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func copyReport() {
        guard let exportText = makeExportText() else { return }
        UIPasteboard.general.string = exportText
        withAnimation {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copied = false
            }
        }
    }

    private func shareReport() {
        shareText = makeExportText()
    }

    private func makeExportText() -> String? {
        guard let report else { return nil }
        guard let dealerId = currentDealerId else { return nil }
        return report.exportText(
            context: SyncDiagnosticsExportContext(
                dealerId: dealerId,
                isConnected: networkMonitor.isConnected,
                deviceName: UIDevice.current.name,
                systemVersion: UIDevice.current.systemVersion,
                appVersion: appVersionString()
            )
        )
    }

    private var currentDealerId: UUID? {
        guard case .signedIn(let user) = sessionStore.status else { return nil }
        return CloudSyncEnvironment.currentDealerId ?? user.id
    }

    private func appVersionString() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    @MainActor
    private func runSyncNow() async {
        guard case .signedIn(let user) = sessionStore.status else {
            errorMessage = "diagnostics_sign_in_required".localizedString
            return
        }
        errorMessage = nil
        maintenanceMessage = nil
        isSyncingNow = true
        await cloudSyncManager.fullSync(user: user)
        isSyncingNow = false
    }

    @MainActor
    private func runDeduplication() async {
        guard case .signedIn(let user) = sessionStore.status else {
            errorMessage = "diagnostics_sign_in_required".localizedString
            return
        }
        maintenanceMessage = nil
        isDeduplicating = true
        do {
            let dealerId = CloudSyncEnvironment.currentDealerId ?? user.id
            try await cloudSyncManager.deduplicateData(dealerId: dealerId)
            maintenanceMessage = "duplicates_removed".localizedString
        } catch {
            maintenanceMessage = error.localizedDescription
        }
        isDeduplicating = false
    }

    @MainActor
    private func runDiagnostics() async {
        guard case .signedIn(let user) = sessionStore.status else {
            errorMessage = "diagnostics_sign_in_required".localizedString
            return
        }
        errorMessage = nil
        isRunning = true
        let dealerId = CloudSyncEnvironment.currentDealerId ?? user.id
        report = await cloudSyncManager.runDiagnostics(dealerId: dealerId)
        isRunning = false
    }

    @MainActor
    private func runFullRefresh() async {
        guard case .signedIn(let user) = sessionStore.status else {
            errorMessage = "diagnostics_sign_in_required".localizedString
            return
        }
        errorMessage = nil
        isRefreshing = true
        await cloudSyncManager.manualSync(user: user, force: true)
        let dealerId = CloudSyncEnvironment.currentDealerId ?? user.id
        report = await cloudSyncManager.runDiagnostics(dealerId: dealerId)
        isRefreshing = false
    }
}

#Preview {
    DataHealthView()
}
