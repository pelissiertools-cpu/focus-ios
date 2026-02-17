//
//  SignUpView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI
import AuthenticationServices
import GoogleSignIn

struct SignUpView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authService: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Create Account")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 40)

                Spacer()

                // Email Field
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .disabled(authService.isLoading)
                    .padding(.horizontal)

                // Password Field
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)
                    .disabled(authService.isLoading)
                    .padding(.horizontal)

                // Confirm Password Field
                SecureField("Confirm Password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)
                    .disabled(authService.isLoading)
                    .padding(.horizontal)

                // Password Match Validation
                if !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
                    Text("Passwords do not match")
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }

                // Error Message
                if let errorMessage = authService.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }

                // Sign Up Button
                Button(action: signUp) {
                    if authService.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Sign Up")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(authService.isLoading || !isFormValid)
                .padding(.horizontal)

                // Divider
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(.secondary.opacity(0.3))
                    Text("or")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(.secondary.opacity(0.3))
                }
                .padding(.horizontal)

                // Continue with Apple
                Button(action: handleAppleSignIn) {
                    HStack(spacing: 8) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 18))
                        Text("Continue with Apple")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(.label))
                    .foregroundColor(Color(.systemBackground))
                    .cornerRadius(10)
                }
                .disabled(authService.isLoading)
                .padding(.horizontal)

                // Continue with Google
                Button(action: handleGoogleSignIn) {
                    HStack(spacing: 8) {
                        Text("G")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [.blue, .green, .yellow, .red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text("Continue with Google")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(.secondarySystemBackground))
                    .foregroundColor(Color(.label))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
                }
                .disabled(authService.isLoading)
                .padding(.horizontal)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(authService.isLoading)
                }
            }
        }
    }

    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && password == confirmPassword && password.count >= 6
    }

    private func signUp() {
        _Concurrency.Task { @MainActor in
            do {
                try await authService.signUp(email: email, password: password)
                dismiss()
            } catch {
                // Error is handled in AuthService
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

                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

                guard let idToken = result.user.idToken?.tokenString else {
                    authService.errorMessage = "Unable to get Google ID token."
                    return
                }

                let accessToken = result.user.accessToken.tokenString
                try await authService.signInWithGoogle(idToken: idToken, accessToken: accessToken)
            } catch {
                // Errors handled in AuthService
            }
        }
    }
}

#Preview {
    SignUpView()
        .environmentObject(AuthService())
}
