//
//  AuthSheetView.swift
//  Focus IOS
//

import SwiftUI
import AuthenticationServices
import GoogleSignIn
import CryptoKit

enum AuthMode {
    case logIn
    case signUp
}

struct AuthSheetView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authService: AuthService

    @State private var step = 1
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showForgotPassword = false
    @State private var resetEmailSent = false
    @State private var forgotPasswordEmail = ""
    @State private var detectedMode: AuthMode = .signUp
    @State private var isCheckingEmail = false

    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Top bar spacer for buttons
                    Color.clear.frame(height: 24)

                    // Logo
                    Image(systemName: "target")
                        .font(.sf(size: 40))
                        .foregroundColor(.primary)
                        .padding(.top, 8)

                    if step == 1 {
                        emailStep
                    } else {
                        passwordStep
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)

            // Top bar overlay
            HStack {
                if step == 2 {
                    Button(action: { withAnimation { step = 1 } }) {
                        Image(systemName: "chevron.left")
                            .font(.sf(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.sf(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                emailFocused = true
            }
        }
        .alert("Reset Password", isPresented: $showForgotPassword) {
            TextField("Email", text: $forgotPasswordEmail)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
            Button("Send Reset Link") {
                _Concurrency.Task { @MainActor in
                    do {
                        try await authService.resetPassword(email: forgotPasswordEmail)
                        resetEmailSent = true
                    } catch {}
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter your email address and we'll send you a link to reset your password.")
        }
        .alert("Email Sent", isPresented: $resetEmailSent) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your inbox for a password reset link.")
        }
    }

    // MARK: - Step 1: Email

    private var emailStep: some View {
        VStack(spacing: 16) {
            // Title
            Text("Log in or sign up")
                .font(.sf(.title2, weight: .bold))

            // Subtitle
            Text("Enter your email to get started")
                .font(.sf(.subheadline))
                .foregroundStyle(.secondary)

            // Email field
            VStack(alignment: .leading, spacing: 6) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .focused($emailFocused)
                    .disabled(authService.isLoading)
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(emailFocused ? Color.primary : Color(.separator), lineWidth: emailFocused ? 2 : 1)
                    )
            }
            .padding(.top, 8)

            // Error
            if let errorMessage = authService.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.sf(.caption))
            }

            // Continue button
            Button(action: {
                _Concurrency.Task { @MainActor in
                    isCheckingEmail = true
                    let exists = await authService.checkEmailExists(email: email)
                    detectedMode = exists ? .logIn : .signUp
                    isCheckingEmail = false
                    withAnimation {
                        step = 2
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            passwordFocused = true
                        }
                    }
                }
            }) {
                Group {
                    if isCheckingEmail {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Continue")
                            .font(.sf(.body, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .contentShape(Rectangle())
            }
            .background(email.isEmpty ? Color(.systemGray4) : Color.black)
            .foregroundColor(.white)
            .cornerRadius(25)
            .disabled(email.isEmpty || isCheckingEmail || authService.isLoading)

            // OR divider
            HStack {
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(Color(.separator))
                Text("OR")
                    .font(.sf(.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(Color(.separator))
            }
            .padding(.vertical, 4)

            // Continue with Google
            Button(action: handleGoogleSignIn) {
                HStack(spacing: 8) {
                    GoogleLogoView()
                        .frame(width: 18, height: 18)
                    Text("Continue with Google")
                        .font(.sf(.body, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .contentShape(Rectangle())
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
            .disabled(authService.isLoading)

            // Continue with Apple
            Button(action: handleAppleSignIn) {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                        .font(.sf(size: 18))
                    Text("Continue with Apple")
                        .font(.sf(.body, weight: .semibold))
                }
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .contentShape(Rectangle())
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
            .disabled(authService.isLoading)
        }
    }

    // MARK: - Step 2: Password

    private var passwordStep: some View {
        VStack(spacing: 16) {
            // Title
            Text(detectedMode == .logIn ? "Welcome back" : "Create your account")
                .font(.sf(.title2, weight: .bold))

            // Subtitle
            Text(detectedMode == .logIn
                 ? "Enter your password to continue"
                 : "Set your password for Focus to continue")
                .font(.sf(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Email (editable — user can fix typos)
            VStack(alignment: .leading, spacing: 6) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .disabled(authService.isLoading)
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
            }
            .padding(.top, 8)

            // Password field
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if showPassword {
                        TextField("Password", text: $password)
                            .textContentType(detectedMode == .logIn ? .password : .newPassword)
                            .focused($passwordFocused)
                    } else {
                        SecureField("Password", text: $password)
                            .textContentType(detectedMode == .logIn ? .password : .newPassword)
                            .focused($passwordFocused)
                    }

                    Button(action: { showPassword.toggle() }) {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(authService.isLoading)
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(passwordFocused ? Color.primary : Color(.separator), lineWidth: passwordFocused ? 2 : 1)
                )
            }

            // Error
            if let errorMessage = authService.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.sf(.caption))
            }

            // Continue button
            Button(action: handleAuth) {
                Group {
                    if authService.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Continue")
                            .font(.sf(.body, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .contentShape(Rectangle())
            }
            .background(password.isEmpty ? Color(.systemGray4) : Color.black)
            .foregroundColor(.white)
            .cornerRadius(25)
            .disabled(password.isEmpty || authService.isLoading)

            // Forgot password (log in only)
            if detectedMode == .logIn {
                Button("Forgot password?") {
                    forgotPasswordEmail = email
                    showForgotPassword = true
                }
                .font(.sf(.subheadline))
                .disabled(authService.isLoading)
            }
        }
    }

    // MARK: - Actions

    private func handleAuth() {
        _Concurrency.Task { @MainActor in
            do {
                if detectedMode == .logIn {
                    try await authService.signIn(email: email, password: password)
                } else {
                    try await authService.signUp(email: email, password: password)
                }
                dismiss()
            } catch {
                // Error handled in AuthService
            }
        }
    }

    private func handleAppleSignIn() {
        _Concurrency.Task { @MainActor in
            do {
                let helper = AppleSignInHelper()
                let result = try await helper.signIn()
                try await authService.signInWithApple(idToken: result.idToken, nonce: result.nonce)
            } catch let error as ASAuthorizationError where error.code == .canceled {
                // User canceled
            } catch {
                // Other errors handled in AuthService
            }
        }
    }

    private func handleGoogleSignIn() {
        _Concurrency.Task { @MainActor in
            do {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let rootViewController = windowScene.windows.first?.rootViewController else {
                    return
                }

                let nonce = NonceHelper.randomNonceString()
                let hashedNonce = NonceHelper.sha256(nonce)

                let result = try await GIDSignIn.sharedInstance.signIn(
                    withPresenting: rootViewController,
                    hint: nil,
                    additionalScopes: nil,
                    nonce: hashedNonce
                )

                guard let idToken = result.user.idToken?.tokenString else {
                    authService.errorMessage = "Unable to get Google ID token."
                    return
                }

                let accessToken = result.user.accessToken.tokenString
                try await authService.signInWithGoogle(idToken: idToken, accessToken: accessToken, nonce: nonce)
            } catch {
                // Errors handled in AuthService
            }
        }
    }
}
