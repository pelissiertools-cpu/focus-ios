//
//  SettingsView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-17.
//

import SwiftUI
import Auth

struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    // Change email state
    @State private var showChangeEmail = false
    @State private var newEmail = ""
    @State private var emailChangeSuccess = false

    // Change password state
    @State private var showChangePassword = false
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var passwordChangeSuccess = false

    var body: some View {
        List {
            // Account info
            SwiftUI.Section {
                if let email = authService.currentUser?.email {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Email")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(email)
                                .font(.body)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Account management
            SwiftUI.Section("Account") {
                Button {
                    newEmail = ""
                    showChangeEmail = true
                } label: {
                    Label("Change Email", systemImage: "envelope")
                }

                Button {
                    newPassword = ""
                    confirmNewPassword = ""
                    showChangePassword = true
                } label: {
                    Label("Change Password", systemImage: "lock")
                }
            }

            // Sign out
            SwiftUI.Section {
                Button(role: .destructive) {
                    _Concurrency.Task { @MainActor in
                        do {
                            try await authService.signOut()
                        } catch {
                            // Error handled in AuthService
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if authService.isLoading {
                            ProgressView()
                        } else {
                            Text("Sign Out")
                        }
                        Spacer()
                    }
                }
                .disabled(authService.isLoading)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .alert("Change Email", isPresented: $showChangeEmail) {
            TextField("New email", text: $newEmail)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
            Button("Update") {
                _Concurrency.Task { @MainActor in
                    do {
                        try await authService.updateEmail(newEmail: newEmail)
                        emailChangeSuccess = true
                    } catch {
                        // Error handled in AuthService
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter your new email address. You'll receive a confirmation email.")
        }
        .alert("Change Password", isPresented: $showChangePassword) {
            SecureField("New password", text: $newPassword)
            SecureField("Confirm password", text: $confirmNewPassword)
            Button("Update") {
                guard newPassword == confirmNewPassword, newPassword.count >= 6 else {
                    authService.errorMessage = "Passwords must match and be at least 6 characters."
                    return
                }
                _Concurrency.Task { @MainActor in
                    do {
                        try await authService.updatePassword(newPassword: newPassword)
                        passwordChangeSuccess = true
                    } catch {
                        // Error handled in AuthService
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a new password (minimum 6 characters).")
        }
        .alert("Email Updated", isPresented: $emailChangeSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your new email address for a confirmation link.")
        }
        .alert("Password Updated", isPresented: $passwordChangeSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your password has been changed successfully.")
        }
    }
}

#Preview {
    NavigationView {
        SettingsView()
            .environmentObject(AuthService())
    }
}
