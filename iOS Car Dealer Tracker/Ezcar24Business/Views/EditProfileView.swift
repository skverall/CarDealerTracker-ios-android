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
    
    // Avatar
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarImage: Image?
    @State private var serverAvatarImage: Image?
    @State private var avatarData: Data?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
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
        }
    }
    
    private func saveProfile() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // Update local user object
                user.firstName = firstName
                user.lastName = lastName
                user.phone = phone
                
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
                
                try viewContext.save()
                
                if let dealerId = sessionStore.activeOrganizationId, let syncManager = CloudSyncManager.shared {
                    await syncManager.upsertUser(user, dealerId: dealerId)
                }
                
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
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
}
