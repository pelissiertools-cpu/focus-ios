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
                    .font(.inter(size: 48, weight: .bold))
                    .padding(.top, 24)
                    .padding(.bottom, 28)

                // Account section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Account")
                        .font(.inter(.footnote))
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
                        .font(.inter(.footnote))
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
                                    .font(.inter(.body))
                                    .foregroundStyle(.primary)
                                    .frame(width: 24)

                                Text("App Language")
                                    .font(.inter(.body))

                                Spacer()

                                Text(languageManager.currentLanguage.displayName)
                                    .font(.inter(.body))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Image(systemName: "chevron.right")
                                    .font(.inter(.caption, weight: .semiBold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(showLanguagePicker ? 90 : 0))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
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
                                            .font(.inter(.body))
                                            .foregroundStyle(.primary)

                                        Spacer()

                                        if languageManager.currentLanguage == language {
                                            Image(systemName: "checkmark")
                                                .font(.inter(.body, weight: .semiBold))
                                                .foregroundColor(Color.appRed)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
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
                                    .font(.inter(.body))
                                    .foregroundStyle(.primary)
                                    .frame(width: 24, alignment: .center)

                                Text("Appearance")
                                    .font(.inter(.body))
                                    .foregroundStyle(.primary)

                                Spacer()

                                Text(appearanceManager.currentAppearance.displayName)
                                    .font(.inter(.body))
                                    .foregroundStyle(.secondary)

                                Image(systemName: "chevron.right")
                                    .font(.inter(.caption, weight: .semiBold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(showAppearancePicker ? 90 : 0))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
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
                                            .font(.inter(.body))
                                            .foregroundStyle(.primary)

                                        Spacer()

                                        if appearanceManager.currentAppearance == appearance {
                                            Image(systemName: "checkmark")
                                                .font(.inter(.body, weight: .semiBold))
                                                .foregroundColor(Color.appRed)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
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
        .background(Color.appBackground)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if showChangeEmail {
                SettingsAlertOverlay(
                    title: "Change Email",
                    message: "Enter your new email address. You'll receive a confirmation email.",
                    isPresented: $showChangeEmail
                ) {
                    TextField("New email", text: $newEmail)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                } onUpdate: {
                    _Concurrency.Task { @MainActor in
                        do {
                            try await authService.updateEmail(newEmail: newEmail)
                            showChangeEmail = false
                            emailChangeSuccess = true
                        } catch {
                            // Error handled in AuthService
                        }
                    }
                } hasInput: {
                    !newEmail.trimmingCharacters(in: .whitespaces).isEmpty
                }
            }

            if showChangePassword {
                SettingsAlertOverlay(
                    title: "Change Password",
                    message: "Enter a new password (minimum 6 characters).",
                    isPresented: $showChangePassword
                ) {
                    SecureField("New password", text: $newPassword)
                    SecureField("Confirm password", text: $confirmNewPassword)
                } onUpdate: {
                    guard newPassword == confirmNewPassword, newPassword.count >= 6 else {
                        authService.errorMessage = "Passwords must match and be at least 6 characters."
                        return
                    }
                    _Concurrency.Task { @MainActor in
                        do {
                            try await authService.updatePassword(newPassword: newPassword)
                            showChangePassword = false
                            passwordChangeSuccess = true
                        } catch {
                            // Error handled in AuthService
                        }
                    }
                } hasInput: {
                    !newPassword.isEmpty
                }
            }
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
                .font(.inter(.body))
                .foregroundStyle(.primary)
                .frame(width: 24)

            Text(title)
                .font(.inter(.body))

            Spacer()

            if let value {
                Text(value)
                    .font(.inter(.body))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.inter(.caption, weight: .semiBold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Custom Alert Overlay

private struct SettingsAlertOverlay<Fields: View>: View {
    let title: String
    let message: String
    @Binding var isPresented: Bool
    @ViewBuilder let fields: () -> Fields
    let onUpdate: () -> Void
    let hasInput: () -> Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(spacing: 0) {
                // Title + message
                VStack(spacing: 4) {
                    Text(title)
                        .font(.inter(.headline))
                    Text(message)
                        .font(.inter(.caption))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

                // Text fields
                VStack(spacing: 8) {
                    fields()
                }
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

                Divider()

                // Buttons
                HStack(spacing: 0) {
                    Button {
                        isPresented = false
                    } label: {
                        Text("Cancel")
                            .font(.inter(.body))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .frame(height: 44)

                    Button(action: onUpdate) {
                        Text("Update")
                            .font(.inter(.body, weight: hasInput() ? .semiBold : .regular))
                            .foregroundColor(hasInput() ? Color.appRed : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .frame(width: 270)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: isPresented)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AuthService())
            .environmentObject(LanguageManager.shared)
    }
}
