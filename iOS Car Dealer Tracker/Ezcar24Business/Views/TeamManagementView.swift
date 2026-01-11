//
//  TeamManagementView.swift
//  Ezcar24Business
//
//  Created for RBAC Team Management
//

import SwiftUI
import Supabase
import Combine
import UIKit

// MARK: - Models

struct TeamMember: Identifiable, Codable {
    let id: UUID // user_id
    let role: String
    let status: String
    let email: String?
    let inviteToken: String?
    
    var displayName: String {
        return email ?? "User"
    }
}

struct TeamMemberResponse: Codable, Identifiable {
    let user_id: UUID
    let role: String
    let status: String
    let member_email: String?
    let invite_token: String?
    let permissions: [String: Bool]?

    var id: UUID { user_id }
}

struct InviteMemberResult: Decodable {
    let success: Bool
    let generatedPassword: String?
    let existingUser: Bool?
    let message: String?
    
    private enum CodingKeys: String, CodingKey {
        case success
        case generatedPassword = "generated_password"
        case existingUser = "existing_user"
        case message
    }
}

struct GeneratedCredentials: Identifiable, Equatable {
    let id = UUID()
    let email: String
    let password: String
}

// MARK: - ViewModel

@MainActor
class TeamViewModel: ObservableObject {
    @Published var members: [TeamMemberResponse] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var listErrorMessage: String?
    
    private let client = SupabaseClientProvider().client

    private struct FunctionErrorPayload: Decodable {
        let error: String
    }
    
    func inviteMember(
        email: String,
        role: String,
        permissions: [String: Bool],
        organizationId: UUID? = nil,
        createAccount: Bool = true,
        language: String = "en"
    ) async -> InviteMemberResult? {
        isLoading = true
        errorMessage = nil
        do {
            struct InviteMemberPayload: Encodable {
                let email: String
                let role: String
                let language: String
                let permissions: [String: Bool]
                let create_account: Bool
                let organization_id: String?
            }
            let payload = InviteMemberPayload(
                email: email,
                role: role,
                language: language,
                permissions: permissions,
                create_account: createAccount,
                organization_id: organizationId?.uuidString
            )
            let result: InviteMemberResult = try await client.functions.invoke(
                "invite_member",
                options: FunctionInvokeOptions(body: payload)
            )
            
            await fetchTeam(organizationId: organizationId)
            isLoading = false
            return result
        } catch {
            errorMessage = functionErrorMessage(from: error)
            isLoading = false
            return nil
        }
    }

    func updateMemberAccess(
        memberId: UUID,
        role: String,
        permissions: [String: Bool],
        organizationId: UUID
    ) async -> Bool {
        isLoading = true
        errorMessage = nil
        do {
            struct UpdateMemberPayload: Encodable {
                let _org_id: String
                let _member_id: String
                let _role: String
                let _permissions: [String: Bool]
            }
            let payload = UpdateMemberPayload(
                _org_id: organizationId.uuidString,
                _member_id: memberId.uuidString,
                _role: role,
                _permissions: permissions
            )

            try await client
                .rpc("update_team_member_access", params: payload)
                .execute()
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }

    func updateInviteAccess(
        inviteId: UUID,
        role: String,
        permissions: [String: Bool],
        organizationId: UUID
    ) async -> Bool {
        isLoading = true
        errorMessage = nil
        do {
            struct UpdateInvitePayload: Encodable {
                let _org_id: String
                let _invite_id: String
                let _role: String
                let _permissions: [String: Bool]
            }
            let payload = UpdateInvitePayload(
                _org_id: organizationId.uuidString,
                _invite_id: inviteId.uuidString,
                _role: role,
                _permissions: permissions
            )

            try await client
                .rpc("update_team_invite_access", params: payload)
                .execute()
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
    
    func removeMember(userId: UUID, organizationId: UUID?) async -> Bool {
        do {
            var query = client.from("dealer_team_members")
                .delete()
                .eq("user_id", value: userId)

            if let organizationId {
                query = query.eq("organization_id", value: organizationId)
            }

            try await query.execute()
            return true
        } catch {
            listErrorMessage = error.localizedDescription
            return false
        }
    }
    
    func cancelInvite(inviteId: UUID, organizationId: UUID?) async -> Bool {
        do {
            var query = client.from("team_invitations")
                .delete()
                .eq("id", value: inviteId)

            if let organizationId {
                query = query.eq("organization_id", value: organizationId)
            }

            try await query.execute()
            return true
        } catch {
            listErrorMessage = error.localizedDescription
            return false
        }
    }

    func fetchTeam(organizationId: UUID?) async {
        isLoading = true
        do {
            let response: [TeamMemberResponse]
            if let organizationId {
                response = try await client
                    .rpc("get_team_members_secure", params: ["_org_id": organizationId.uuidString])
                    .execute()
                    .value
            } else {
                response = try await client
                    .rpc("get_team_members_secure")
                    .execute()
                    .value
            }

            self.members = response
        } catch {
            listErrorMessage = error.localizedDescription
            print("Error fetching team: \(error)")
        }
        isLoading = false
    }

    private func functionErrorMessage(from error: Error) -> String {
        if let functionsError = error as? FunctionsError {
            switch functionsError {
            case let .httpError(_, data):
                if let payload = try? JSONDecoder().decode(FunctionErrorPayload.self, from: data) {
                    let trimmed = payload.error.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
                return error.localizedDescription
            case .relayError:
                return error.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

// MARK: - Views

struct TeamManagementView: View {
    @StateObject private var viewModel = TeamViewModel()
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject private var permissionService = PermissionService.shared
    @State private var showingInviteSheet = false
    @State private var generatedCredentials: GeneratedCredentials?
    @State private var inviteInfoMessage: String?
    @State private var editingMember: TeamMemberResponse?
    
    private var canManageTeam: Bool {
        permissionService.can(.manageTeam)
    }

    private var listErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.listErrorMessage != nil },
            set: { if !$0 { viewModel.listErrorMessage = nil } }
        )
    }

    private var inviteInfoBinding: Binding<Bool> {
        Binding(
            get: { inviteInfoMessage != nil },
            set: { if !$0 { inviteInfoMessage = nil } }
        )
    }

    var body: some View {
        StackCompat {
            contentBody
                .background(ColorTheme.background)
                .navigationTitle("Team Management")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingInviteSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(!canManageTeam)
                    }
                }
                .sheet(isPresented: $showingInviteSheet) {
                    inviteSheet
                }
                .sheet(item: $editingMember) { member in
                    memberAccessSheet(for: member)
                }
                .sheet(item: $generatedCredentials) { credentials in
                    CredentialsSheet(credentials: credentials)
                }
                .task {
                    await viewModel.fetchTeam(organizationId: sessionStore.activeOrganizationId)
                }
                .onChange(of: sessionStore.activeOrganizationId) { _, newOrgId in
                    Task {
                        await viewModel.fetchTeam(organizationId: newOrgId)
                    }
                }
                .alert("Error", isPresented: listErrorBinding) {
                    Button("OK", role: .cancel) {
                        viewModel.listErrorMessage = nil
                    }
                } message: {
                    Text(viewModel.listErrorMessage ?? "Something went wrong.")
                }
                .alert("Notice", isPresented: inviteInfoBinding) {
                    Button("OK", role: .cancel) {
                        inviteInfoMessage = nil
                    }
                } message: {
                    Text(inviteInfoMessage ?? "")
                }
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.members.isEmpty {
                loadingView
            } else if viewModel.members.isEmpty {
                emptyStateView
            } else {
                membersListView
            }
        }
    }

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 50))
                .foregroundColor(ColorTheme.secondaryText)
            Text("No team members found")
                .foregroundColor(ColorTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var membersListView: some View {
        List {
            ForEach(viewModel.members, id: \.user_id) { member in
                TeamMemberRow(
                    member: member,
                    canManageTeam: canManageTeam,
                    onEdit: { editingMember = member }
                )
                    // Disable delete swipe action for the owner
                    .deleteDisabled(member.role == "owner" || !canManageTeam)
            }
            .onDelete(perform: deleteMember)
        }
        .listStyle(.plain)
    }

    private var inviteSheet: some View {
        InviteMemberSheet(
            viewModel: viewModel,
            organizationId: sessionStore.activeOrganizationId,
            onCredentialsGenerated: { generatedCredentials = $0 },
            onInfoMessage: { inviteInfoMessage = $0 }
        )
        .presentationDetents([PresentationDetent.medium])
    }

    private func memberAccessSheet(for member: TeamMemberResponse) -> some View {
        MemberAccessSheet(
            viewModel: viewModel,
            member: member,
            organizationId: sessionStore.activeOrganizationId
        )
        .presentationDetents([.medium, .large])
    }
    
    private func deleteMember(at offsets: IndexSet) {
        guard permissionService.can(.manageTeam) else {
            viewModel.listErrorMessage = "team_manage_permission_denied".localizedString
            return
        }
        let membersToDelete = offsets.map { viewModel.members[$0] }
        let orgId = sessionStore.activeOrganizationId
        withAnimation {
            viewModel.members.remove(atOffsets: offsets)
        }
        Task {
            for member in membersToDelete {
                if member.status == "invited" {
                    _ = await viewModel.cancelInvite(inviteId: member.user_id, organizationId: orgId)
                } else {
                    _ = await viewModel.removeMember(userId: member.user_id, organizationId: orgId)
                }
            }
            await viewModel.fetchTeam(organizationId: orgId)
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
    let canManageTeam: Bool
    let onEdit: () -> Void
    @State private var copied = false
    
    var body: some View {
        let isCustom = PermissionCatalog.isCustomPermissions(member.permissions, role: member.role)
        let badgeText = isCustom
            ? "permission_badge_custom".localizedString
            : "permission_badge_preset".localizedString

        VStack(alignment: .leading, spacing: 8) {
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
                     Text("team_member_pending".localizedString)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Text(PermissionCatalog.permissionSummary(for: member.permissions, role: member.role))
                .font(.caption2)
                .foregroundColor(ColorTheme.secondaryText)

            Text(badgeText)
                .font(.caption2)
                .foregroundColor(isCustom ? ColorTheme.primary : ColorTheme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((isCustom ? ColorTheme.primary.opacity(0.12) : ColorTheme.secondaryText.opacity(0.12)))
                .clipShape(Capsule())
            
            // Copy Link Button for Invited Users
            if member.status == "invited", let token = member.invite_token {
                Button {
                    let link = "https://ezcar24.com/accept-invite?token=\(token)"
                    UIPasteboard.general.string = link
                    withAnimation {
                        copied = true
                    }
                    
                    // Reset copied state after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            copied = false
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy Invite Link")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }

            if canManageTeam && member.role != "owner" {
                Button {
                    onEdit()
                } label: {
                    Label("team_manage_access".localizedString, systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundColor(ColorTheme.primary)
                }
                .buttonStyle(.plain)
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
    let organizationId: UUID?
    let onCredentialsGenerated: (GeneratedCredentials) -> Void
    let onInfoMessage: (String) -> Void
    @State private var email = ""
    @State private var selectedRole = "sales"
    @State private var permissions: [String: Bool] = [:]

    private var existingAccountNotice: String {
        "invite_existing_account_notice".localizedString
    }
    
    private func applyRoleDefaults() {
        PermissionCatalog.applyDefaults(to: &permissions, role: selectedRole)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("team_details_section_title".localizedString)) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    
                    Picker("team_role_section_title".localizedString, selection: $selectedRole) {
                        ForEach(PermissionCatalog.roles, id: \.self) { role in
                            Text(role.capitalized).tag(role)
                        }
                    }

                    Text(PermissionCatalog.roleSummary(for: selectedRole))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("team_access_section_title".localizedString)) {
                    Text("team_access_customize_hint".localizedString)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    ForEach(PermissionCatalog.groups) { group in
                        PermissionToggleRow(
                            title: group.primary.titleKey.localizedString,
                            detail: group.primary.detailKey.localizedString,
                            systemImage: group.primary.systemImage,
                            isOn: Binding(
                                get: { permissions[group.primary.key.rawValue] ?? false },
                                set: { permissions[group.primary.key.rawValue] = $0 }
                            )
                        )

                        if let detailTitleKey = group.detailTitleKey, !group.detailItems.isEmpty {
                            DisclosureGroup(detailTitleKey.localizedString) {
                                ForEach(group.detailItems) { item in
                                    PermissionToggleRow(
                                        title: item.titleKey.localizedString,
                                        detail: item.detailKey.localizedString,
                                        systemImage: item.systemImage,
                                        isOn: Binding(
                                            get: { permissions[item.key.rawValue] ?? false },
                                            set: { permissions[item.key.rawValue] = $0 }
                                        )
                                    )
                                    .padding(.leading, 8)
                                }
                            }
                        }
                    }
                    
                    Button("team_access_reset_role_defaults".localizedString) {
                        applyRoleDefaults()
                    }
                }
                
                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundColor(.red)
                    }
                }
                
                Button("team_generate_access_button".localizedString) {
                    Task {
                        // Detect current language
                        let currentLanguage = Locale.current.language.languageCode?.identifier ?? "en"
                        let lang = currentLanguage == "ru" ? "ru" : "en"
                        
                        let result = await viewModel.inviteMember(
                            email: email,
                            role: selectedRole,
                            permissions: permissions,
                            organizationId: organizationId,
                            createAccount: true,
                            language: lang
                        )
                        if let result {
                            if let password = result.generatedPassword {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    onCredentialsGenerated(.init(email: email, password: password))
                                }
                                return
                            }
                            
                            if let message = result.message {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    onInfoMessage(message)
                                }
                                return
                            }
                            
                            if result.existingUser == true {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    onInfoMessage(existingAccountNotice)
                                }
                                return
                            }
                            
                            dismiss()
                        }
                    }
                }
                .disabled(email.isEmpty || viewModel.isLoading || organizationId == nil)
            }
            .navigationTitle("team_add_member_title".localizedString)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localizedString) { dismiss() }
                }
            }
            .onAppear {
                if permissions.isEmpty {
                    applyRoleDefaults()
                }
            }
            .onChange(of: selectedRole) { _, _ in
                applyRoleDefaults()
            }
        }
    }
}

struct MemberAccessSheet: View {
    @ObservedObject var viewModel: TeamViewModel
    @Environment(\.dismiss) var dismiss
    let member: TeamMemberResponse
    let organizationId: UUID?
    @State private var selectedRole: String
    @State private var permissions: [String: Bool] = [:]

    init(viewModel: TeamViewModel, member: TeamMemberResponse, organizationId: UUID?) {
        self.viewModel = viewModel
        self.member = member
        self.organizationId = organizationId
        _selectedRole = State(initialValue: member.role)
    }

    private var isInvite: Bool {
        member.status == "invited"
    }

    private func applyRoleDefaults() {
        PermissionCatalog.applyDefaults(to: &permissions, role: selectedRole)
    }

    private func saveChanges() {
        Task {
            guard let organizationId else { return }
            let updated = permissions
            let success: Bool
            if isInvite {
                success = await viewModel.updateInviteAccess(
                    inviteId: member.user_id,
                    role: selectedRole,
                    permissions: updated,
                    organizationId: organizationId
                )
            } else {
                success = await viewModel.updateMemberAccess(
                    memberId: member.user_id,
                    role: selectedRole,
                    permissions: updated,
                    organizationId: organizationId
                )
            }

            if success {
                await viewModel.fetchTeam(organizationId: organizationId)
                dismiss()
            }
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("team_member_section_title".localizedString)) {
                    Text(member.member_email ?? "User")
                        .font(.headline)
                    Text(isInvite ? "team_member_status_pending".localizedString : "team_member_status_active".localizedString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("team_role_section_title".localizedString)) {
                    Picker("team_role_section_title".localizedString, selection: $selectedRole) {
                        ForEach(PermissionCatalog.roles, id: \.self) { role in
                            Text(role.capitalized).tag(role)
                        }
                    }
                    Text(PermissionCatalog.roleSummary(for: selectedRole))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("team_access_section_title".localizedString)) {
                    ForEach(PermissionCatalog.groups) { group in
                        PermissionToggleRow(
                            title: group.primary.titleKey.localizedString,
                            detail: group.primary.detailKey.localizedString,
                            systemImage: group.primary.systemImage,
                            isOn: Binding(
                                get: { permissions[group.primary.key.rawValue] ?? false },
                                set: { permissions[group.primary.key.rawValue] = $0 }
                            )
                        )

                        if let detailTitleKey = group.detailTitleKey, !group.detailItems.isEmpty {
                            DisclosureGroup(detailTitleKey.localizedString) {
                                ForEach(group.detailItems) { item in
                                    PermissionToggleRow(
                                        title: item.titleKey.localizedString,
                                        detail: item.detailKey.localizedString,
                                        systemImage: item.systemImage,
                                        isOn: Binding(
                                            get: { permissions[item.key.rawValue] ?? false },
                                            set: { permissions[item.key.rawValue] = $0 }
                                        )
                                    )
                                    .padding(.leading, 8)
                                }
                            }
                        }
                    }

                    Button("team_access_reset_role_defaults".localizedString) {
                        applyRoleDefaults()
                    }
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("team_manage_access_title".localizedString)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localizedString) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save".localizedString) {
                        saveChanges()
                    }
                    .disabled(organizationId == nil || viewModel.isLoading)
                }
            }
            .onAppear {
                permissions = PermissionCatalog.resolvedPermissions(member.permissions, role: selectedRole)
            }
            .onChange(of: selectedRole) { _, _ in
                applyRoleDefaults()
            }
        }
    }
}

struct PermissionToggleRow: View {
    let title: String
    let detail: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundColor(ColorTheme.primary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct CredentialsSheet: View {
    let credentials: GeneratedCredentials
    @Environment(\.dismiss) private var dismiss
    @State private var copiedEmail = false
    @State private var copiedPassword = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Text(credentials.email)
                            .font(.body)
                        Spacer()
                        Button(copiedEmail ? "Copied" : "Copy") {
                            UIPasteboard.general.string = credentials.email
                            copiedEmail = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Text(credentials.password)
                            .font(.body)
                        Spacer()
                        Button(copiedPassword ? "Copied" : "Copy") {
                            UIPasteboard.general.string = credentials.password
                            copiedPassword = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Text("This password is shown once. Share it securely and ask the member to change it after signing in.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Login Credentials")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
