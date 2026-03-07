import SwiftUI
import UIKit

struct DataHealthView: View {
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var report: SyncDiagnosticsReport?
    @State private var isRunning = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var copied = false
    @State private var shareText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
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
        .navigationTitle("data_health".localizedString)
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

    private var diagnosticsControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync Diagnostics")
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)

            Text("Run a quick check to compare local data, remote data, and queued changes.")
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
                            Text("Share Report")
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
                Text("Summary")
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
                Text("Remote check failed: \(remoteError)")
                    .font(.footnote)
                    .foregroundColor(ColorTheme.warning)
            }

            if let lastFailureMessage = report.lastFailureMessage {
                Text("Last issue: \(lastFailureMessage)")
                    .font(.footnote)
                    .foregroundColor(report.health == .blocked ? ColorTheme.danger : ColorTheme.warning)

                if let lastFailureAt = report.lastFailureAt {
                    Text("Issue detected at \(formattedDate(lastFailureAt) ?? "—")")
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
            Text("Offline Queue")
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
            Text("Entity Counts")
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(report.entityCounts) { item in
                HStack {
                    Text(item.entity.displayName)
                        .font(.footnote)
                        .foregroundColor(ColorTheme.primaryText)
                    Spacer()
                    Text("Local \(item.localCount)")
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                    if let remote = item.remoteCount {
                        Text("Remote \(remote)")
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                    } else {
                        Text("Remote —")
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
    private func runDiagnostics() async {
        guard case .signedIn(let user) = sessionStore.status else {
            errorMessage = "Sign in to run diagnostics."
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
            errorMessage = "Sign in to run diagnostics."
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
