import SwiftUI

struct DataHealthView: View {
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var report: SyncDiagnosticsReport?
    @State private var isRunning = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?

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
        }
        .padding(16)
        .cardStyle()
    }

    private func summaryCard(_ report: SyncDiagnosticsReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Summary")
                .font(.subheadline)
                .fontWeight(.semibold)

            summaryRow(label: "Last Sync", value: formattedDate(report.lastSyncAt) ?? "Never")
            summaryRow(label: "Diagnostics", value: formattedDate(report.generatedAt) ?? "—")
            summaryRow(label: "Queue Items", value: "\(report.offlineQueueCount)")

            if let remoteError = report.remoteFetchError {
                Text("Remote check failed: \(remoteError)")
                    .font(.footnote)
                    .foregroundColor(ColorTheme.warning)
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

    private func formattedDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @MainActor
    private func runDiagnostics() async {
        guard case .signedIn(let user) = sessionStore.status else {
            errorMessage = "Sign in to run diagnostics."
            return
        }
        errorMessage = nil
        isRunning = true
        report = await cloudSyncManager.runDiagnostics(dealerId: user.id)
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
        report = await cloudSyncManager.runDiagnostics(dealerId: user.id)
        isRefreshing = false
    }
}

#Preview {
    DataHealthView()
}
