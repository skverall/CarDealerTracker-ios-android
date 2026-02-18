//
//  FinancialAccountsView.swift
//  Ezcar24Business
//
//  Created by User on 11/19/25.
//

import SwiftUI

struct FinancialAccountsView: View {
    @StateObject private var viewModel: FinancialAccountsViewModel
    @State private var selectedAccount: FinancialAccount?
    @State private var showAddAccount = false
    
    let filterKind: FinancialAccountKind?
    
    init(filterKind: FinancialAccountKind? = nil) {
        self.filterKind = filterKind
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: FinancialAccountsViewModel(context: context))
    }
    
    private var navigationTitle: String {
        if let kind = filterKind {
            return kind.title
        }
        return "financial_accounts".localizedString
    }
    
    var body: some View {
        List {
            listContent
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddAccount = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(ColorTheme.primary)
                }
            }
        }
        .sheet(item: $selectedAccount) { account in
            EditAccountView(viewModel: viewModel, account: account)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAddAccount) {
            AddFinancialAccountView(viewModel: viewModel, preselectedKind: filterKind)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            viewModel.fetchAccounts()
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if groupedAccounts.isEmpty {
            emptyStateSection
        } else {
            accountsSections
        }
    }

    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: filterKind?.iconName ?? "building.columns.fill")
                    .font(.system(size: 48))
                    .foregroundColor(ColorTheme.secondaryText)

                Text(emptyStateTitle)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)

                Text(emptyStateSubtitle)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.secondaryText)
                    .multilineTextAlignment(.center)

                if filterKind == nil {
                    Button {
                        viewModel.createDefaultAccounts()
                    } label: {
                        Text("Create Cash + Bank")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(ColorTheme.primary)
                            .cornerRadius(12)
                    }
                }

                Button {
                    showAddAccount = true
                } label: {
                    Text(filterKind == nil ? "Add Custom Account" : "Add \(filterKind?.title ?? "Account")")
                        .font(.headline)
                        .foregroundColor(ColorTheme.primary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(ColorTheme.secondaryBackground)
                        .cornerRadius(12)
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 32)
            .listRowBackground(Color.clear)
        }
    }
    
    private var emptyStateTitle: String {
        if let kind = filterKind {
            return "No \(kind.title) Found"
        }
        return "No Accounts Found"
    }
    
    private var emptyStateSubtitle: String {
        if let kind = filterKind {
            return "Tap the + button to add a \(kind.title.lowercased())."
        }
        return "Create accounts to track cash, banks, and cards separately."
    }

    private var accountsSections: some View {
        ForEach(groupedAccounts) { group in
            Section {
                ForEach(group.accounts) { account in
                    accountRow(account)
                }
            } header: {
                Text(group.kind.title)
            } footer: {
                Text("Tap an account to view transactions.")
            }
        }
    }

    private func accountRow(_ account: FinancialAccount) -> some View {
        Button {
            selectedAccount = account
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(account.kind.color.opacity(0.12))
                        .frame(width: 40, height: 40)

                    Image(systemName: account.kind.iconName)
                        .font(.headline)
                        .foregroundColor(account.kind.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(account.shortTitle)
                        .font(.body.weight(.medium))
                        .foregroundColor(ColorTheme.primaryText)

                    if let subtitle = account.subtitleTitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text((account.balance?.decimalValue ?? 0).asCurrency())
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText)

                    Text("Current Balance")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.secondaryText)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(ColorTheme.tertiaryText)
            }
            .padding(.vertical, 8)
        }
    }

    private struct AccountGroup: Identifiable {
        let kind: FinancialAccountKind
        let accounts: [FinancialAccount]

        var id: FinancialAccountKind { kind }
    }

    private var groupedAccounts: [AccountGroup] {
        let grouped = Dictionary(grouping: viewModel.accounts) { $0.kind }
        let kindsToShow: [FinancialAccountKind] = filterKind.map { [$0] } ?? Array(FinancialAccountKind.allCases)
        return kindsToShow.compactMap { kind in
            guard let accounts = grouped[kind], !accounts.isEmpty else { return nil }
            let sortedAccounts = accounts.sorted {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
            return AccountGroup(kind: kind, accounts: sortedAccounts)
        }
    }
}
