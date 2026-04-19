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
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @ObservedObject private var permissionService = PermissionService.shared
    @State private var selectedTab: Tab = .dashboard
    @State private var showProfileSheet = false
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
        let overlayBottomPadding = max(tabBarHeight, 60)

        ZStack {
            TabView(selection: $selectedTab) {
                // 1. Dashboard
                DashboardView()
                    .tag(Tab.dashboard)
                   // .toolbar(.hidden, for: .tabBar) // iOS 16+, falling back to onAppear for broader support if needed

                // 2. Expenses
                Group {
                    if shouldGatePermissions {
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
                    if shouldGatePermissions {
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
                        if shouldGatePermissions {
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
                    if shouldGatePermissions {
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
                    if shouldGatePermissions {
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
