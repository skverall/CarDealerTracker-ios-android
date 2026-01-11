import SwiftUI

struct BackupCenterView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @StateObject private var exporter: BackupExportManager

    @State private var startDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @State private var shareURL: URL?
    @State private var isProcessing = false
    @State private var statusMessage: String?

    init() {
        let ctx = PersistenceController.shared.container.viewContext
        _exporter = StateObject(wrappedValue: BackupExportManager(context: ctx))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorTheme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        
                        // MARK: - Quick Exports
                        menuSection(title: "Quick Exports") {
                            ExportRow(
                                title: "Export expenses CSV",
                                icon: "creditcard",
                                color: .blue
                            ) {
                                try exporter.exportExpensesCSV()
                            }
                            
                            Divider().padding(.leading, 52)
                            
                            ExportRow(
                                title: "Export vehicles CSV",
                                icon: "car.fill",
                                color: .purple
                            ) {
                                try exporter.exportVehiclesCSV()
                            }
                            
                            Divider().padding(.leading, 52)
                            
                            ExportRow(
                                title: "Export clients CSV",
                                icon: "person.2.fill",
                                color: .orange
                            ) {
                                try exporter.exportClientsCSV()
                            }
                        }
                        
                        // MARK: - Custom Range Report
                        menuSection(title: "Custom Range Report") {
                            VStack(spacing: 16) {
                                HStack(spacing: 12) {
                                    datePickerBox(title: "Start", selection: $startDate)
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(ColorTheme.tertiaryText)
                                        .font(.caption)
                                    datePickerBox(title: "End", selection: $endDate)
                                }
                                .padding(.top, 4)
                                
                                Button {
                                    runExport {
                                        let range = DateInterval(start: startDate, end: endDate)
                                        return try exporter.generateReportPDF(for: range)
                                    }
                                } label: {
                                    HStack {
                                        Text("Generate PDF Report")
                                            .fontWeight(.semibold)
                                        Spacer()
                                        if isProcessing {
                                            ProgressView().tint(.white)
                                        } else {
                                            Image(systemName: "doc.text.fill")
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(ColorTheme.primary)
                                    .cornerRadius(12)
                                }
                                .disabled(isProcessing)
                            }
                            .padding(16)
                        }
                        
                        // MARK: - Full Archive
                        menuSection(title: "Full Backup & Archive") {
                            VStack(alignment: .leading, spacing: 12) {
                                Button {
                                    runAsyncExport {
                                        let dealerId = CloudSyncEnvironment.currentDealerId
                                        let range = DateInterval(start: startDate, end: endDate)
                                        return try await exporter.createRangeArchive(for: range, dealerId: dealerId)
                                    }
                                } label: {
                                    HStack {
                                        ZStack {
                                            Circle()
                                                .fill(Color.green.opacity(0.1))
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "archivebox.fill")
                                                .foregroundColor(.green)
                                                .font(.system(size: 16))
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Build JSON Archive")
                                                .foregroundColor(ColorTheme.primaryText)
                                                .font(.body)
                                            Text("Includes CSVs + PDF Report")
                                                .font(.caption)
                                                .foregroundColor(ColorTheme.secondaryText)
                                        }
                                        
                                        Spacer()
                                        
                                        if isProcessing {
                                            ProgressView()
                                        } else {
                                            Image(systemName: "arrow.down.circle")
                                                .foregroundColor(.green)
                                                .font(.system(size: 20))
                                        }
                                    }
                                }
                                .disabled(isProcessing)
                                
                                if sessionStore.isSignedIn {
                                    HStack(spacing: 6) {
                                        Image(systemName: "cloud.fill")
                                        Text("Automatically uploads to Supabase cloud storage (bucket: dealer-backups).")
                                    }
                                    .font(.caption2)
                                    .foregroundColor(ColorTheme.tertiaryText)
                                    .padding(.leading, 44)
                                }
                            }
                            .padding(16)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Backup & Export")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { attachCloudManagerIfNeeded() }
            .sheet(isPresented: .constant(shareURL != nil), onDismiss: { shareURL = nil }) {
                if let url = shareURL {
                    ShareSheet(items: [url]) {
                        shareURL = nil
                    }
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "externaldrive.fill.badge.checkmark")
                .font(.system(size: 40))
                .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(.bottom, 4)
            
            Text("Data Management")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(ColorTheme.primaryText)
            
            Text("Create local backups, generate PDF reports, or archive your entire dataset to the cloud.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundColor(statusMessage.contains("Failed") ? .red : .green)
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 12)
    }
    
    private func menuSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(ColorTheme.secondaryText)
                .padding(.leading, 8)
            
            VStack(spacing: 0) {
                content()
            }
            .background(ColorTheme.cardBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
        }
    }
    
    private func datePickerBox(title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(ColorTheme.secondaryText)
            
            DatePicker("", selection: selection, displayedComponents: [.date])
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(ColorTheme.background)
        .cornerRadius(8)
    }
    
    private struct ExportRow: View {
        let title: String
        let icon: String
        let color: Color
        let action: () throws -> Void
        
        var body: some View {
            Button {
                do { try action() } catch { print(error) }
            } label: {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.1))
                            .frame(width: 36, height: 36)
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundColor(color)
                    }
                    
                    Text(title)
                        .font(.callout)
                        .foregroundColor(ColorTheme.primaryText)
                    
                    Spacer()
                    
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                        .foregroundColor(ColorTheme.tertiaryText)
                }
                .padding(16)
            }
        }
    }

    private func attachCloudManagerIfNeeded() {
        if exporter.cloudSyncManager == nil {
            exporter.cloudSyncManager = cloudSyncManager
        }
    }

    private func runExport(_ action: @escaping () throws -> URL) {
        statusMessage = nil
        isProcessing = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try action()
                DispatchQueue.main.async {
                    shareURL = url
                    statusMessage = "Ready for export"
                    isProcessing = false
                }
            } catch {
                DispatchQueue.main.async {
                    statusMessage = "Failed: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }

    private func runAsyncExport(_ action: @escaping () async throws -> URL) {
        statusMessage = nil
        isProcessing = true
        Task {
            do {
                let url = try await action()
                await MainActor.run {
                    shareURL = url
                    statusMessage = "Archive ready"
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Failed: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }
}

private extension SessionStore {
    var isSignedIn: Bool {
        if case .signedIn = status {
            return true
        }
        return false
    }
}
