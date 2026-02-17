//
//  SignInView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct SignInView: View {
    @EnvironmentObject var authService: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false
    @State private var showForgotPassword = false
    @State private var resetEmailSent = false
    @State private var forgotPasswordEmail = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()

                // App Title
                Text("Focus")
                    .font(.system(size: 48, weight: .bold))
                    .padding(.bottom, 40)

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
                    .textContentType(.password)
                    .disabled(authService.isLoading)
                    .padding(.horizontal)

                // Forgot Password
                HStack {
                    Spacer()
                    Button("Forgot Password?") {
                        forgotPasswordEmail = email
                        showForgotPassword = true
                    }
                    .font(.subheadline)
                    .disabled(authService.isLoading)
                }
                .padding(.horizontal)

                // Error Message
                if let errorMessage = authService.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }

                // Sign In Button
                Button(action: signIn) {
                    if authService.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Sign In")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(authService.isLoading || email.isEmpty || password.isEmpty)
                .padding(.horizontal)

                // Sign Up Button
                Button(action: { showSignUp = true }) {
                    Text("Don't have an account? Sign Up")
                        .font(.subheadline)
                }
                .disabled(authService.isLoading)

                Spacer()
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSignUp) {
                SignUpView()
                    .environmentObject(authService)
                    .drawerStyle()
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
                        } catch {
                            // Error handled in AuthService
                        }
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
    }

    private func signIn() {
        Task {
            do {
                try await authService.signIn(email: email, password: password)
            } catch {
                // Error is handled in AuthService
            }
        }
    }
}

#Preview {
    SignInView()
        .environmentObject(AuthService())
}
