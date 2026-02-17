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

    private var userEmail: String {
        authService.currentUser?.email ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // App branding
                Text("Focus")
                    .font(.system(size: 48, weight: .bold))
                    .padding(.top, 24)
                    .padding(.bottom, 28)

                // Account section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Account")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        // Email row
                        settingsRow(
                            icon: "envelope",
                            title: "Email",
                            value: userEmail
                        )

                        Divider()
                            .padding(.leading, 44)

                        // Change Email row
                        Button {
                            newEmail = ""
                            showChangeEmail = true
                        } label: {
                            settingsRow(
                                icon: "envelope.badge",
                                title: "Change Email",
                                showChevron: true
                            )
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 44)

                        // Change Password row
                        Button {
                            newPassword = ""
                            confirmNewPassword = ""
                            showChangePassword = true
                        } label: {
                            settingsRow(
                                icon: "lock",
                                title: "Change Password",
                                showChevron: true
                            )
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 44)

                        // Subscription row
                        Button {
                            // Placeholder
                        } label: {
                            settingsRow(
                                icon: "plus.app",
                                title: "Subscription",
                                showChevron: true
                            )
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 44)

                        // Notifications row
                        Button {
                            // Placeholder
                        } label: {
                            settingsRow(
                                icon: "bell",
                                title: "Notifications",
                                showChevron: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)

                // App section
                VStack(alignment: .leading, spacing: 8) {
                    Text("App")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        // App Language row
                        Button {
                            // Placeholder
                        } label: {
                            settingsRow(
                                icon: "globe",
                                title: "App Language",
                                value: "English",
                                showChevron: true
                            )
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 44)

                        // Appearance row
                        Button {
                            // Placeholder
                        } label: {
                            settingsRow(
                                icon: "sun.min",
                                title: "Appearance",
                                value: "System",
                                showChevron: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)

                // Sign Out
                VStack(spacing: 0) {
                    Button {
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
                                    .foregroundColor(.red)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                    }
                    .disabled(authService.isLoading)
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 20)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Row Builder

    private func settingsRow(
        icon: String,
        title: String,
        value: String? = nil,
        showChevron: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(width: 24)

            Text(title)
                .font(.body)

            Spacer()

            if let value {
                Text(value)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    NavigationView {
        SettingsView()
            .environmentObject(AuthService())
    }
}
