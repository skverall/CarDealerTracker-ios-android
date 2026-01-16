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
    @ObservedObject private var permissionService = PermissionService.shared
    @State private var selectedTab: Tab = .dashboard
    @State private var showProfileSheet = false

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

        ZStack(alignment: .bottom) {
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
            // Hide system tab bar so we can show ours
            .onAppear {
                UITabBar.appearance().isHidden = true
            }
            
            // Custom Tab Bar
            CustomTabBar(selectedTab: $selectedTab)
                .padding(.bottom, 0) // Safe area handled inside internal padding usually or implicit
                .ignoresSafeArea(.keyboard, edges: .bottom)

            // Overlays
            SyncHUDOverlay()
                .padding(.bottom, 60) // Lift HUD above tabbar

            // Error Toast Overlay
            if let errorMessage = cloudSyncManager.errorMessage {
                VStack {
                    Spacer()
                    ToastView(
                        message: errorMessage,
                        isError: true,
                        onDismiss: { cloudSyncManager.errorMessage = nil }
                    )
                    .padding(.bottom, 90) // Above tab bar
                }
                .zIndex(100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let inviteMessage = sessionStore.inviteToastMessage {
                VStack {
                    Spacer()
                    ToastView(
                        message: inviteMessage,
                        isError: sessionStore.inviteToastIsError,
                        onDismiss: { sessionStore.dismissInviteToast() }
                    )
                    .padding(.bottom, 90) // Above tab bar
                }
                .zIndex(100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showProfileSheet) {
            AccountView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardDidRequestAccount)) { _ in
            showProfileSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .currencySettingsDidComplete)) { _ in
            showProfileSheet = false // Close the Account sheet
            selectedTab = .dashboard // Switch to Dashboard tab
        }
    }
}

struct CustomTabBar: View {
    @Binding var selectedTab: ContentView.Tab
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(ContentView.Tab.allCases) { tab in
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
        Group {
            switch cloudSyncManager.syncHUDState {
            case .some(.syncing):
                hudView(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: ColorTheme.primary,
                    title: "synchronizing".localizedString,
                    subtitle: "please_wait".localizedString
                )
                .onAppear { isSpinning = true }

            case .some(.success):
                hudView(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    title: "synced".localizedString,
                    subtitle: "all_data_up_to_date".localizedString
                )
                .onAppear { isSpinning = false }

            case .some(.failure):
                hudView(
                    icon: "xmark.octagon.fill",
                    iconColor: .red,
                    title: "sync_failed".localizedString,
                    subtitle: "please_try_again".localizedString
                )
                .onAppear { isSpinning = false }

            case .none:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: cloudSyncManager.syncHUDState)
    }

    @ViewBuilder
    private func hudView(icon: String, iconColor: Color, title: String, subtitle: String?) -> some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: icon)
                // Use .degrees(isSpinning ? 360 : 0) directly if compatible, or handle animation carefully
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(iconColor)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(
                        isSpinning
                        ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                        : .default,
                        value: isSpinning
                    )

                Text(title)
                    .font(.headline)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
            .padding(20)
            .frame(maxWidth: 260)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 8)
        }
        .transition(.opacity.combined(with: .scale))
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
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(), value: message)
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
