//
//  UserManagementView.swift
//  Ezcar24Business
//
//  User management interface
//

import SwiftUI

struct UserManagementView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel: UserViewModel
    @State private var showingAddUser = false
    @State private var newUserName = ""
    
    init() {
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: UserViewModel(context: context))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.users.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 60))
                            .foregroundColor(ColorTheme.secondaryText)
                        
                        Text("No users found")
                            .font(.headline)
                            .foregroundColor(ColorTheme.secondaryText)
                        
                        Text("Add users to track who made each expense")
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.tertiaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.users, id: \.id) { user in
                            UserRow(user: user, viewModel: viewModel)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                        }
                        .onDelete(perform: deleteUsers)
                    }
                    .listStyle(.plain)
                    .background(ColorTheme.secondaryBackground)
                }
            }
            .background(ColorTheme.secondaryBackground)
            .navigationTitle("Users")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddUser = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Add User", isPresented: $showingAddUser) {
                TextField("Name", text: $newUserName)
                    .textInputAutocapitalization(.words)

                Button("cancel".localizedString, role: .cancel) {
                    newUserName = ""
                }

                Button("Add") {
                    if !newUserName.isEmpty {
                        let user = viewModel.addUser(name: newUserName)
                        if let dealerId = CloudSyncEnvironment.currentDealerId {
                            Task {
                                await CloudSyncManager.shared?.upsertUser(user, dealerId: dealerId)
                            }
                        }
                        newUserName = ""
                    }
                }
            } message: {
                Text("Enter the user's name")
            }
        }
    }
    
    private func deleteUsers(at offsets: IndexSet) {
        let usersToDelete = offsets.map { viewModel.users[$0] }
        for user in usersToDelete {
            let deletedId = viewModel.deleteUser(user)
            if let dealerId = CloudSyncEnvironment.currentDealerId, let id = deletedId {
                Task {
                    await CloudSyncManager.shared?.deleteUser(id: id, dealerId: dealerId)
                }
            }
        }
    }
}

struct UserRow: View {
    let user: User
    let viewModel: UserViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(ColorTheme.primary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name ?? "Unknown")
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText)
                    
                    Text("Member since \(user.createdAt ?? Date(), style: .date)")
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                }
                
                Spacer()
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Expenses")
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                    
                    Text(viewModel.totalExpenses(for: user).asCurrency())
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(ColorTheme.primary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Expense Count")
                        .font(.caption)
                        .foregroundColor(ColorTheme.secondaryText)
                    
                    Text("\(viewModel.expenseCount(for: user))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .cardStyle()
    }
}

#Preview {
    UserManagementView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
