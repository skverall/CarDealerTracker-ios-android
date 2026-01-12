import SwiftUI

struct PartsDashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @ObservedObject private var permissionService = PermissionService.shared

    @StateObject private var inventoryViewModel: PartsInventoryViewModel
    @StateObject private var salesViewModel: PartSalesViewModel

    @State private var selectedSection: PartsSection = .inventory
    @State private var showAddPart = false
    @State private var showReceiveStock = false
    @State private var showAddSale = false

    enum PartsSection: String, CaseIterable, Identifiable {
        case inventory
        case sales

        var id: String { rawValue }

        @MainActor
        var title: String {
            switch self {
            case .inventory: return "parts_inventory_title".localizedString
            case .sales: return "parts_sales_title".localizedString
            }
        }
    }

    init() {
        let context = PersistenceController.shared.container.viewContext
        _inventoryViewModel = StateObject(wrappedValue: PartsInventoryViewModel(context: context))
        _salesViewModel = StateObject(wrappedValue: PartSalesViewModel(context: context))
    }

    @State private var expandedCategories: Set<String> = [] // If empty, assume all expanded or handle logic
    @State private var showFilters = true

    // MARK: - Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Section Picker
                Picker("Section", selection: $selectedSection) {
                    ForEach(PartsSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(ColorTheme.background)
                
                // Search Bar
                searchBar
                    .background(ColorTheme.background)
                
                // Filters (Only for Inventory currently)
                if selectedSection == .inventory {
                    filtersBar
                        .background(ColorTheme.background)
                        .padding(.bottom, 8)
                }

                // Main Content
                switch selectedSection {
                case .inventory:
                    inventoryListWithGrouping
                case .sales:
                    salesList
                }
            }
            .background(ColorTheme.secondaryBackground.ignoresSafeArea())
            .navigationTitle("parts_tab_title".localizedString)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if hasAnyActions {
                        Menu {
                            if permissionService.can(.managePartsInventory) {
                                Button("parts_add_part".localizedString) { showAddPart = true }
                                Button("parts_receive_stock".localizedString) { showReceiveStock = true }
                            }
                            if permissionService.can(.createPartSale) {
                                Button("parts_new_sale".localizedString) { showAddSale = true }
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(ColorTheme.primary)
                        }
                    }
                }
            }
        }
        .id(regionSettings.selectedRegion.rawValue)
        .sheet(isPresented: $showAddPart) { NavigationStack { AddPartView() } }
        .sheet(isPresented: $showReceiveStock) { NavigationStack { ReceivePartStockView() } }
        .sheet(isPresented: $showAddSale) { NavigationStack { AddPartSaleView() } }
    }

    // MARK: - Filters
    private var filtersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Category Filter
                Menu {
                    Button(action: { inventoryViewModel.selectedCategory = nil }) {
                        Label("all".localizedString, systemImage: inventoryViewModel.selectedCategory == nil ? "checkmark" : "")
                    }
                    Divider()
                    ForEach(inventoryViewModel.getAllCategories(), id: \.self) { cat in
                        Button(action: { inventoryViewModel.selectedCategory = cat }) {
                            Label(cat, systemImage: inventoryViewModel.selectedCategory == cat ? "checkmark" : "")
                        }
                    }
                } label: {
                    filterPill(
                        title: inventoryViewModel.selectedCategory ?? "category".localizedString,
                        icon: "tag.fill",
                        isActive: inventoryViewModel.selectedCategory != nil
                    )
                }

                // Low Stock Toggle
                Button {
                    inventoryViewModel.showLowStockOnly.toggle()
                } label: {
                    filterPill(
                        title: "parts_filter_low_stock".localizedString,
                        icon: "exclamationmark.triangle.fill",
                        isActive: inventoryViewModel.showLowStockOnly
                    )
                }

                // Clear Filters
                if inventoryViewModel.selectedCategory != nil || inventoryViewModel.showLowStockOnly {
                    Button {
                        inventoryViewModel.selectedCategory = nil
                        inventoryViewModel.showLowStockOnly = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill").font(.caption)
                            Text("clear".localizedString).font(.footnote)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundColor(ColorTheme.secondaryText)
                        .background(Capsule().fill(Color.gray.opacity(0.1)))
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func filterPill(title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(title).font(.footnote).lineLimit(1)
            if !isActive {
                Image(systemName: "chevron.down").font(.caption2).opacity(0.6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 28)
        .foregroundColor(isActive ? .white : ColorTheme.secondaryText)
        .background(
            Capsule().fill(isActive ? ColorTheme.primary : Color.gray.opacity(0.1))
        )
    }

    // MARK: - Inventory List
    private var inventoryListWithGrouping: some View {
        List {
            // Summary Stats Section
            Section {
                VStack(spacing: 16) {
                    HStack(spacing: 20) {
                        summaryCard(
                            title: "parts_stats_total_value".localizedString,
                            value: inventoryViewModel.totalValue.asCurrency(),
                            icon: "scroll",
                            color: .blue
                        )
                        summaryCard(
                            title: "parts_stats_low_stock".localizedString,
                            value: "\(inventoryViewModel.lowStockCount)",
                            icon: "exclamationmark.triangle.fill",
                            color: inventoryViewModel.lowStockCount > 0 ? .orange : .green
                        )
                    }
                     HStack {
                         Text(String(format: "parts_stats_items_count".localizedString, inventoryViewModel.activeItemCount))
                             .font(.caption)
                             .foregroundColor(ColorTheme.secondaryText)
                        Spacer()
                    }
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }

            // Grouped Items
            ForEach(groupedParts, id: \.category) { group in
                Section {
                    if expandedCategories.contains(group.category) {
                        EmptyView()
                    } else {
                        ForEach(group.parts) { part in
                            NavigationLink(destination: PartDetailView(part: part)) {
                                PartRow(part: part, canViewCost: permissionService.canViewPartCost())
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(ColorTheme.cardBackground)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                } header: {
                    Button {
                        if expandedCategories.contains(group.category) {
                            expandedCategories.remove(group.category)
                        } else {
                            expandedCategories.insert(group.category)
                        }
                    } label: {
                        HStack {
                            Text(group.category)
                                .font(.headline)
                                .foregroundColor(ColorTheme.primaryText)
                            Spacer()
                            Text("\(group.parts.count)")
                                .font(.subheadline)
                                .foregroundColor(ColorTheme.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            Image(systemName: expandedCategories.contains(group.category) ? "chevron.right" : "chevron.down")
                                .font(.caption)
                                .foregroundColor(ColorTheme.secondaryText)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            // Add padding at bottom
            Section {
                Color.clear.frame(height: 60).listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .refreshable {
            inventoryViewModel.fetchParts()
        }
    }
    
    // Grouping Logic
    private var groupedParts: [(category: String, parts: [Part])] {
         let groups = Dictionary(grouping: inventoryViewModel.parts) { part in
             let cat = part.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
             return cat.isEmpty ? "parts_uncategorized".localizedString : cat
         }
         return groups.map { (category: $0.key, parts: $0.value) }
             .sorted { $0.category < $1.category }
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                    Text(title)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(ColorTheme.primaryText)
            }
            Spacer()
        }
        .padding(12)
        .background(ColorTheme.cardBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }


    
    // MARK: - Search Bar
    private var searchBar: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(ColorTheme.secondaryText)
                TextField(searchPlaceholder, text: activeSearchText)
                    .foregroundColor(ColorTheme.primaryText)
                    .submitLabel(.search)
                
                if !activeSearchText.wrappedValue.isEmpty {
                    Button(action: { activeSearchText.wrappedValue = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                }
            }
            .padding(10)
            .background(ColorTheme.secondaryBackground)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    private var activeSearchText: Binding<String> {
        switch selectedSection {
        case .inventory:
            return $inventoryViewModel.searchText
        case .sales:
            return $salesViewModel.searchText
        }
    }

    private var searchPlaceholder: String {
        switch selectedSection {
        case .inventory:
            return "parts_search_inventory_placeholder".localizedString
        case .sales:
            return "parts_search_sales_placeholder".localizedString
        }
    }

    // MARK: - Sales List (Existing logic adapted)
    private var salesList: some View {
        Group {
            if salesViewModel.saleItems.isEmpty {
                 EmptyStateView(
                    title: "parts_sales_empty_title".localizedString,
                    message: "parts_sales_empty_message".localizedString,
                    systemImage: "cart"
                )
            } else {
                List {
                    ForEach(salesViewModel.saleItems) { item in
                        PartSaleRow(
                            item: item,
                            canViewProfit: permissionService.canViewPartProfit()
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    .onDelete(perform: deletePartSales)
                }
                .listStyle(.plain)
                .refreshable {
                    salesViewModel.fetchSales()
                }
            }
        }
    }

    private func deletePartSales(at offsets: IndexSet) {
        guard canDeleteRecords else { return }
        for index in offsets {
            let sale = salesViewModel.saleItems[index].sale
            salesViewModel.deleteSale(sale)
        }
    }

    private var hasAnyActions: Bool {
        permissionService.can(.managePartsInventory) || permissionService.can(.createPartSale)
    }

    private var canDeleteRecords: Bool {
        if case .signedIn = sessionStore.status {
            return permissionService.can(.deleteRecords)
        }
        return true
    }
}

private struct PartRow: View {
    let part: Part
    let canViewCost: Bool

    private var quantityText: String {
        formatQuantity(part.quantityOnHand)
    }

    private var valueText: String {
        guard canViewCost else { return "" }
        return part.inventoryValue.asCurrency()
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(part.displayName)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)
                
                // Display code if available
                if let code = part.code, !code.isEmpty {
                    Text(code)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(ColorTheme.primary)
                }

                if let category = part.category, !category.isEmpty {
                    Text(category)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(quantityText)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)
                if canViewCost {
                    Text(valueText)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    private func formatQuantity(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}

private struct PartSaleRow: View {
    let item: PartSaleItem
    let canViewProfit: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.buyerName)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)
                Spacer()
                Text(item.saleDate, style: .date)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }

            if !item.itemsSummary.isEmpty {
                Text(item.itemsSummary)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.secondaryText)
            }

            HStack {
                Text(item.totalAmount.asCurrency())
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)
                Spacer()
                if canViewProfit {
                    let profit = item.profit
                    Text(profit.asCurrency())
                        .font(.subheadline)
                        .foregroundColor(profit >= 0 ? ColorTheme.success : ColorTheme.danger)
                }
            }
        }
        .padding(16)
        .cardStyle()
    }
}

private struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 60))
                .foregroundColor(ColorTheme.primary.opacity(0.2))
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(ColorTheme.primaryText)
            Text(message)
                .font(.body)
                .foregroundColor(ColorTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}
