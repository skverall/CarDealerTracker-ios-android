import SwiftUI

struct ExportProgressView: View {
    let progress: Double
    let currentItem: String
    let exportedCount: Int
    let totalCount: Int
    
    @State private var showCancelConfirmation = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    
                    Text("Exporting to Notion")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                // Progress section
                VStack(spacing: 12) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 12)
                            
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * progress, height: 12)
                                .animation(.easeInOut(duration: 0.3), value: progress)
                        }
                    }
                    .frame(height: 12)
                    
                    // Progress text
                    HStack {
                        Text("\(Int(progress * 100))%")
                            .font(.headline)
                            .foregroundColor(.blue)
                        
                        Spacer()
                        
                        Text("\(exportedCount) / \(totalCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Current item
                if !currentItem.isEmpty {
                    VStack(spacing: 8) {
                        Text("Currently exporting:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(currentItem)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                }
                
                // Cancel button
                Button(action: { showCancelConfirmation = true }) {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(radius: 20)
            )
            .padding(32)
        }
        .alert("Cancel Export?", isPresented: $showCancelConfirmation) {
            Button("Continue Exporting", role: .cancel) { }
            Button("Cancel", role: .destructive) {
                // Cancel the export operation
            }
        } message: {
            Text("Are you sure you want to cancel the export? Progress will be lost.")
        }
    }
}

// MARK: - Export Result View

struct ExportResultView: View {
    let results: ExportResults
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Success icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
            }
            
            Text("Export Complete!")
                .font(.title2)
                .fontWeight(.bold)
            
            // Summary
            VStack(spacing: 12) {
                if let vehiclesResult = results.vehiclesResult {
                    ResultRow(
                        icon: "car.fill",
                        title: "Vehicles",
                        successCount: vehiclesResult.successCount,
                        failedCount: vehiclesResult.failedCount
                    )
                }
                
                if let leadsResult = results.leadsResult {
                    ResultRow(
                        icon: "person.2.fill",
                        title: "Leads",
                        successCount: leadsResult.successCount,
                        failedCount: leadsResult.failedCount
                    )
                }
                
                if let salesResult = results.salesResult {
                    ResultRow(
                        icon: "dollarsign.circle.fill",
                        title: "Sales",
                        successCount: salesResult.successCount,
                        failedCount: salesResult.failedCount
                    )
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            
            // Total
            HStack {
                Text("Total Exported:")
                    .font(.headline)
                Spacer()
                Text("\(results.totalSuccessCount)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
            .padding(.horizontal)
            
            if results.totalFailedCount > 0 {
                HStack {
                    Text("Failed:")
                        .font(.subheadline)
                    Spacer()
                    Text("\(results.totalFailedCount)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
                .padding(.horizontal)
            }
            
            Button(action: onDismiss) {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.top)
        }
        .padding()
    }
}

struct ResultRow: View {
    let icon: String
    let title: String
    let successCount: Int
    let failedCount: Int
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            HStack(spacing: 12) {
                Label("\(successCount)", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundColor(.green)
                
                if failedCount > 0 {
                    Label("\(failedCount)", systemImage: "xmark")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }
}

// MARK: - Preview

struct ExportProgressView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ExportProgressView(
                progress: 0.65,
                currentItem: "2023 Toyota Camry - ABC123",
                exportedCount: 65,
                totalCount: 100
            )
            
            ExportResultView(
                results: ExportResults(
                    vehiclesResult: ExportResult(
                        successCount: 45,
                        failedCount: 2,
                        failedIdentifiers: [],
                        databaseUrl: nil
                    ),
                    leadsResult: ExportResult(
                        successCount: 30,
                        failedCount: 0,
                        failedIdentifiers: [],
                        databaseUrl: nil
                    ),
                    salesResult: nil
                ),
                onDismiss: {}
            )
            .padding()
            .previewDisplayName("Result View")
        }
    }
}