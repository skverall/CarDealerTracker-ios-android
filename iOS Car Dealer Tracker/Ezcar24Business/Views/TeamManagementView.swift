//
//  TeamManagementView.swift
//  Ezcar24Business
//
//  Created for RBAC Team Management
//

import SwiftUI
import Supabase
import Combine

// MARK: - Models

struct TeamMember: Identifiable, Codable {
    let id: UUID // user_id
    let role: String
    let status: String
    let email: String?
    
    var displayName: String {
        return email ?? "User"
    }
}

struct TeamMemberResponse: Codable {
    let user_id: UUID
    let role: String
    let status: String
    let member_email: String?
}

// MARK: - ViewModel

@MainActor
class TeamViewModel: ObservableObject {
    @Published var members: [TeamMemberResponse] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let client = SupabaseClientProvider().client
    
    func fetchTeam() async {
        isLoading = true
        errorMessage = nil
        do {
            let response: [TeamMemberResponse] = try await client
                .rpc("get_team_members_secure")
                .execute()
                .value
            
            self.members = response
            
        } catch {
            print("Error fetching team: \(error)")
        }
        isLoading = false
    }
    
    func inviteMember(email: String, role: String, language: String = "en") async -> Bool {
        isLoading = true
        errorMessage = nil
        do {
            let params: [String: String] = [
                "email": email, 
                "role": role,
                "language": language
            ]
            let _ = try await client.functions.invoke("invite_member", options: FunctionInvokeOptions(body: params))
            
            await fetchTeam()
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
    
    func removeMember(userId: UUID) async {
        do {
             try await client.from("dealer_team_members")
                .delete()
                .eq("user_id", value: userId)
                .execute()
            
            await fetchTeam()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Views

struct TeamManagementView: View {
    @StateObject private var viewModel = TeamViewModel()
    @State private var showingInviteSheet = false
    
    var body: some View {
        StackCompat {
            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.members.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.members.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 50))
                            .foregroundColor(ColorTheme.secondaryText)
                        Text("No team members found")
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.members, id: \.user_id) { member in
                            TeamMemberRow(member: member)
                        }
                        .onDelete(perform: deleteMember)
                    }
                    .listStyle(.plain)
                }
            }
            .background(ColorTheme.background)
            .navigationTitle("Team Management")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingInviteSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingInviteSheet) {
                InviteMemberSheet(viewModel: viewModel)
                    .presentationDetents([PresentationDetent.medium])
            }
            .task {
                await viewModel.fetchTeam()
            }
        }
    }
    
    private func deleteMember(at offsets: IndexSet) {
        for index in offsets {
            let member = viewModel.members[index]
            Task {
                await viewModel.removeMember(userId: member.user_id)
            }
        }
    }
}

// Helper wrapper for NavigationStack/AnyView
struct StackCompat<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }
        }
    }
}

struct TeamMemberRow: View {
    let member: TeamMemberResponse
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(member.member_email ?? "User")
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText)
                Text(member.role.capitalized)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(roleColor.opacity(0.1))
                    .cornerRadius(4)
            }
            Spacer()
            if member.status == "invited" {
                 Text("Pending")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
    }
    
    var roleColor: Color {
        switch member.role {
        case "owner": return .purple
        case "admin": return .blue
        case "sales": return .green
        case "viewer": return .gray
        default: return .primary
        }
    }
}

struct InviteMemberSheet: View {
    @ObservedObject var viewModel: TeamViewModel
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var selectedRole = "sales"
    
    let roles = ["admin", "sales", "viewer"]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Details")) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    
                    Picker("Role", selection: $selectedRole) {
                        ForEach(roles, id: \.self) { role in
                            Text(role.capitalized).tag(role)
                        }
                    }
                }
                
                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundColor(.red)
                    }
                }
                
                Button("Send Invite") {
                    Task {
                        // Detect current language
                        let currentLanguage = Locale.current.language.languageCode?.identifier ?? "en"
                        let lang = currentLanguage == "ru" ? "ru" : "en"
                        
                        let success = await viewModel.inviteMember(email: email, role: selectedRole, language: lang)
                        if success {
                            dismiss()
                        }
                    }
                }
                .disabled(email.isEmpty || viewModel.isLoading)
            }
            .navigationTitle("Invite Member")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
