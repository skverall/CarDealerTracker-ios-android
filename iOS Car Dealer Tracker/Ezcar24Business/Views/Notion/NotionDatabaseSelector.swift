import SwiftUI

struct NotionDatabaseSelector: View {
    @ObservedObject var viewModel: NotionExportViewModel
    @State private var showCreateDatabaseSheet = false
    @State private var newDatabaseName = ""
    @State private var selectedTemplateType: NotionExportType = .vehicles
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Select Destination Database")
                    .font(.headline)
                Spacer()
                Button(action: { Task { await viewModel.fetchDatabases() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isConnecting)
            }
            
            if viewModel.isConnecting {
                HStack {
                    ProgressView()
                    Text("Loading databases...")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else if viewModel.availableDatabases.isEmpty {
                // No databases found
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No databases found")
                        .font(.headline)
                    
                    Text("Create a new database to export your data")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        
                    Button(action: { showCreateDatabaseSheet = true }) {
                        Label("Create New Database", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                // Database list
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Existing databases
                        ForEach(viewModel.availableDatabases) { database in
                            DatabaseCard(
                                database: database,
                                isSelected: viewModel.selectedDatabaseId == database.id,
                                onTap: {
                                    withAnimation {
                                        viewModel.selectedDatabaseId = database.id
                                        viewModel.createNewDatabase = false
                                    }
                                }
                            )
                        }
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        // Create new database option
                        CreateDatabaseCard(
                            isSelected: viewModel.createNewDatabase,
                            onTap: {
                                withAnimation {
                                    viewModel.createNewDatabase = true
                                    viewModel.selectedDatabaseId = nil
                                    showCreateDatabaseSheet = true
                                }
                            }
                        )
                    }
                }
                .frame(maxHeight: 400)
            }
        }
        .sheet(isPresented: $showCreateDatabaseSheet) {
            CreateDatabaseSheet(
                viewModel: viewModel,
                isPresented: $showCreateDatabaseSheet,
                databaseName: $newDatabaseName,
                selectedType: $selectedTemplateType
            )
        }
    }
}

// MARK: - Database Card

struct DatabaseCard: View {
    let database: NotionDatabase
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.title3)
                
                // Database icon
                Image(systemName: "table.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 40, height: 40)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                
                // Database info
                VStack(alignment: .leading, spacing: 4) {
                    Text(database.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text("\(database.properties.count) properties")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // External link indicator
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Create Database Card

struct CreateDatabaseCard: View {
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .secondary)
                    .font(.title3)
                
                // Add icon
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                    .frame(width: 40, height: 40)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create New Database")
                        .font(.headline)
                    
                    Text("Set up a database with the proper schema")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
            .background(isSelected ? Color.green.opacity(0.1) : Color.secondary.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.green : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Create Database Sheet

struct CreateDatabaseSheet: View {
    @ObservedObject var viewModel: NotionExportViewModel
    @Binding var isPresented: Bool
    @Binding var databaseName: String
    @Binding var selectedType: NotionExportType
    
    @State private var isCreating = false
    @State private var showPreview = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Database Name") {
                    TextField("Enter database name", text: $databaseName)
                        .textInputAutocapitalization(.words)
                }
                
                Section("Database Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(NotionExportType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectedType.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button(action: { showPreview.toggle() }) {
                            Label(
                                showPreview ? "Hide Schema Preview" : "Show Schema Preview",
                                systemImage: showPreview ? "eye.slash" : "eye"
                            )
                            .font(.caption)
                        }
                    }
                    .padding(.top, 8)
                }
                
                if showPreview {
                    Section("Schema Preview") {
                        SchemaPreviewView(type: selectedType)
                    }
                }
                
                Section {
                    Button(action: createDatabase) {
                        if isCreating {
                            HStack {
                                ProgressView()
                                Text("Creating...")
                            }
                        } else {
                            Text("Create Database")
                        }
                    }
                    .disabled(databaseName.isEmpty || isCreating)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("New Database")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private func createDatabase() {
        isCreating = true
        
        Task { @MainActor in
            defer { isCreating = false }
            do {
                _ = try await viewModel.createNotionDatabase(name: databaseName, type: selectedType)
                isPresented = false
            } catch {
                viewModel.errorMessage = "Failed to create database: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Schema Preview View

struct SchemaPreviewView: View {
    let type: NotionExportType
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let properties = NotionDatabaseTemplates.schema(for: type)
            
            ForEach(Array(properties.keys.sorted()), id: \.self) { key in
                if let property = properties[key] {
                    HStack {
                        Image(systemName: iconForPropertyType(property))
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        
                        Text(key)
                            .font(.caption)
                        
                        Spacer()
                        
                        Text(property.type)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func iconForPropertyType(_ property: NotionPropertyDefinition) -> String {
        switch property.type {
        case "title":
            return "textformat"
        case "rich_text":
            return "text.quote"
        case "number":
            return "number"
        case "select":
            return "checkmark.circle"
        case "date":
            return "calendar"
        case "formula":
            return "function"
        case "url":
            return "link"
        case "email":
            return "envelope"
        case "phone_number":
            return "phone"
        default:
            return "doc.text"
        }
    }
}

private extension NotionExportType {
    var displayName: String {
        rawValue
    }
    
    var description: String {
        switch self {
        case .vehicles:
            return "Vehicle inventory schema"
        case .leads:
            return "Lead management schema"
        case .sales:
            return "Sales history schema"
        }
    }
}

// MARK: - Preview

struct NotionDatabaseSelector_Previews: PreviewProvider {
    static var previews: some View {
        NotionDatabaseSelector(viewModel: NotionExportViewModel())
            .padding()
    }
}
