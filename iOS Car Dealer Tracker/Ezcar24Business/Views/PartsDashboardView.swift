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

    // Initialize view models
    init() {
        let context = PersistenceController.shared.container.viewContext
        _inventoryViewModel = StateObject(wrappedValue: PartsInventoryViewModel(context: context))
        _salesViewModel = StateObject(wrappedValue: PartSalesViewModel(context: context))
    }

    enum PartsSection: String, CaseIterable, Identifiable {
        case inventory, sales
        var id: String { rawValue }
        
        @MainActor
        var title: String {
            switch self {
            case .inventory: return "parts_inventory_title".localizedString
            case .sales: return "parts_sales_title".localizedString
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Dashboard Header (Stats)
                        dashboardHeader
                        
                        // 2. Control Bar (Filters & Segment)
                        controlBar
                        
                        // 3. Content List
                        contentList
                            .padding(.bottom, 100) // Space for scroll
                    }
                    .padding(.top, 10)
                }
                .refreshable {
                    if selectedSection == .inventory {
                        inventoryViewModel.fetchParts()
                    } else {
                        salesViewModel.fetchSales()
                    }
                }
            }
            .navigationTitle("parts_tab_title".localizedString)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    menuActions
                }
            }
            .sheet(isPresented: $showAddPart) { NavigationStack { AddPartView() } }
            .sheet(isPresented: $showReceiveStock) { NavigationStack { ReceivePartStockView() } }
            .sheet(isPresented: $showAddSale) { NavigationStack { AddPartSaleView() } }
        }
    }
    
    // MARK: - Dashboard Header
    private var dashboardHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Total Value Card
                StatsCard(
                    title: "parts_stats_total_value".localizedString,
                    value: inventoryViewModel.totalValue.asCurrencyCompact(),
                    icon: "shippingbox.fill", // More "Inventory" feeling
                    gradient: LinearGradient(colors: [ColorTheme.primary, ColorTheme.primary.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    shadowColor: ColorTheme.primary
                )
                
                // Low Stock Card
                StatsCard(
                    title: "parts_stats_low_stock".localizedString,
                    value: "\(inventoryViewModel.lowStockCount)",
                    icon: "exclamationmark.triangle.fill",
                    gradient: LinearGradient(colors: [.orange, .red.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    shadowColor: .orange,
                    isWarning: inventoryViewModel.lowStockCount > 0
                )
                
                // Item Count (Subtle)
                StatsCard(
                    title: "parts_stats_items_count_short".localizedString, // "Items"
                    value: "\(inventoryViewModel.activeItemCount)",
                    icon: "number.circle.fill",
                    gradient: LinearGradient(colors: [Color.gray, Color.gray.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    shadowColor: .gray
                )
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Control Bar
    private var controlBar: some View {
        VStack(spacing: 12) {
            // Segment Switcher
            HStack(spacing: 0) {
                ForEach(PartsSection.allCases) { section in
                    Button {
                        withAnimation(.snappy(duration: 0.24, extraBounce: 0.03)) {
                            selectedSection = section
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(section.title)
                                .font(.headline)
                                .fontWeight(selectedSection == section ? .semibold : .medium)
                                .foregroundColor(selectedSection == section ? ColorTheme.primary : ColorTheme.secondaryText)
                            
                            // Indicator
                            if selectedSection == section {
                                Capsule()
                                    .fill(ColorTheme.primary)
                                    .frame(height: 3)
                                    .matchedGeometryEffect(id: "TabIndicator", in: namespace)
                            } else {
                                Capsule()
                                    .fill(Color.clear)
                                    .frame(height: 3)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            
            // Search Input
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(ColorTheme.secondaryText)
                TextField(searchPlaceholder, text: activeSearchText)
/*                  .textFieldStyle(.plain) */
                    .submitLabel(.search)
                if !activeSearchText.wrappedValue.isEmpty {
                    Button(action: { activeSearchText.wrappedValue = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                }
            }
            .padding(10)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(10)
            .padding(.horizontal, 16)

            // Filters (Inventory Only)
            if selectedSection == .inventory {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Menu {
                            Button("all".localizedString) { inventoryViewModel.selectedCategory = nil }
                            Divider()
                            ForEach(inventoryViewModel.getAllCategories(), id: \.self) { cat in
                                Button(cat) { inventoryViewModel.selectedCategory = cat }
                            }
                        } label: {
                            PartsFilterChip(
                                title: inventoryViewModel.selectedCategory ?? "category".localizedString,
                                icon: "tag.fill",
                                isSelected: inventoryViewModel.selectedCategory != nil
                            )
                        }

                        Button {
                            withAnimation { inventoryViewModel.showLowStockOnly.toggle() }
                        } label: {
                            PartsFilterChip(
                                title: "parts_filter_low_stock".localizedString,
                                icon: "exclamationmark.triangle.fill",
                                isSelected: inventoryViewModel.showLowStockOnly,
                                selectedColor: .orange
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
    
    // MARK: - Content List
    private var contentList: some View {
        VStack(spacing: 16) {
            switch selectedSection {
            case .inventory:
                ForEach(groupedParts, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        // Section Header
                        HStack {
                            Text(group.category)
                                .font(.callout)
                                .fontWeight(.semibold)
                                .foregroundColor(ColorTheme.secondaryText)
                                .textCase(.uppercase)
                            Spacer()
                            Text("\(group.parts.count)")
                                .font(.caption)
                                .foregroundColor(ColorTheme.secondaryText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(uiColor: .tertiarySystemFill))
                                .cornerRadius(4)
                        }
                        .padding(.leading, 16)
                        .padding(.bottom, 6)
                        .padding(.top, 8)

                        // Items Group
                        VStack(spacing: 0) {
                            ForEach(group.parts.indices, id: \.self) { index in
                                let part = group.parts[index]
                                NavigationLink(destination: PartDetailView(part: part)) {
                                    PartRowNew(part: part, canViewCost: permissionService.canViewPartCost())
                                }
                                .buttonStyle(PlainButtonStyle()) // Important for interactions
                                
                                if index < group.parts.count - 1 {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(10)
                        .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
                    }
                    .padding(.horizontal, 16)
                }
                
            case .sales:
                VStack(spacing: 0) {
                    ForEach(salesViewModel.saleItems) { item in
                        Button(action: {}) { // Sales typically don't have detail view yet, just placeholder or logic
                            PartSaleRowNew(item: item, canViewProfit: permissionService.canViewPartProfit())
                        } // Simple wrapper, action could be show receipt
                        .buttonStyle(PlainButtonStyle())
                        
                        Divider().padding(.leading, 16)
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
            }
        }
    }
    
    // MARK: - Actions Menu (Top Right)
    private var menuActions: some View {
        Menu {
            if permissionService.can(.managePartsInventory) {
                Button(action: { showAddPart = true }) {
                    Label("parts_add_part".localizedString, systemImage: "plus")
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
            Image(systemName: "plus.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 20))
                .foregroundColor(ColorTheme.primary)
        }
    }

    @Namespace private var namespace

    // MARK: - Helpers
    private var groupedParts: [(category: String, parts: [Part])] {
         let groups = Dictionary(grouping: inventoryViewModel.parts) { part in
             let cat = part.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
             return cat.isEmpty ? "parts_uncategorized".localizedString : cat.localizedString
         }
         return groups.map { (category: $0.key, parts: $0.value) }
             .sorted { $0.category < $1.category }
    }
    
    private var activeSearchText: Binding<String> {
        switch selectedSection {
        case .inventory: return $inventoryViewModel.searchText
        case .sales: return $salesViewModel.searchText
        }
    }
    
    private var searchPlaceholder: String {
        switch selectedSection {
        case .inventory: return "parts_search_inventory_placeholder".localizedString
        case .sales: return "parts_search_sales_placeholder".localizedString
        }
    }
}

// MARK: - Subviews

struct StatsCard: View {
    let title: String
    let value: String
    let icon: String
    let gradient: LinearGradient
    var shadowColor: Color
    var isWarning: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(10) // Reduced padding
        .frame(width: 130, height: 90) // Reduced frame size
        .background(gradient)
        .cornerRadius(12) // Reduced corner radius
        .shadow(color: shadowColor.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

struct PartsFilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    var selectedColor: Color = ColorTheme.primary
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? selectedColor.opacity(0.15) : Color(uiColor: .tertiarySystemFill))
        .foregroundColor(isSelected ? selectedColor : ColorTheme.secondaryText)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(isSelected ? selectedColor : Color.clear, lineWidth: 1)
        )
    }
}

struct PartRowNew: View {
    let part: Part
    let canViewCost: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(part.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(ColorTheme.primaryText)
                
                if let code = part.code, !code.isEmpty {
                    Text(code)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatQuantity(part.quantityOnHand))
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundColor(part.quantityOnHand <= 2 ? .orange : ColorTheme.primaryText)
                
                if canViewCost {
                    Text(part.inventoryValue.asCurrency())
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
        }
        .padding(.vertical, 10) // Reduced padding
        .padding(.horizontal, 16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }
    
    private func formatQuantity(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}

struct PartSaleRowNew: View {
    let item: PartSaleItem
    let canViewProfit: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.buyerName)
                    .font(.body)
                    .fontWeight(.medium)
                Text(item.saleDate, style: .date)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.totalAmount.asCurrency())
                    .font(.body)
                    .fontWeight(.semibold)
                
                if canViewProfit {
                    Text(item.profit.asCurrency())
                        .font(.caption)
                        .foregroundColor(item.profit >= 0 ? ColorTheme.success : ColorTheme.danger)
                }
            }
        }
        .padding(.vertical, 10) // Reduced padding
        .padding(.horizontal, 16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }
}
