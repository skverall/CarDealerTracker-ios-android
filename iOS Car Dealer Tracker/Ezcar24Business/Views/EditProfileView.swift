import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var sessionStore: SessionStore
    
    // Core Data User
    @ObservedObject var user: Ezcar24Business.User
    
    // Form fields
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var phone: String = ""
    @State private var email: String = ""
    
    // Avatar
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarImage: Image?
    @State private var serverAvatarImage: Image?
    @State private var avatarData: Data?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showSuccessAlert = false
    
    var body: some View {
        NavigationView {
            SwiftUI.Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            if let avatarImage {
                                avatarImage
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(ColorTheme.primary, lineWidth: 2))
                            } else if let serverAvatarImage {
                                serverAvatarImage
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(ColorTheme.primary, lineWidth: 2))
                            } else {
                                Circle()
                                    .fill(ColorTheme.primary.opacity(0.1))
                                    .frame(width: 100, height: 100)
                                    .overlay(
                                        Text(getInitials(name: user.name))
                                            .font(.title)
                                            .fontWeight(.bold)
                                            .foregroundColor(ColorTheme.primary)
                                    )
                            }
                            
                            PhotosPicker(selection: $avatarItem, matching: .images) {
                                Text("Change Photo")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical)
                }
                
                Section(header: Text("Personal Information")) {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let pendingEmail = sessionStore.pendingEmailChange {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pending confirmation")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.orange)
                            Text("Check \(pendingEmail) and confirm the link to complete your sign-in email change.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                }
                
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                    }
                    .disabled(isLoading)
                }
            }
            .onAppear {
                firstName = user.firstName ?? ""
                lastName = user.lastName ?? ""
                phone = user.phone ?? ""
                email = resolvedCurrentEmail()
                loadAvatar()
            }
            .onChange(of: avatarItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        let compressedData = uiImage.compressed(maxDimension: 512, compressionQuality: 0.8)
                        let finalData = compressedData ?? data
                        avatarData = finalData
                        if let finalImage = UIImage(data: finalData) {
                            avatarImage = Image(uiImage: finalImage)
                        } else {
                            avatarImage = Image(uiImage: uiImage)
                        }
                    }
                }
            }
            .disabled(isLoading)
            .alert("Profile Updated", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text(successMessage ?? "")
            }
        }
    }
    
    private func saveProfile() {
        let normalizedEmail = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let currentEmail = resolvedCurrentEmail()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let emailChanged = normalizedEmail != currentEmail

        guard !emailChanged || isValidEmail(normalizedEmail) else {
            errorMessage = "Enter a valid email address."
            return
        }

        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        Task {
            var emailChangeMessage: String?
            var shouldPersistEmailLocally = !normalizedEmail.isEmpty && !emailChanged
            var requestedEmailChange = false

            do {
                if emailChanged {
                    let updatedUser = try await sessionStore.updateEmail(normalizedEmail)
                    requestedEmailChange = true

                    let returnedEmail = updatedUser.email?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased() ?? ""
                    let pendingEmail = updatedUser.newEmail?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased() ?? ""

                    if pendingEmail == normalizedEmail && returnedEmail != normalizedEmail {
                        emailChangeMessage = "We sent a confirmation link to \(normalizedEmail). Your sign-in email will switch after you confirm it."
                    } else if returnedEmail == normalizedEmail {
                        emailChangeMessage = "Your account email was updated."
                        shouldPersistEmailLocally = true
                    } else {
                        emailChangeMessage = "Check your inbox to confirm your new email address."
                    }
                }

                // Update local user object
                user.firstName = firstName
                user.lastName = lastName
                user.phone = phone
                if shouldPersistEmailLocally {
                    user.email = normalizedEmail
                }
                
                // Update full name if needed
                if !firstName.isEmpty || !lastName.isEmpty {
                    let fullName = [firstName, lastName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    if !fullName.isEmpty {
                        user.name = fullName
                    }
                }
                
                user.updatedAt = Date()
                
                // Upload avatar if changed
                if let data = avatarData, let userId = user.id, let syncManager = CloudSyncManager.shared {
                    let url = try await syncManager.uploadAvatar(image: data, userId: userId)
                    user.avatarUrl = url
                }
                
                try viewContext.save()

                if let dealerId = sessionStore.activeOrganizationId, let syncManager = CloudSyncManager.shared {
                    await syncManager.upsertUser(user, dealerId: dealerId)
                }

                if let emailChangeMessage {
                    successMessage = emailChangeMessage
                    showSuccessAlert = true
                } else {
                    dismiss()
                }
            } catch {
                if requestedEmailChange {
                    errorMessage = "Email change was requested, but the rest of the profile could not be saved. Reopen the profile and verify the details."
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
        }
    }
    
    private func getInitials(name: String?) -> String {
        guard let name = name, !name.isEmpty else { return "?" }
        let components = name.components(separatedBy: " ")
        if let first = components.first?.first, let last = components.last?.first, components.count > 1 {
            return "\(first)\(last)"
        }
        return String(name.prefix(2)).uppercased()
    }

    private func loadAvatar() {
        guard let userId = user.id, user.avatarUrl != nil else { return }
        
        Task {
            do {
                if let data = try await CloudSyncManager.shared?.downloadAvatar(userId: userId),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        self.serverAvatarImage = Image(uiImage: uiImage)
                    }
                }
            } catch {
                print("Failed to load avatar: \(error)")
            }
        }
    }

    private func resolvedCurrentEmail() -> String {
        if let authEmail = sessionStore.currentAuthEmail {
            return authEmail
        }
        return user.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func isValidEmail(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let regex = "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$"
        return NSPredicate(format: "SELF MATCHES[c] %@", regex).evaluate(with: value)
    }
}
