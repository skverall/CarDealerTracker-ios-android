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
    
    init() {
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: FinancialAccountsViewModel(context: context))
    }
    
    var body: some View {
        List {
            if viewModel.accounts.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "building.columns")
                            .font(.system(size: 48))
                            .foregroundColor(ColorTheme.secondaryText)
                        
                        Text("No Accounts Found")
                            .font(.headline)
                            .foregroundColor(ColorTheme.primaryText)
                        
                        Text("Initialize your default Cash and Bank accounts to start tracking your finances.")
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.secondaryText)
                            .multilineTextAlignment(.center)
                        
                        Button {
                            viewModel.createDefaultAccounts()
                        } label: {
                            Text("Initialize Default Accounts")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(ColorTheme.primary)
                                .cornerRadius(12)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.vertical, 32)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(viewModel.accounts) { account in
                        Button {
                            selectedAccount = account
                        } label: {
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(iconColor(for: account).opacity(0.1))
                                        .frame(width: 40, height: 40)
                                    
                                    Image(systemName: iconName(for: account))
                                        .font(.headline)
                                        .foregroundColor(iconColor(for: account))
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(account.accountType?.capitalized ?? "Unknown Account")
                                        .font(.body.weight(.medium))
                                        .foregroundColor(ColorTheme.primaryText)
                                    
                                    Text("Current Balance")
                                        .font(.caption)
                                        .foregroundColor(ColorTheme.secondaryText)
                                }
                                
                                Spacer()
                                
                                Text((account.balance?.decimalValue ?? 0).asCurrency())
                                    .font(.headline)
                                    .foregroundColor(ColorTheme.primaryText)
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.tertiaryText)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                } header: {
                    Text("Your Accounts")
                } footer: {
                    Text("Tap an account to view transactions.")
                }
            }
        }
        .navigationTitle("financial_accounts".localizedString)
        .sheet(item: $selectedAccount) { account in
            EditAccountView(viewModel: viewModel, account: account)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            viewModel.fetchAccounts()
        }
    }
    
    private func iconName(for account: FinancialAccount) -> String {
        switch account.accountType?.lowercased() {
        case "cash": return "banknote.fill"
        case "bank": return "building.columns.fill"
        default: return "creditcard.fill"
        }
    }
    
    private func iconColor(for account: FinancialAccount) -> Color {
        switch account.accountType?.lowercased() {
        case "cash": return .green
        case "bank": return .blue
        default: return .purple
        }
    }
}
