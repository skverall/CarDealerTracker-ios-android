//
//  ContentView.swift
//  Ezcar24Business
//
//  Main navigation container
//

import SwiftUI
#if DEBUG
import Supabase
#endif

struct ContentView: View {
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSessionState: AppSessionState
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @ObservedObject private var permissionService = PermissionService.shared
    @State private var selectedTab: Tab = .dashboard
    @State private var showProfileSheet = false
    @State private var showGuestAccountPrompt = false
    @State private var tabBarHeight: CGFloat = 72

    enum Tab: Int, CaseIterable, Identifiable {
        case dashboard = 0
        case expenses = 1
        case vehicles = 2
        case parts = 3
        case sales = 4
        case clients = 5
        
        var id: Int { rawValue }
        
        @MainActor var title: String {
            switch self {
            case .dashboard: return "dashboard_title".localizedString
            case .expenses: return "expenses".localizedString
            case .vehicles: return "vehicles".localizedString
            case .parts: return "parts_tab_title".localizedString
            case .sales: return "sales".localizedString
            case .clients: return "clients".localizedString
            }
        }
        
        var icon: String {
            switch self {
            case .dashboard: return "house.fill"
            case .expenses: return "creditcard" // Used standard SF symbol as per existing code
            case .vehicles: return "car.fill"
            case .parts: return "shippingbox"
            case .sales: return "dollarsign.circle.fill"
            case .clients: return "person.2"
            }
        }

        var color: Color {
            switch self {
            case .dashboard: return .blue
            case .expenses: return .red
            case .vehicles: return .purple
            case .parts: return .orange
            case .sales: return .green
            case .clients: return .indigo
            }
        }
    }

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                iPadRootView()
            } else {
                mobileBody
            }
        }
    }

    @ViewBuilder
    var mobileBody: some View {
        let shouldGatePermissions: Bool = {
            if case .signedIn = sessionStore.status {
                return true
            }
            return false
        }()
        let isGuestPreview = appSessionState.isGuestMode && !shouldGatePermissions
        let overlayBottomPadding = max(tabBarHeight, 60)

        ZStack {
            TabView(selection: $selectedTab) {
                // 1. Dashboard
                Group {
                    if isGuestPreview {
                        GuestFeaturePreviewView(
                            feature: .dashboard,
                            bottomPadding: overlayBottomPadding + 24,
                            onRequireAccount: requestGuestAccount
                        )
                    } else {
                        DashboardView()
                    }
                }
                    .tag(Tab.dashboard)
                   // .toolbar(.hidden, for: .tabBar) // iOS 16+, falling back to onAppear for broader support if needed

                // 2. Expenses
                Group {
                    if isGuestPreview {
                        GuestFeaturePreviewView(
                            feature: .expenses,
                            bottomPadding: overlayBottomPadding + 24,
                            onRequireAccount: requestGuestAccount
                        )
                    } else if shouldGatePermissions {
                        if permissionService.didLoad {
                            if permissionService.can(.viewExpenses) {
                                DealerExpenseDashboardView()
                            } else {
                                RestrictedAccessView(title: "expenses".localizedString)
                            }
                        } else {
                            PermissionLoadingView(title: "expenses".localizedString)
                        }
                    } else {
                        DealerExpenseDashboardView()
                    }
                }
                .tag(Tab.expenses)

                // 3. Vehicles
                Group {
                    if isGuestPreview {
                        GuestFeaturePreviewView(
                            feature: .vehicles,
                            bottomPadding: overlayBottomPadding + 24,
                            onRequireAccount: requestGuestAccount
                        )
                    } else if shouldGatePermissions {
                        if permissionService.didLoad {
                            if permissionService.can(.viewInventory) {
                                VehicleListView()
                            } else {
                                RestrictedAccessView(title: "vehicles".localizedString)
                            }
                        } else {
                            PermissionLoadingView(title: "vehicles".localizedString)
                        }
                    } else {
                        VehicleListView()
                    }
                }
                .tag(Tab.vehicles)

                // 4. Parts
                if regionSettings.isPartsEnabled {
                    Group {
                        if isGuestPreview {
                            GuestFeaturePreviewView(
                                feature: .parts,
                                bottomPadding: overlayBottomPadding + 24,
                                onRequireAccount: requestGuestAccount
                            )
                        } else if shouldGatePermissions {
                            if permissionService.didLoad {
                                if permissionService.can(.viewPartsInventory) {
                                    PartsDashboardView()
                                } else {
                                    RestrictedAccessView(title: "parts_tab_title".localizedString)
                                }
                            } else {
                                PermissionLoadingView(title: "parts_tab_title".localizedString)
                            }
                        } else {
                            PartsDashboardView()
                        }
                    }
                    .tag(Tab.parts)
                }
                
                // 5. Sales
                Group {
                    if isGuestPreview {
                        GuestFeaturePreviewView(
                            feature: .sales,
                            bottomPadding: overlayBottomPadding + 24,
                            onRequireAccount: requestGuestAccount
                        )
                    } else if shouldGatePermissions {
                        if permissionService.didLoad {
                            if permissionService.can(.createSale) || permissionService.can(.viewFinancials) {
                                SalesListView()
                            } else {
                                RestrictedAccessView(title: "sales".localizedString)
                            }
                        } else {
                            PermissionLoadingView(title: "sales".localizedString)
                        }
                    } else {
                        SalesListView()
                    }
                }
                .tag(Tab.sales)

                // 6. Clients
                Group {
                    if isGuestPreview {
                        GuestFeaturePreviewView(
                            feature: .clients,
                            bottomPadding: overlayBottomPadding + 24,
                            onRequireAccount: requestGuestAccount
                        )
                    } else if shouldGatePermissions {
                        if permissionService.didLoad {
                            if permissionService.can(.viewLeads) {
                                ClientListView()
                            } else {
                                RestrictedAccessView(title: "clients".localizedString)
                            }
                        } else {
                            PermissionLoadingView(title: "clients".localizedString)
                        }
                    } else {
                        ClientListView()
                    }
                }
                .tag(Tab.clients)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CustomTabBar(selectedTab: $selectedTab)
                    .readSize { size in
                        if abs(tabBarHeight - size.height) > 0.5 {
                            tabBarHeight = size.height
                        }
                    }
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .alert("VIN already exists", isPresented: Binding(
                get: { cloudSyncManager.vinConflictVehicleId != nil },
                set: { if !$0 { cloudSyncManager.vinConflictVehicleId = nil } }
            )) {
                Button("Open Vehicles") {
                    selectedTab = .vehicles
                    cloudSyncManager.vinConflictVehicleId = nil
                }
                Button("OK", role: .cancel) {
                    cloudSyncManager.vinConflictVehicleId = nil
                }
            } message: {
                Text("This VIN is already in your inventory.")
            }
            // Hide system tab bar so we can show ours
            .onAppear {
                UITabBar.appearance().isHidden = true
            }

            // Overlays
            SyncHUDOverlay()
                .padding(.bottom, overlayBottomPadding)

            // Error Toast Overlay
            Group {
                if let errorMessage = cloudSyncManager.errorMessage {
                    VStack {
                        Spacer()
                        ToastView(
                            message: errorMessage,
                            isError: true,
                            onDismiss: { cloudSyncManager.errorMessage = nil }
                        )
                        .padding(.bottom, overlayBottomPadding + 24)
                    }
                    .zIndex(100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.28, extraBounce: 0.02), value: cloudSyncManager.errorMessage != nil)

            Group {
                if let inviteMessage = sessionStore.inviteToastMessage {
                    VStack {
                        Spacer()
                        ToastView(
                            message: inviteMessage,
                            isError: sessionStore.inviteToastIsError,
                            onDismiss: { sessionStore.dismissInviteToast() }
                        )
                        .padding(.bottom, overlayBottomPadding + 24)
                    }
                    .zIndex(100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.28, extraBounce: 0.02), value: sessionStore.inviteToastMessage != nil)
        }
        .sheet(isPresented: $showProfileSheet) {
            AccountView()
                .preferredColorScheme(regionSettings.selectedTheme.colorScheme)
        }
        .guestAccountPrompt(isPresented: $showGuestAccountPrompt) {
            appSessionState.exitGuestModeForLogin()
            appSessionState.mode = .signUp
        }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardDidRequestAccount)) { _ in
            showProfileSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardDidRequestExpensesTab)) { _ in
            withAnimation(.snappy(duration: 0.28, extraBounce: 0.04)) {
                selectedTab = .expenses
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .currencySettingsDidComplete)) { _ in
            showProfileSheet = false // Close the Account sheet
            selectedTab = .dashboard // Switch to Dashboard tab
        }
    }

    private func requestGuestAccount() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showGuestAccountPrompt = true
    }
}

struct CustomTabBar: View {
    @Binding var selectedTab: ContentView.Tab
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(ContentView.Tab.allCases.filter { tab in tab != .parts || regionSettings.isPartsEnabled }) { tab in
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(.snappy(duration: 0.28, extraBounce: 0.04)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 4) {
                        // Icon
                        Image(systemName: tab.icon)
                            .font(.system(size: 22))
                            .symbolVariant(selectedTab == tab ? .fill : .none)
                            .scaleEffect(selectedTab == tab ? 1.1 : 1.0)
                            .frame(height: 24)
                        
                        // Label - Always Visible
                        Text(tab.title)
                            .font(.system(size: 9, weight: selectedTab == tab ? .bold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity) // Distribute space evenly (6 items)
                    .padding(.vertical, 12)
                    .foregroundColor(selectedTab == tab ? tab.color : ColorTheme.secondaryText)
                    .contentShape(Rectangle())
                }
            }
        }
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    @Namespace private var namespace
}

enum GuestPreviewFeature {
    case dashboard
    case expenses
    case vehicles
    case parts
    case sales
    case clients

    init(tab: ContentView.Tab) {
        switch tab {
        case .dashboard: self = .dashboard
        case .expenses: self = .expenses
        case .vehicles: self = .vehicles
        case .parts: self = .parts
        case .sales: self = .sales
        case .clients: self = .clients
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "chart.xyaxis.line"
        case .expenses: return "creditcard.fill"
        case .vehicles: return "car.2.fill"
        case .parts: return "shippingbox.fill"
        case .sales: return "banknote.fill"
        case .clients: return "person.2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .dashboard: return ColorTheme.primary
        case .expenses: return ColorTheme.danger
        case .vehicles: return ColorTheme.purple
        case .parts: return ColorTheme.accent
        case .sales: return ColorTheme.success
        case .clients: return .indigo
        }
    }

    @MainActor var title: String {
        switch self {
        case .dashboard: return "guest_preview_dashboard_title".localizedString
        case .expenses: return "guest_preview_expenses_title".localizedString
        case .vehicles: return "guest_preview_vehicles_title".localizedString
        case .parts: return "guest_preview_parts_title".localizedString
        case .sales: return "guest_preview_sales_title".localizedString
        case .clients: return "guest_preview_clients_title".localizedString
        }
    }

    @MainActor var subtitle: String {
        switch self {
        case .dashboard: return "guest_preview_dashboard_subtitle".localizedString
        case .expenses: return "guest_preview_expenses_subtitle".localizedString
        case .vehicles: return "guest_preview_vehicles_subtitle".localizedString
        case .parts: return "guest_preview_parts_subtitle".localizedString
        case .sales: return "guest_preview_sales_subtitle".localizedString
        case .clients: return "guest_preview_clients_subtitle".localizedString
        }
    }

    @MainActor var actionTitle: String {
        switch self {
        case .dashboard: return "guest_preview_create_account".localizedString
        case .expenses: return "add_expense".localizedString
        case .vehicles: return "add_vehicle".localizedString
        case .parts: return "parts_add_part".localizedString
        case .sales: return "guest_preview_action_sale".localizedString
        case .clients: return "guest_preview_action_client".localizedString
        }
    }

    @MainActor func metrics(currencySymbol: String) -> [GuestPreviewMetric] {
        switch self {
        case .dashboard:
            return [
                GuestPreviewMetric(title: "inventory_value".localizedString, value: "\(currencySymbol) 428K", icon: "car.fill", color: ColorTheme.primary),
                GuestPreviewMetric(title: "guest_preview_month_profit".localizedString, value: "\(currencySymbol) 36K", icon: "chart.line.uptrend.xyaxis", color: ColorTheme.success),
                GuestPreviewMetric(title: "expenses".localizedString, value: "\(currencySymbol) 7.4K", icon: "creditcard.fill", color: ColorTheme.danger),
                GuestPreviewMetric(title: "clients".localizedString, value: "18", icon: "person.2.fill", color: .indigo)
            ]
        case .expenses:
            return [
                GuestPreviewMetric(title: "guest_preview_month_spend".localizedString, value: "\(currencySymbol) 7.4K", icon: "calendar", color: ColorTheme.danger),
                GuestPreviewMetric(title: "vehicle".localizedString, value: "\(currencySymbol) 3.1K", icon: "car.fill", color: ColorTheme.primary),
                GuestPreviewMetric(title: "employee".localizedString, value: "\(currencySymbol) 2.2K", icon: "person.fill", color: ColorTheme.purple),
                GuestPreviewMetric(title: "personal".localizedString, value: "\(currencySymbol) 900", icon: "wallet.pass.fill", color: ColorTheme.accent)
            ]
        case .vehicles:
            return [
                GuestPreviewMetric(title: "vehicles".localizedString, value: "12", icon: "car.2.fill", color: ColorTheme.purple),
                GuestPreviewMetric(title: "inventory_value".localizedString, value: "\(currencySymbol) 428K", icon: "chart.pie.fill", color: ColorTheme.primary),
                GuestPreviewMetric(title: "guest_preview_avg_days".localizedString, value: "38", icon: "clock.fill", color: ColorTheme.warning),
                GuestPreviewMetric(title: "sold".localizedString, value: "4", icon: "checkmark.seal.fill", color: ColorTheme.success)
            ]
        case .parts:
            return [
                GuestPreviewMetric(title: "parts_tab_title".localizedString, value: "86", icon: "shippingbox.fill", color: ColorTheme.accent),
                GuestPreviewMetric(title: "inventory_value".localizedString, value: "\(currencySymbol) 18K", icon: "chart.bar.fill", color: ColorTheme.primary),
                GuestPreviewMetric(title: "guest_preview_low_stock".localizedString, value: "7", icon: "exclamationmark.triangle.fill", color: ColorTheme.warning),
                GuestPreviewMetric(title: "sales".localizedString, value: "\(currencySymbol) 4.8K", icon: "banknote.fill", color: ColorTheme.success)
            ]
        case .sales:
            return [
                GuestPreviewMetric(title: "sales".localizedString, value: "9", icon: "checkmark.circle.fill", color: ColorTheme.success),
                GuestPreviewMetric(title: "total_revenue".localizedString, value: "\(currencySymbol) 214K", icon: "banknote.fill", color: ColorTheme.primary),
                GuestPreviewMetric(title: "profit".localizedString, value: "\(currencySymbol) 36K", icon: "chart.line.uptrend.xyaxis", color: ColorTheme.success),
                GuestPreviewMetric(title: "guest_preview_conversion".localizedString, value: "32%", icon: "percent", color: ColorTheme.accent)
            ]
        case .clients:
            return [
                GuestPreviewMetric(title: "clients".localizedString, value: "18", icon: "person.2.fill", color: .indigo),
                GuestPreviewMetric(title: "guest_preview_hot_leads".localizedString, value: "6", icon: "flame.fill", color: ColorTheme.accent),
                GuestPreviewMetric(title: "guest_preview_followups".localizedString, value: "5", icon: "bell.fill", color: ColorTheme.warning),
                GuestPreviewMetric(title: "sales".localizedString, value: "9", icon: "checkmark.seal.fill", color: ColorTheme.success)
            ]
        }
    }

    @MainActor func rows(currencySymbol: String) -> [GuestPreviewRow] {
        switch self {
        case .dashboard:
            return [
                GuestPreviewRow(title: "guest_preview_row_inventory".localizedString, detail: "12 \("vehicles".localizedString.lowercased())", icon: "car.fill"),
                GuestPreviewRow(title: "guest_preview_row_profit".localizedString, detail: "\(currencySymbol) 36K", icon: "chart.line.uptrend.xyaxis"),
                GuestPreviewRow(title: "guest_preview_row_sync".localizedString, detail: "guest_preview_row_sync_detail".localizedString, icon: "icloud.fill")
            ]
        case .expenses:
            return [
                GuestPreviewRow(title: "guest_preview_row_vehicle_prep".localizedString, detail: "\(currencySymbol) 1,250", icon: "wrench.and.screwdriver.fill"),
                GuestPreviewRow(title: "guest_preview_row_transport".localizedString, detail: "\(currencySymbol) 640", icon: "box.truck.fill"),
                GuestPreviewRow(title: "guest_preview_row_salary".localizedString, detail: "\(currencySymbol) 2,200", icon: "person.text.rectangle.fill")
            ]
        case .vehicles:
            return [
                GuestPreviewRow(title: "2021 Toyota Camry", detail: "\(currencySymbol) 82K", icon: "car.fill"),
                GuestPreviewRow(title: "2020 BMW 530i", detail: "\(currencySymbol) 118K", icon: "car.fill"),
                GuestPreviewRow(title: "2019 Mercedes C200", detail: "\(currencySymbol) 96K", icon: "car.fill")
            ]
        case .parts:
            return [
                GuestPreviewRow(title: "guest_preview_row_brake_pads".localizedString, detail: "24 \("guest_preview_units".localizedString)", icon: "circle.fill"),
                GuestPreviewRow(title: "guest_preview_row_oil_filters".localizedString, detail: "40 \("guest_preview_units".localizedString)", icon: "drop.fill"),
                GuestPreviewRow(title: "guest_preview_row_tires".localizedString, detail: "12 \("guest_preview_units".localizedString)", icon: "circle.dotted")
            ]
        case .sales:
            return [
                GuestPreviewRow(title: "guest_preview_row_sale_recorded".localizedString, detail: "\(currencySymbol) 92K", icon: "checkmark.circle.fill"),
                GuestPreviewRow(title: "guest_preview_row_deposit".localizedString, detail: "\(currencySymbol) 5K", icon: "creditcard.fill"),
                GuestPreviewRow(title: "guest_preview_row_profit".localizedString, detail: "\(currencySymbol) 11K", icon: "chart.line.uptrend.xyaxis")
            ]
        case .clients:
            return [
                GuestPreviewRow(title: "guest_preview_row_hot_lead".localizedString, detail: "guest_preview_row_hot_lead_detail".localizedString, icon: "flame.fill"),
                GuestPreviewRow(title: "guest_preview_row_test_drive".localizedString, detail: "guest_preview_row_test_drive_detail".localizedString, icon: "steeringwheel"),
                GuestPreviewRow(title: "guest_preview_row_reminder".localizedString, detail: "guest_preview_row_reminder_detail".localizedString, icon: "bell.fill")
            ]
        }
    }
}

struct GuestPreviewMetric: Identifiable {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var id: String { "\(title)-\(value)" }
}

struct GuestPreviewRow: Identifiable {
    let title: String
    let detail: String
    let icon: String

    var id: String { "\(title)-\(detail)" }
}

struct GuestFeaturePreviewView: View {
    let feature: GuestPreviewFeature
    let bottomPadding: CGFloat
    let onRequireAccount: () -> Void
    @EnvironmentObject private var regionSettings: RegionSettingsManager

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        let metrics = feature.metrics(currencySymbol: regionSettings.selectedRegion.currencySymbol)
        let rows = feature.rows(currencySymbol: regionSettings.selectedRegion.currencySymbol)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(metrics) { metric in
                        GuestMetricCard(metric: metric)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("guest_preview_activity_title".localizedString)
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText)

                    ForEach(rows) { row in
                        GuestActivityRow(row: row, tint: feature.tint)
                    }
                }

                Button(action: onRequireAccount) {
                    Label(feature.actionTitle, systemImage: "lock.open.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(feature.tint)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.hapticScale)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, bottomPadding)
        }
        .background(ColorTheme.background.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: feature.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 54, height: 54)
                    .background(feature.tint)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("guest_preview_badge".localizedString)
                        .font(.caption.weight(.bold))
                        .foregroundColor(feature.tint)
                        .textCase(.uppercase)

                    Text(feature.title)
                        .font(.title3.weight(.bold))
                        .foregroundColor(ColorTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(feature.subtitle)
                .font(.subheadline)
                .foregroundColor(ColorTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(feature.tint.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct GuestMetricCard: View {
    let metric: GuestPreviewMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: metric.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(metric.color)
                .frame(width: 34, height: 34)
                .background(metric.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(metric.value)
                    .font(.headline.weight(.bold))
                    .foregroundColor(ColorTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(metric.title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(ColorTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(14)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct GuestActivityRow: View {
    let row: GuestPreviewRow
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(row.detail)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct GuestAccountPromptModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onSignUp: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("guest_account_required_title".localizedString, isPresented: $isPresented) {
                Button("guest_preview_create_account".localizedString) {
                    onSignUp()
                }
                Button("cancel".localizedString, role: .cancel) {}
            } message: {
                Text("guest_account_required_message".localizedString)
            }
    }
}

extension View {
    func guestAccountPrompt(isPresented: Binding<Bool>, onSignUp: @escaping () -> Void) -> some View {
        modifier(GuestAccountPromptModifier(isPresented: isPresented, onSignUp: onSignUp))
    }
}

struct SyncHUDOverlay: View {
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @State private var isSpinning = false

    var body: some View {
        ZStack {
            if cloudSyncManager.syncHUDState == .some(.syncing) {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            switch cloudSyncManager.syncHUDState {
            case .some(.syncing):
                syncCard(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: ColorTheme.primary,
                    title: "synchronizing".localizedString,
                    subtitle: "please_wait".localizedString,
                    compact: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { isSpinning = true }
                .onDisappear { isSpinning = false }

            case .some(.success):
                syncCard(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    title: "synced".localizedString,
                    subtitle: "all_data_up_to_date".localizedString,
                    compact: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .onAppear { isSpinning = false }

            case .some(.failure):
                syncCard(
                    icon: "xmark.octagon.fill",
                    iconColor: .red,
                    title: "sync_failed".localizedString,
                    subtitle: "please_try_again".localizedString,
                    compact: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .onAppear { isSpinning = false }

            case .none:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(cloudSyncManager.syncHUDState == .some(.syncing))
        .animation(.snappy(duration: 0.3, extraBounce: 0.03), value: cloudSyncManager.syncHUDState)
    }

    @ViewBuilder
    private func syncCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String?,
        compact: Bool
    ) -> some View {
        Group {
            if compact {
                HStack(spacing: 12) {
                    syncIcon(icon: icon, iconColor: iconColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ColorTheme.primaryText)

                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(ColorTheme.secondaryText)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .frame(maxWidth: 340)
            } else {
                VStack(spacing: 12) {
                    syncIcon(icon: icon, iconColor: iconColor)

                    Text(title)
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText)

                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                }
                .padding(20)
                .frame(maxWidth: 260)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: compact ? 10 : 14, x: 0, y: compact ? 4 : 8)
        .transition(
            compact
            ? .move(edge: .bottom).combined(with: .opacity)
            : .opacity.combined(with: .scale(scale: 0.96))
        )
    }

    private func syncIcon(icon: String, iconColor: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 24, weight: .semibold))
            .foregroundColor(iconColor)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(
                isSpinning
                ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                : .default,
                value: isSpinning
            )
    }
}

struct ToastView: View {
    let message: String
    let isError: Bool
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .white : .white)
                .font(.system(size: 20))
            
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.system(size: 14, weight: .bold))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isError ? Color.red.opacity(0.95) : Color.green.opacity(0.95))
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct RestrictedAccessView: View {
    let title: String
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        let message = String(
            format: "permission_access_restricted_message".localizedString,
            locale: Locale.current,
            title
        )

        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundColor(ColorTheme.secondaryText)
                Text(title)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Text("permission_access_pull_to_refresh".localizedString)
                    .font(.caption)
                    .foregroundColor(ColorTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorTheme.background)
        .refreshable {
            await sessionStore.refreshPermissionsIfPossible()
        }
    }
}

struct PermissionLoadingView: View {
    let title: String

    var body: some View {
        let message = String(
            format: "permission_access_loading_message".localizedString,
            locale: Locale.current,
            title
        )

        VStack(spacing: 16) {
            ProgressView()
            Text(message)
                .font(.subheadline)
                .foregroundColor(ColorTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorTheme.background)
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

extension View {
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}
