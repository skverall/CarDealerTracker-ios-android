import SwiftUI

struct PasswordResetView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isProcessing = false
    @State private var showSuccess = false
    @State private var showNewPassword = false
    @State private var showConfirmPassword = false
    @FocusState private var focusedField: Field?
    
    private enum Field {
        case newPassword
        case confirmPassword
    }
    
    private var isValid: Bool {
        !newPassword.isEmpty && 
        newPassword.count >= 6 && 
        newPassword == confirmPassword
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "lock.rotation")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Reset Password")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Create a new password to regain access. You'll sign in again after saving.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                // Password fields
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("New Password")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            if showNewPassword {
                                TextField("At least 6 characters", text: $newPassword)
                                    .textContentType(.newPassword)
                                    .focused($focusedField, equals: .newPassword)
                            } else {
                                SecureField("At least 6 characters", text: $newPassword)
                                    .textContentType(.newPassword)
                                    .focused($focusedField, equals: .newPassword)
                            }
                            
                            Button(action: { showNewPassword.toggle() }) {
                                Image(systemName: showNewPassword ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Password")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            if showConfirmPassword {
                                TextField("Re-enter password", text: $confirmPassword)
                                    .textContentType(.newPassword)
                                    .focused($focusedField, equals: .confirmPassword)
                            } else {
                                SecureField("Re-enter password", text: $confirmPassword)
                                    .textContentType(.newPassword)
                                    .focused($focusedField, equals: .confirmPassword)
                            }
                            
                            Button(action: { showConfirmPassword.toggle() }) {
                                Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        
                        if !confirmPassword.isEmpty && newPassword != confirmPassword {
                            Text("Passwords do not match")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Update button
                Button(action: updatePassword) {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }
                        Text(isProcessing ? "Updating..." : "Update Password")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValid ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(!isValid || isProcessing)
                .padding(.horizontal)
                
                if let errorMessage = sessionStore.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        Task {
                            await sessionStore.cancelPasswordRecoveryFlow()
                        }
                    }
                }
                
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .alert("Password Updated", isPresented: $showSuccess) {
                Button("OK") {
                    sessionStore.dismissPasswordResetUI()
                }
            } message: {
                Text("Your password has been updated. Please sign in with your new password to continue.")
            }
        }
    }
    
    private func updatePassword() {
        guard isValid else { return }
        
        isProcessing = true
        
        Task {
            do {
                try await sessionStore.completePasswordRecovery(newPassword: newPassword)
                await MainActor.run {
                    isProcessing = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    // Error is already set in sessionStore
                }
            }
        }
    }
}
