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
    @EnvironmentObject var languageManager: LanguageManager
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

    // Language picker state
    @State private var showLanguagePicker = false
    // Appearance picker state
    @State private var showAppearancePicker = false
    @EnvironmentObject var appearanceManager: AppearanceManager

    private var userEmail: String {
        authService.currentUser?.email ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // App branding
                Text("Focus")
                    .font(.sf(size: 48, weight: .bold))
                    .padding(.top, 24)
                    .padding(.bottom, 28)

                // Account section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Account")
                        .font(.sf(.footnote))
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
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                }
                .padding(.horizontal, 16)

                // App section
                VStack(alignment: .leading, spacing: 8) {
                    Text("App")
                        .font(.sf(.footnote))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        // App Language row
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showLanguagePicker.toggle()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "globe")
                                    .font(.sf(.body))
                                    .foregroundStyle(.primary)
                                    .frame(width: 24)

                                Text("App Language")
                                    .font(.sf(.body))

                                Spacer()

                                Text(languageManager.currentLanguage.displayName)
                                    .font(.sf(.body))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Image(systemName: "chevron.right")
                                    .font(.sf(.caption, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(showLanguagePicker ? 90 : 0))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)

                        // Inline language options
                        if showLanguagePicker {
                            ForEach(AppLanguage.allCases) { language in
                                Divider()
                                    .padding(.leading, 44)

                                Button {
                                    languageManager.currentLanguage = language
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showLanguagePicker = false
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Spacer()
                                            .frame(width: 24)

                                        Text(language.displayName)
                                            .font(.sf(.body))
                                            .foregroundStyle(.primary)

                                        Spacer()

                                        if languageManager.currentLanguage == language {
                                            Image(systemName: "checkmark")
                                                .font(.sf(.body, weight: .semibold))
                                                .foregroundColor(Color.appRed)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Divider()
                            .padding(.leading, 44)

                        // Appearance row
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAppearancePicker.toggle()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sun.min")
                                    .font(.sf(.body))
                                    .foregroundStyle(.primary)
                                    .frame(width: 24, alignment: .center)

                                Text("Appearance")
                                    .font(.sf(.body))
                                    .foregroundStyle(.primary)

                                Spacer()

                                Text(appearanceManager.currentAppearance.displayName)
                                    .font(.sf(.body))
                                    .foregroundStyle(.secondary)

                                Image(systemName: "chevron.right")
                                    .font(.sf(.caption, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(showAppearancePicker ? 90 : 0))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)

                        // Inline appearance options
                        if showAppearancePicker {
                            ForEach(AppAppearance.allCases) { appearance in
                                Divider()
                                    .padding(.leading, 44)

                                Button {
                                    appearanceManager.currentAppearance = appearance
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showAppearancePicker = false
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Spacer()
                                            .frame(width: 24)

                                        Text(appearance.displayName)
                                            .font(.sf(.body))
                                            .foregroundStyle(.primary)

                                        Spacer()

                                        if appearanceManager.currentAppearance == appearance {
                                            Image(systemName: "checkmark")
                                                .font(.sf(.body, weight: .semibold))
                                                .foregroundColor(Color.appRed)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
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
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 20)
            }
        }
        .background(Color(.systemBackground))
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
        title: LocalizedStringKey,
        value: String? = nil,
        showChevron: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.sf(.body))
                .foregroundStyle(.primary)
                .frame(width: 24)

            Text(title)
                .font(.sf(.body))

            Spacer()

            if let value {
                Text(value)
                    .font(.sf(.body))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.sf(.caption, weight: .semibold))
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
            .environmentObject(LanguageManager.shared)
    }
}
