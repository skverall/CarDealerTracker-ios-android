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
                    icon: "shippingbox.fill",
                    gradient: ColorTheme.premiumAssetsGradient,
                    shadowColor: ColorTheme.primary
                )
                
                // Low Stock Card
                StatsCard(
                    title: "parts_stats_low_stock".localizedString,
                    value: "\(inventoryViewModel.lowStockCount)",
                    icon: "exclamationmark.triangle.fill",
                    gradient: LinearGradient(colors: [ColorTheme.danger, ColorTheme.accent], startPoint: .topLeading, endPoint: .bottomTrailing),
                    shadowColor: ColorTheme.danger,
                    isWarning: inventoryViewModel.lowStockCount > 0
                )
                
                // Item Count (Subtle)
                StatsCard(
                    title: "parts_stats_items_count_short".localizedString,
                    value: "\(inventoryViewModel.activeItemCount)",
                    icon: "number.circle.fill",
                    gradient: LinearGradient(colors: [ColorTheme.purple, ColorTheme.secondary], startPoint: .topLeading, endPoint: .bottomTrailing),
                    shadowColor: ColorTheme.purple
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Control Bar
    private var controlBar: some View {
        VStack(spacing: 12) {
            // Segment Switcher in premium capsule style
            HStack(spacing: 4) {
                ForEach(PartsSection.allCases) { section in
                    Button {
                        withAnimation(.snappy(duration: 0.24, extraBounce: 0.03)) {
                            selectedSection = section
                        }
                    } label: {
                        Text(section.title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(selectedSection == section ? .white : ColorTheme.secondaryText)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                ZStack {
                                    if selectedSection == section {
                                        Capsule()
                                            .fill(ColorTheme.primary)
                                            .matchedGeometryEffect(id: "TabIndicator", in: namespace)
                                    }
                                }
                            )
                    }
                }
            }
            .padding(4)
            .background(ColorTheme.cardBackground)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(ColorTheme.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            
            // Search Input
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(ColorTheme.secondaryText)
                TextField(searchPlaceholder, text: activeSearchText)
                    .submitLabel(.search)
                if !activeSearchText.wrappedValue.isEmpty {
                    Button(action: { activeSearchText.wrappedValue = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                }
            }
            .padding(10)
            .background(ColorTheme.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(ColorTheme.primary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 3)

            // Filters (Inventory Only)
            if selectedSection == .inventory {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Menu {
                            Button("all".localizedString) { inventoryViewModel.selectedCategory = nil }
                            Divider()
                            ForEach(inventoryViewModel.getAllCategories(), id: \.self) { cat in
                                Button(localizedPartCategory(cat)) { inventoryViewModel.selectedCategory = cat }
                            }
                        } label: {
                            PartsFilterChip(
                                title: inventoryViewModel.selectedCategory.map(localizedPartCategory) ?? "category".localizedString,
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
        VStack(spacing: 20) {
            switch selectedSection {
            case .inventory:
                ForEach(groupedParts, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        // Section Header
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(ColorTheme.primary.opacity(0.1))
                                    .frame(width: 26, height: 26)
                                
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(ColorTheme.primary)
                            }
                            
                            Text(localizedPartCategory(group.category))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(ColorTheme.secondaryText)
                            
                            Spacer()
                            
                            Text("\(group.parts.count)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(ColorTheme.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(ColorTheme.primary.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 4)

                        // Items Group
                        VStack(spacing: 0) {
                            ForEach(group.parts.indices, id: \.self) { index in
                                let part = group.parts[index]
                                NavigationLink(destination: PartDetailView(part: part)) {
                                    PartRowNew(part: part, canViewCost: permissionService.canViewPartCost())
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                if index < group.parts.count - 1 {
                                    Divider().opacity(0.5)
                                }
                            }
                        }
                        .cardStyle()
                    }
                    .padding(.horizontal, 16)
                }
                
            case .sales:
                VStack(spacing: 0) {
                    ForEach(salesViewModel.saleItems) { item in
                        Button(action: {}) {
                            PartSaleRowNew(item: item, canViewProfit: permissionService.canViewPartProfit())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if item.id != salesViewModel.saleItems.last?.id {
                            Divider().opacity(0.5)
                        }
                    }
                }
                .cardStyle()
                .padding(.horizontal, 16)
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
              return cat.isEmpty ? "__uncategorized" : cat
         }
         return groups.map { (category: $0.key, parts: $0.value) }
             .sorted { localizedPartCategory($0.category) < localizedPartCategory($1.category) }
    }

    private func localizedPartCategory(_ category: String) -> String {
        switch category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "__uncategorized", "":
            return "parts_uncategorized".localizedString
        case "engine":
            return "parts_category_engine".localizedString
        case "body":
            return "parts_category_body".localizedString
        case "electrical":
            return "parts_category_electrical".localizedString
        case "suspension":
            return "parts_category_suspension".localizedString
        case "interior":
            return "parts_category_interior".localizedString
        case "other":
            return "parts_category_other".localizedString
        default:
            return category
        }
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(12)
        .frame(width: 140, height: 105)
        .background(gradient)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: shadowColor.opacity(0.25), radius: 6, x: 0, y: 3)
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
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(ColorTheme.primary.opacity(0.06))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "shippingbox")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ColorTheme.primary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(part.displayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(ColorTheme.primaryText)
                
                if let code = part.code, !code.isEmpty {
                    Text(code)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ColorTheme.primary.opacity(0.06))
                        .cornerRadius(6)
                        .foregroundColor(ColorTheme.primary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                // Rounded pill warning quantity badge
                Text("\(formatQuantity(part.quantityOnHand))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(part.quantityOnHand <= 2 ? .white : ColorTheme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(part.quantityOnHand <= 2 ? ColorTheme.danger : ColorTheme.primary.opacity(0.08))
                    )
                
                if canViewCost {
                    Text(part.inventoryValue.asCurrency())
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.clear)
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
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(ColorTheme.success.opacity(0.08))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "cart.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ColorTheme.success)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.buyerName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(ColorTheme.primaryText)
                Text(item.saleDate, style: .date)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(ColorTheme.secondaryText)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.totalAmount.asCurrency())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(ColorTheme.primaryText)
                
                if canViewProfit {
                    Text(item.profit.asCurrency())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(item.profit >= 0 ? ColorTheme.success : ColorTheme.danger)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.clear)
    }
}
