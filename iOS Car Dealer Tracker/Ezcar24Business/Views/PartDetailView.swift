import SwiftUI

struct PartDetailView: View {
    @ObservedObject var part: Part
    @ObservedObject private var permissionService = PermissionService.shared

    @State private var showReceiveStock = false
    @State private var showAddSale = false

    var body: some View {
        List {
            Section(header: Text("parts_detail_summary".localizedString)) {
                HStack {
                    Text("parts_detail_on_hand".localizedString)
                    Spacer()
                    Text(formatQuantity(part.quantityOnHand))
                        .foregroundColor(ColorTheme.primaryText)
                }
                if permissionService.canViewPartCost() {
                    HStack {
                        Text("parts_detail_inventory_value".localizedString)
                        Spacer()
                        Text(part.inventoryValue.asCurrency())
                            .foregroundColor(ColorTheme.primaryText)
                    }
                }
            }

            Section(header: Text("parts_detail_batches".localizedString)) {
                if batches.isEmpty {
                    Text("parts_detail_batches_empty".localizedString)
                        .foregroundColor(ColorTheme.secondaryText)
                } else {
                    ForEach(batches) { batch in
                        PartBatchRow(batch: batch, showCost: permissionService.canViewPartCost())
                    }
                }
            }
        }
        .navigationTitle(part.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if hasAnyActions {
                    Menu {
                        if permissionService.can(.managePartsInventory) {
                            Button("parts_receive_stock".localizedString) { showReceiveStock = true }
                        }
                        if permissionService.can(.createPartSale) {
                            Button("parts_new_sale".localizedString) { showAddSale = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundColor(ColorTheme.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showReceiveStock) {
            NavigationStack { ReceivePartStockView() }
        }
        .sheet(isPresented: $showAddSale) {
            NavigationStack { AddPartSaleView() }
        }
    }

    private var batches: [PartBatch] {
        part.activeBatches.sorted { ($0.purchaseDate ?? .distantPast) > ($1.purchaseDate ?? .distantPast) }
    }

    private var hasAnyActions: Bool {
        permissionService.can(.managePartsInventory) || permissionService.can(.createPartSale)
    }

    private func formatQuantity(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}

private struct PartBatchRow: View {
    let batch: PartBatch
    let showCost: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(batchTitle)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)
                Spacer()
                Text(batch.purchaseDate ?? Date(), style: .date)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }

            HStack {
                Text(String(format: "parts_detail_batch_remaining".localizedString, formatQuantity(remaining)))
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.secondaryText)
                Spacer()
                if showCost {
                    let unitCost = batch.unitCost?.decimalValue ?? 0
                    Text(unitCost.asCurrency())
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var batchTitle: String {
        let label = batch.batchLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let label, !label.isEmpty {
            return label
        }
        return "parts_detail_batch_default".localizedString
    }

    private var remaining: Decimal {
        batch.quantityRemaining?.decimalValue ?? 0
    }

    private func formatQuantity(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}
