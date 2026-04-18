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
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    @ObservedObject private var permissionService = PermissionService.shared
    
    @State private var selectedTab: ContentView.Tab? = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showProfileSheet = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedTab: $selectedTab)
                .navigationTitle("Ezcar24")
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showProfileSheet = true
                        } label: {
                            Label("Account", systemImage: "person.crop.circle")
                        }
                    }
                }
        } detail: {
            // Feature: Background gradient for empty states or transitions
            ZStack {
                ColorTheme.secondaryBackground.ignoresSafeArea()
                
                if let selectedTab {
                    viewForTab(selectedTab)
                } else {
                    ContentUnavailableView("Select a Menu Item", systemImage: "sidebar.left")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .fullScreenCover(isPresented: $showProfileSheet) {
            AccountView()
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

        switch tab {
        case .dashboard:
            DashboardView()
                .id(tab) // Force recreate if needed, though usually not for dashboard
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
                    VehicleListView()
                } else {
                    RestrictedAccessView(title: "vehicles".localizedString)
                }
            } else {
                VehicleListView()
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

struct SidebarView: View {
    @Binding var selectedTab: ContentView.Tab?
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var regionSettings: RegionSettingsManager
    
    var body: some View {
        List(selection: $selectedTab) {
            Section("Menu") {
                ForEach(ContentView.Tab.allCases.filter { tab in tab != .parts || regionSettings.isPartsEnabled }) { tab in
                    NavigationLink(value: tab) {
                        Label {
                            Text(tab.title)
                                .font(.body)
                                .fontWeight(.medium)
                        } icon: {
                            Image(systemName: tab.icon)
                                .foregroundStyle(tab.color)
                        }
                        .padding(.vertical, 4)
                    }
                    // Keyboard Shortcuts: Cmd+1 for first tab, Cmd+2 for second, etc.
                    .keyboardShortcut(KeyEquivalent(Character("\(tab.rawValue + 1)")), modifiers: .command)
                }
            }
            
            Section("Quick Actions") {
                // Add useful shortcuts here if needed, e.g. "New Sale"
                // For now we keep it clean
            }
        }
        .listStyle(.sidebar)
    }
}
