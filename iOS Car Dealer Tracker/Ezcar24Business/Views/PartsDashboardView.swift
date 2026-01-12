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

    @State private var expandedCategories: Set<String> = []
    @State private var showFilters = true

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // Custom Section Picker
                    customSegmentedControl
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
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
                
                // Floating Action Button (FAB)
                if hasAnyActions {
                   floatingActionButton
                        .padding()
                }
            }
            .navigationTitle("parts_tab_title".localizedString)
            .navigationBarTitleDisplayMode(.large)
        }
        .id(regionSettings.selectedRegion.rawValue)
        .sheet(isPresented: $showAddPart) { NavigationStack { AddPartView() } }
        .sheet(isPresented: $showReceiveStock) { NavigationStack { ReceivePartStockView() } }
        .sheet(isPresented: $showAddSale) { NavigationStack { AddPartSaleView() } }
    }
    
    // MARK: - Custom Segmented Control
    private var customSegmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(PartsSection.allCases) { section in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedSection = section
                    }
                } label: {
                    Text(section.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(selectedSection == section ? ColorTheme.primaryText : ColorTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            ZStack {
                                if selectedSection == section {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(ColorTheme.cardBackground)
                                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                                        .matchedGeometryEffect(id: "SEGMENT", in: namespace)
                                }
                            }
                        )
                }
            }
        }
        .padding(4)
        .background(ColorTheme.secondaryBackground) // Light gray background for the track
        .cornerRadius(12)
    }
    
    @Namespace private var namespace

    // MARK: - Floating Action Button
    private var floatingActionButton: some View {
        Menu {
            if permissionService.can(.managePartsInventory) {
                Button(action: { showAddPart = true }) {
                    Label("parts_add_part".localizedString, systemImage: "plus.circle")
                }
                Button(action: { showReceiveStock = true }) {
                    Label("parts_receive_stock".localizedString, systemImage: "shippingbox")
                }
            }
            if permissionService.can(.createPartSale) {
                Button(action: { showAddSale = true }) {
                    Label("parts_new_sale".localizedString, systemImage: "cart")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(ColorTheme.primary)
                .clipShape(Circle())
                .shadow(color: ColorTheme.primary.opacity(0.4), radius: 8, x: 0, y: 4)
        }
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
                    withAnimation {
                        inventoryViewModel.showLowStockOnly.toggle()
                    }
                } label: {
                    filterPill(
                        title: "parts_filter_low_stock".localizedString,
                        icon: "exclamationmark.triangle.fill",
                        isActive: inventoryViewModel.showLowStockOnly,
                        activeColor: .orange
                    )
                }

                // Clear Filters
                if inventoryViewModel.selectedCategory != nil || inventoryViewModel.showLowStockOnly {
                    Button {
                        withAnimation {
                            inventoryViewModel.selectedCategory = nil
                            inventoryViewModel.showLowStockOnly = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill").font(.caption)
                            Text("clear".localizedString).font(.footnote)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundColor(ColorTheme.secondaryText)
                        .background(Capsule().fill(Color.gray.opacity(0.1)))
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func filterPill(title: String, icon: String, isActive: Bool, activeColor: Color = ColorTheme.primary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(title).font(.footnote).fontWeight(.medium).lineLimit(1)
            if !isActive {
                Image(systemName: "chevron.down").font(.caption2).opacity(0.6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundColor(isActive ? .white : ColorTheme.primaryText)
        .background(
            Capsule().fill(isActive ? activeColor : ColorTheme.cardBackground)
                .shadow(color: isActive ? activeColor.opacity(0.3) : Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }

    // MARK: - Inventory List
    private var inventoryListWithGrouping: some View {
        List {
            // Summary Stats Section
            Section {
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        summaryCard(
                            title: "parts_stats_total_value".localizedString,
                            value: inventoryViewModel.totalValue.asCurrency(),
                            icon: "scroll.fill",
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
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            .listSectionSeparator(.hidden)

            // Grouped Items
            ForEach(groupedParts, id: \.category) { group in
                Section {
                    if expandedCategories.contains(group.category) {
                        EmptyView()
                    } else {
                        ForEach(group.parts) { part in
                            ZStack {
                                NavigationLink(destination: PartDetailView(part: part)) {
                                    EmptyView()
                                }
                                .opacity(0) // Hide the chevron

                                PartRow(part: part, canViewCost: permissionService.canViewPartCost())
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                } header: {
                    Button {
                        withAnimation {
                            if expandedCategories.contains(group.category) {
                                expandedCategories.remove(group.category)
                            } else {
                                expandedCategories.insert(group.category)
                            }
                        }
                    } label: {
                        HStack {
                            Text(group.category)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(ColorTheme.primaryText)
                            Spacer()
                            Text("\(group.parts.count)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(ColorTheme.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(ColorTheme.secondaryText)
                                .rotationEffect(.degrees(expandedCategories.contains(group.category) ? 0 : 90))
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listSectionSeparator(.hidden)
            }
            // Add padding at bottom
            Section {
                Color.clear.frame(height: 80).listRowBackground(Color.clear)
            }
            .listSectionSeparator(.hidden)
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
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.custom("system", size: 18))
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(ColorTheme.secondaryText)
                }
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(ColorTheme.primaryText)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(16)
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack {
            HStack(spacing: 8) {
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
            .padding(12)
            .background(ColorTheme.secondaryBackground)
            .cornerRadius(12)
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
                    
                    Section {
                         Color.clear.frame(height: 80).listRowBackground(Color.clear)
                    }
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
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ColorTheme.primary.opacity(0.1))
                        .foregroundColor(ColorTheme.primary)
                        .cornerRadius(4)
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
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(ColorTheme.secondaryText)
                .padding(.leading, 8)
        }
        .padding(16)
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
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
        .background(ColorTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
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
