import SwiftUI

struct NotionExportView: View {
    @StateObject private var viewModel = NotionExportViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                connectionSection
                
                if viewModel.isConnected {
                    exportOptionsSection
                    databaseSection
                    dateRangeSection
                    exportButtonSection
                }
            }
            .navigationTitle("Export to Notion")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $viewModel.showAuthSheet) {
                if let url = viewModel.authUrl {
                    NotionAuthView(url: url) { callbackUrl in
                        viewModel.handleAuthCallback(url: callbackUrl)
                    }
                }
            }
            .alert("Export Complete", isPresented: $viewModel.showSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                if let results = viewModel.exportResults {
                    Text("Successfully exported \(results.totalSuccessCount) items.\nFailed: \(results.totalFailedCount)")
                } else {
                    Text("Export completed")
                }
            }
            .overlay {
                if viewModel.isExporting {
                    ExportProgressView(
                        progress: viewModel.exportProgress,
                        currentItem: viewModel.currentItem,
                        exportedCount: viewModel.exportedCount,
                        totalCount: viewModel.totalCount
                    )
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }
    
    private var connectionSection: some View {
        Section("Notion Connection") {
            if viewModel.isConnected {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .imageScale(.large)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connected to Notion")
                            .font(.headline)
                        Text("Ready to export data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Disconnect") {
                        viewModel.disconnect()
                    }
                    .foregroundColor(.red)
                    .font(.caption)
                }
            } else {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "link.circle")
                            .foregroundColor(.blue)
                            .imageScale(.large)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Connect to Notion")
                                .font(.headline)
                            Text("Export your data to Notion databases")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    Button(action: { viewModel.connectToNotion() }) {
                        HStack {
                            Image(systemName: "link")
                            Text("Connect")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isConnecting)
                }
            }
        }
    }
    
    private var exportOptionsSection: some View {
        Section("Export Options") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select Data to Export")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                ForEach(NotionExportViewModel.ExportType.allCases) { type in
                    ExportTypeRow(
                        type: type,
                        isSelected: viewModel.selectedExportTypes.contains(type)
                    ) {
                        if viewModel.selectedExportTypes.contains(type) {
                            viewModel.selectedExportTypes.remove(type)
                        } else {
                            viewModel.selectedExportTypes.insert(type)
                        }
                    }
                }
            }
        }
    }
    
    private var databaseSection: some View {
        Section("Destination Database") {
            Toggle("Create New Database", isOn: $viewModel.createNewDatabase)
            
            if viewModel.createNewDatabase {
                TextField("Database Name", text: $viewModel.newDatabaseName)
                TextField("Parent Page ID", text: $viewModel.parentPageId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                if viewModel.isLoadingDatabases {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if viewModel.availableDatabases.isEmpty {
                    Text("No databases found")
                        .foregroundColor(.secondary)
                } else {
                    Picker("Select Database", selection: $viewModel.selectedDatabaseId) {
                        Text("Choose a database...")
                            .tag(nil as String?)
                        
                        ForEach(viewModel.availableDatabases) { database in
                            Text(database.displayTitle)
                                .tag(database.id as String?)
                        }
                    }
                }
                
                Button("Refresh Databases") {
                    Task {
                        await viewModel.fetchDatabases()
                    }
                }
                .font(.caption)
            }
        }
    }
    
    private var dateRangeSection: some View {
        Section("Date Range") {
            DatePicker("Start Date", selection: $viewModel.startDate, displayedComponents: .date)
            DatePicker("End Date", selection: $viewModel.endDate, displayedComponents: .date)
        }
    }
    
    private var exportButtonSection: some View {
        Section {
            Button(action: { viewModel.exportData() }) {
                HStack {
                    Spacer()
                    Image(systemName: "square.and.arrow.up")
                    Text("Export to Notion")
                    Spacer()
                }
            }
            .disabled(!viewModel.canExport)
        }
    }
}

struct ExportTypeRow: View {
    let type: NotionExportViewModel.ExportType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: type.icon)
                    .foregroundColor(isSelected ? .white : .blue)
                    .frame(width: 32, height: 32)
                    .background(isSelected ? Color.blue : Color.blue.opacity(0.1))
                    .cornerRadius(8)
                
                Text(type.rawValue)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .imageScale(.large)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                        .imageScale(.large)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

extension NotionExportViewModel {
    var canExport: Bool {
        guard isConnected && !selectedExportTypes.isEmpty else { return false }
        
        if createNewDatabase {
            return !newDatabaseName.isEmpty && !parentPageId.isEmpty
        } else {
            return selectedDatabaseId != nil
        }
    }
}