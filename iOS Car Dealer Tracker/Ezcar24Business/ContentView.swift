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
    @State private var selectedTab = 0
    @State private var showProfileSheet = false

    var body: some View {
        let shouldGatePermissions: Bool = {
            if case .signedIn = sessionStore.status {
                return true
            }
            return false
        }()

        ZStack {
            TabView(selection: $selectedTab) {
                DashboardView()
                    .tabItem {
                        Label("dashboard_title".localizedString, systemImage: "house.fill")
                    }
                    .tag(0)

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
                .tabItem {
                    Label("vehicles".localizedString, systemImage: "car.fill")
                }
                .tag(1)

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
                .tabItem {
                    Label("expenses".localizedString, systemImage: "creditcard")
                }
                .tag(2)

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
                .tabItem {
                    Label("sales".localizedString, systemImage: "dollarsign.circle.fill")
                }
                .tag(3)

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
                .tabItem {
                    Label("clients".localizedString, systemImage: "person.2")
                }
                .tag(4)
            }
            .tint(ColorTheme.dealerGreen)

            SyncHUDOverlay()
            
            // Error Toast Overlay
            if let errorMessage = cloudSyncManager.errorMessage {
                VStack {
                    Spacer()
                    ToastView(
                        message: errorMessage,
                        isError: true,
                        onDismiss: { cloudSyncManager.errorMessage = nil }
                    )
                    .padding(.bottom, 60) // Above tab bar
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
                    .padding(.bottom, 60) // Above tab bar
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
            selectedTab = 0 // Switch to Dashboard tab
        }
        .onAppear {
            configureTabBar()
        }
    }
    
    private func configureTabBar() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        
        let scrollingAppearance = UITabBarAppearance()
        scrollingAppearance.configureWithDefaultBackground()
        scrollingAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
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
