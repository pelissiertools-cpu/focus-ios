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

    // Sign out confirmation
    @State private var showSignOutConfirmation = false

    // Edit name state
    @State private var showEditName = false
    @State private var editedName = ""

    // Language picker state
    @State private var showLanguagePicker = false
    // Appearance picker state
    @State private var showAppearancePicker = false
    @EnvironmentObject var appearanceManager: AppearanceManager
    @EnvironmentObject var notificationManager: NotificationManager
    @Environment(\.scenePhase) private var scenePhase

    private var userEmail: String {
        authService.currentUser?.email ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Profile icon + name + edit
                VStack(spacing: AppStyle.Spacing.comfortable) {
                    Image(systemName: "person")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle()
                                .stroke(Color.cardBorder, lineWidth: AppStyle.Border.thin)
                        )

                    if let name = authService.displayName {
                        Text(name)
                            .font(.inter(size: 18, weight: .semiBold))
                            .foregroundColor(.appText)
                    }

                    Button {
                        editedName = authService.displayName ?? ""
                        showEditName = true
                    } label: {
                        Text("Edit profile")
                            .font(.inter(.caption, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, AppStyle.Spacing.content)
                            .padding(.vertical, AppStyle.Spacing.tiny)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppStyle.CornerRadius.pill)
                                    .stroke(Color.cardBorder, lineWidth: AppStyle.Border.standard)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, AppStyle.Spacing.expanded)
                .padding(.bottom, 28)

                // Account section
                VStack(alignment: .leading, spacing: AppStyle.Spacing.compact) {
                    Text("Account")
                        .font(.inter(.footnote))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, AppStyle.Spacing.tiny)

                    VStack(spacing: 0) {
                        // Email row
                        settingsRow(
                            icon: "envelope",
                            title: "Email",
                            value: userEmail
                        )

                        Divider()
                            .padding(.leading, AppStyle.Layout.touchTarget)

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
                            .padding(.leading, AppStyle.Layout.touchTarget)

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
                            .padding(.leading, AppStyle.Layout.touchTarget)

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
                            .padding(.leading, AppStyle.Layout.touchTarget)

                        // Notifications row
                        HStack(spacing: AppStyle.Spacing.comfortable) {
                            Image(systemName: notificationManager.isEnabled ? "bell.badge" : "bell")
                                .font(.inter(.body))
                                .foregroundColor(.appText)
                                .frame(width: AppStyle.Layout.pillButton)

                            Text("Notifications")
                                .font(.inter(.body))
                                .foregroundColor(.appText)

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { notificationManager.isEnabled },
                                set: { newValue in
                                    if newValue {
                                        _Concurrency.Task { @MainActor in
                                            await notificationManager.enableNotifications()
                                        }
                                    } else {
                                        notificationManager.disableNotifications()
                                    }
                                }
                            ))
                            .labelsHidden()
                            .tint(.green)
                        }
                        .padding(.horizontal, AppStyle.Spacing.section)
                        .padding(.vertical, AppStyle.Spacing.content)
                    }
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
                    .cardBorderOverlay()
                    .cardShadow()
                }
                .padding(.horizontal, AppStyle.Spacing.section)

                // App section
                VStack(alignment: .leading, spacing: AppStyle.Spacing.compact) {
                    Text("App")
                        .font(.inter(.footnote))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, AppStyle.Spacing.tiny)

                    VStack(spacing: 0) {
                        // App Language row
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showLanguagePicker.toggle()
                            }
                        } label: {
                            HStack(spacing: AppStyle.Spacing.comfortable) {
                                Image(systemName: "globe")
                                    .font(.inter(.body))
                                    .foregroundColor(.appText)
                                    .frame(width: AppStyle.Layout.pillButton)

                                Text("App Language")
                                    .font(.inter(.body))
                                    .foregroundColor(.appText)

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
                            .padding(.horizontal, AppStyle.Spacing.section)
                            .padding(.vertical, AppStyle.Spacing.content)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Inline language options
                        if showLanguagePicker {
                            ForEach(AppLanguage.allCases) { language in
                                Divider()
                                    .padding(.leading, AppStyle.Layout.touchTarget)

                                Button {
                                    languageManager.currentLanguage = language
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showLanguagePicker = false
                                    }
                                } label: {
                                    HStack(spacing: AppStyle.Spacing.comfortable) {
                                        Spacer()
                                            .frame(width: AppStyle.Layout.pillButton)

                                        Text(language.displayName)
                                            .font(.inter(.body))
                                            .foregroundColor(.appText)

                                        Spacer()

                                        if languageManager.currentLanguage == language {
                                            Image(systemName: "checkmark")
                                                .font(.inter(.body, weight: .semiBold))
                                                .foregroundColor(Color.appRed)
                                        }
                                    }
                                    .padding(.horizontal, AppStyle.Spacing.section)
                                    .padding(.vertical, AppStyle.Spacing.comfortable)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Divider()
                            .padding(.leading, AppStyle.Layout.touchTarget)

                        // Appearance row
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAppearancePicker.toggle()
                            }
                        } label: {
                            HStack(spacing: AppStyle.Spacing.comfortable) {
                                Image(systemName: "sun.min")
                                    .font(.inter(.body))
                                    .foregroundColor(.appText)
                                    .frame(width: AppStyle.Layout.pillButton, alignment: .center)

                                Text("Appearance")
                                    .font(.inter(.body))
                                    .foregroundColor(.appText)

                                Spacer()

                                Text(appearanceManager.currentAppearance.displayName)
                                    .font(.inter(.body))
                                    .foregroundStyle(.secondary)

                                Image(systemName: "chevron.right")
                                    .font(.inter(.caption, weight: .semiBold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(showAppearancePicker ? 90 : 0))
                            }
                            .padding(.horizontal, AppStyle.Spacing.section)
                            .padding(.vertical, AppStyle.Spacing.content)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Inline appearance options
                        if showAppearancePicker {
                            ForEach(AppAppearance.allCases) { appearance in
                                Divider()
                                    .padding(.leading, AppStyle.Layout.touchTarget)

                                Button {
                                    appearanceManager.currentAppearance = appearance
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showAppearancePicker = false
                                    }
                                } label: {
                                    HStack(spacing: AppStyle.Spacing.comfortable) {
                                        Spacer()
                                            .frame(width: AppStyle.Layout.pillButton)

                                        Text(appearance.displayName)
                                            .font(.inter(.body))
                                            .foregroundColor(.appText)

                                        Spacer()

                                        if appearanceManager.currentAppearance == appearance {
                                            Image(systemName: "checkmark")
                                                .font(.inter(.body, weight: .semiBold))
                                                .foregroundColor(Color.appRed)
                                        }
                                    }
                                    .padding(.horizontal, AppStyle.Spacing.section)
                                    .padding(.vertical, AppStyle.Spacing.comfortable)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
                    .cardBorderOverlay()
                    .cardShadow()
                }
                .padding(.horizontal, AppStyle.Spacing.section)
                .padding(.top, AppStyle.Spacing.page)

                // Sign Out
                VStack(spacing: 0) {
                    Button {
                        showSignOutConfirmation = true
                    } label: {
                        HStack(spacing: AppStyle.Spacing.comfortable) {
                            if authService.isLoading {
                                ProgressView()
                                    .frame(width: AppStyle.Layout.pillButton)
                            } else {
                                Image("SignOutIcon")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .foregroundColor(.red)
                                    .frame(width: AppStyle.Layout.pillButton)

                                Text("Sign Out")
                                    .font(.inter(.body))
                                    .foregroundColor(.red)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, AppStyle.Spacing.section)
                        .padding(.vertical, AppStyle.Spacing.content)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(authService.isLoading)
                }
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
                .cardBorderOverlay()
                .cardShadow()
                .padding(.horizontal, AppStyle.Spacing.section)
                .padding(.top, AppStyle.Spacing.page)
            }
        }
        .background(Color.appBackground)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if showEditName {
                SettingsAlertOverlay(
                    title: "Edit Name",
                    message: "This name will be displayed on your profile.",
                    isPresented: $showEditName
                ) {
                    TextField("Your name", text: $editedName)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                } onUpdate: {
                    let trimmed = editedName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    _Concurrency.Task { @MainActor in
                        do {
                            try await authService.updateDisplayName(trimmed)
                            showEditName = false
                        } catch {
                            // Error handled in AuthService
                        }
                    }
                } hasInput: {
                    !editedName.trimmingCharacters(in: .whitespaces).isEmpty
                }
            }

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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                notificationManager.checkSystemAuthorization()
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
        .alert("Signing out of Focus", isPresented: $showSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Yes", role: .destructive) {
                _Concurrency.Task { @MainActor in
                    do {
                        try await authService.signOut()
                    } catch {
                        // Error handled in AuthService
                    }
                }
            }
        } message: {
            Text(userEmail)
        }
    }

    // MARK: - Row Builder

    private func settingsRow(
        icon: String,
        title: LocalizedStringKey,
        value: String? = nil,
        showChevron: Bool = false
    ) -> some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            Image(systemName: icon)
                .font(.inter(.body))
                .foregroundColor(.appText)
                .frame(width: AppStyle.Layout.pillButton)

            Text(title)
                .font(.inter(.body))
                .foregroundColor(.appText)

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
        .padding(.horizontal, AppStyle.Spacing.section)
        .padding(.vertical, AppStyle.Spacing.content)
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
                VStack(spacing: AppStyle.Spacing.tiny) {
                    Text(title)
                        .font(.inter(.headline))
                    Text(message)
                        .font(.inter(.caption))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, AppStyle.Spacing.page)
                .padding(.horizontal, AppStyle.Spacing.section)
                .padding(.bottom, AppStyle.Spacing.section)

                // Text fields
                VStack(spacing: AppStyle.Spacing.compact) {
                    fields()
                }
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, AppStyle.Spacing.section)
                .padding(.bottom, AppStyle.Spacing.section)

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
                            .padding(.vertical, AppStyle.Spacing.comfortable)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .frame(height: AppStyle.Layout.touchTarget)

                    Button(action: onUpdate) {
                        Text("Update")
                            .font(.inter(.body, weight: hasInput() ? .semiBold : .regular))
                            .foregroundColor(hasInput() ? Color.appRed : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppStyle.Spacing.comfortable)
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
            .environmentObject(NotificationManager.shared)
    }
}
