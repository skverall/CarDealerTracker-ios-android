//
//  iPadRootView.swift
//  Ezcar24Business
//
//  Created for iPad 10x Experience
//

import SwiftUI
import CoreData

struct iPadRootView: View {
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appSessionState: AppSessionState
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @ObservedObject private var permissionService = PermissionService.shared
    
    @State private var selectedTab: ContentView.Tab? = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showProfileSheet = false
    @State private var showGuestAccountPrompt = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedTab: $selectedTab) {
                showProfileSheet = true
            }
            .navigationSplitViewColumnWidth(min: 270, ideal: 310)
            .toolbar(.hidden, for: .navigationBar)
        } detail: {
            ZStack {
                iPadDetailCanvas()
                    .ignoresSafeArea()
                
                if let selectedTab {
                    viewForTab(selectedTab)
                } else {
                    ContentUnavailableView {
                        Label("Select a Menu Item".localizedString, systemImage: "sidebar.left")
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .fullScreenCover(isPresented: $showProfileSheet) {
            AccountView()
        }
        .guestAccountPrompt(isPresented: $showGuestAccountPrompt) {
            appSessionState.exitGuestModeForLogin()
            appSessionState.mode = .signUp
        }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardDidRequestAccount)) { _ in
            showProfileSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardDidRequestExpensesTab)) { _ in
            selectedTab = .expenses
        }
        .onReceive(NotificationCenter.default.publisher(for: .currencySettingsDidComplete)) { _ in
            showProfileSheet = false
            selectedTab = .dashboard
        }
    }
    
    @ViewBuilder
    private func viewForTab(_ tab: ContentView.Tab) -> some View {
        let shouldGatePermissions: Bool = {
            if case .signedIn = sessionStore.status {
                return true
            }
            return false
        }()
        let isGuestPreview = appSessionState.isGuestMode && !shouldGatePermissions

        if isGuestPreview {
            GuestFeaturePreviewView(
                feature: GuestPreviewFeature(tab: tab),
                bottomPadding: 32,
                onRequireAccount: requestGuestAccount
            )
        } else {
            switch tab {
            case .dashboard:
                DashboardView()
                    .id(tab)
            case .expenses:
                if shouldGatePermissions {
                    if permissionService.can(.viewExpenses) {
                        DealerExpenseDashboardView(showNavigation: false)
                    } else {
                        RestrictedAccessView(title: "expenses".localizedString)
                    }
                } else {
                    DealerExpenseDashboardView(showNavigation: false)
                }
            case .vehicles:
                if shouldGatePermissions {
                    if permissionService.can(.viewInventory) {
                        VehicleListView(showNavigation: false)
                    } else {
                        RestrictedAccessView(title: "vehicles".localizedString)
                    }
                } else {
                    VehicleListView(showNavigation: false)
                }
            case .parts:
                if regionSettings.isPartsEnabled {
                    if shouldGatePermissions {
                        if permissionService.can(.viewPartsInventory) {
                            PartsDashboardView()
                        } else {
                            RestrictedAccessView(title: "parts_tab_title".localizedString)
                        }
                    } else {
                        PartsDashboardView()
                    }
                } else {
                    EmptyView()
                }
            case .sales:
                if shouldGatePermissions {
                    if permissionService.can(.createSale) || permissionService.can(.viewFinancials) {
                        SalesListView()
                    } else {
                        RestrictedAccessView(title: "sales".localizedString)
                    }
                } else {
                    SalesListView()
                }
            case .clients:
                if shouldGatePermissions {
                    if permissionService.can(.viewLeads) {
                        ClientListView(showNavigation: false)
                    } else {
                        RestrictedAccessView(title: "clients".localizedString)
                    }
                } else {
                    ClientListView(showNavigation: false)
                }
            }
        }
    }

    private func requestGuestAccount() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showGuestAccountPrompt = true
    }
}

private struct iPadDetailCanvas: View {
    var body: some View {
        ZStack {
            ColorTheme.background
            LinearGradient(
                colors: [
                    ColorTheme.primary.opacity(0.12),
                    ColorTheme.secondary.opacity(0.06),
                    ColorTheme.background.opacity(0.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [
                    ColorTheme.accent.opacity(0.08),
                    Color.clear
                ],
                startPoint: .bottomTrailing,
                endPoint: .center
            )
        }
    }
}

struct SidebarView: View {
    @Binding var selectedTab: ContentView.Tab?
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    let onAccountTap: () -> Void

    private var visibleTabs: [ContentView.Tab] {
        ContentView.Tab.allCases.filter { tab in
            tab != .parts || regionSettings.isPartsEnabled
        }
    }
    
    var body: some View {
        ZStack {
            sidebarCanvas

            VStack(alignment: .leading, spacing: 18) {
                sidebarHeader

                VStack(alignment: .leading, spacing: 9) {
                    Text("Menu")
                        .font(.footnote.weight(.bold))
                        .foregroundColor(ColorTheme.secondaryText)
                        .textCase(.uppercase)
                        .tracking(1)
                        .padding(.horizontal, 10)

                    ForEach(visibleTabs) { tab in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedTab = tab
                        } label: {
                            SidebarNavigationRow(tab: tab, isSelected: selectedTab == tab)
                        }
                        .buttonStyle(.hapticScale)
                        .keyboardShortcut(KeyEquivalent(Character("\(tab.rawValue + 1)")), modifiers: .command)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 9) {
                    Text("Quick Actions")
                        .font(.footnote.weight(.bold))
                        .foregroundColor(ColorTheme.secondaryText)
                        .textCase(.uppercase)
                        .tracking(1)
                        .padding(.horizontal, 10)

                    SidebarQuickAction(
                        title: "inventory".localizedString,
                        subtitle: "vehicles".localizedString,
                        icon: "car.2.fill",
                        color: .purple
                    ) {
                        selectedTab = .vehicles
                    }

                    SidebarQuickAction(
                        title: "expenses".localizedString,
                        subtitle: "this_week".localizedString,
                        icon: "creditcard.fill",
                        color: .red
                    ) {
                        selectedTab = .expenses
                    }
                }
            }
            .padding(18)
        }
    }

    private var sidebarCanvas: some View {
        ZStack {
            ColorTheme.background
            LinearGradient(
                colors: [
                    ColorTheme.primary.opacity(0.16),
                    ColorTheme.purple.opacity(0.08),
                    ColorTheme.background.opacity(0.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var sidebarHeader: some View {
        Button(action: onAccountTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [ColorTheme.primary, ColorTheme.secondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "car.2.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 52, height: 52)
                .shadow(color: ColorTheme.primary.opacity(0.28), radius: 12, y: 6)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Car Dealer Tracker")
                        .font(.headline.weight(.heavy))
                        .foregroundColor(ColorTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .layoutPriority(1)

                    Text(accountSubtitle)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)

                Image(systemName: "person.crop.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(ColorTheme.primary)
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 16, y: 8)
        }
        .buttonStyle(.hapticScale)
    }

    private var accountSubtitle: String {
        if case .signedIn(let user) = sessionStore.status {
            return user.email ?? "account".localizedString
        }
        return "account".localizedString
    }
}

private struct SidebarNavigationRow: View {
    let tab: ContentView.Tab
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? .white.opacity(0.2) : tab.color.opacity(0.12))

                Image(systemName: tab.icon)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(isSelected ? .white : tab.color)
            }
            .frame(width: 40, height: 40)

            Text(tab.title)
                .font(.body.weight(isSelected ? .bold : .semibold))
                .foregroundColor(isSelected ? .white : ColorTheme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.heavy))
                    .foregroundColor(.white.opacity(0.82))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tab.color, ColorTheme.primary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: tab.color.opacity(0.28), radius: 14, y: 8)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white.opacity(0.42))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.6), lineWidth: 1)
                    )
            }
        }
    }
}

private struct SidebarQuickAction: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(ColorTheme.primaryText)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.hapticScale)
    }
}
