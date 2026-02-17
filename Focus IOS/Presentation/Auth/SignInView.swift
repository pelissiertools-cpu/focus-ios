//
//  SignInView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI
import AuthenticationServices
import GoogleSignIn

struct SignInView: View {
    @EnvironmentObject var authService: AuthService
    @State private var showAuth = false

    var body: some View {
        ZStack {
            // White background
            Color.white
                .ignoresSafeArea()

            VStack {
                Spacer()

                // App Title
                Text("Focus")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.black)

                Spacer()

                // Dark bottom drawer
                VStack(spacing: 12) {
                    // Error Message
                    if let errorMessage = authService.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    }

                    // Continue with Apple
                    Button(action: handleAppleSignIn) {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 18))
                            Text("Continue with Apple")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(14)
                    }
                    .disabled(authService.isLoading)

                    // Continue with Google
                    Button(action: handleGoogleSignIn) {
                        HStack(spacing: 8) {
                            GoogleLogoView()
                                .frame(width: 18, height: 18)
                            Text("Continue with Google")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.white.opacity(0.12))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                    .disabled(authService.isLoading)

                    // Sign up
                    Button(action: { showAuth = true }) {
                        Text("Sign up")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.white.opacity(0.12))
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .disabled(authService.isLoading)

                    // Log in
                    Button(action: { showAuth = true }) {
                        Text("Log in")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.clear)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .disabled(authService.isLoading)
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 40)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 24,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 24
                    )
                    .fill(Color.black)
                    .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .sheet(isPresented: $showAuth) {
            AuthSheetView()
                .environmentObject(authService)
                .drawerStyle()
        }
    }

    private func handleAppleSignIn() {
        _Concurrency.Task { @MainActor in
            do {
                let helper = AppleSignInHelper()
                let result = try await helper.signIn()
                try await authService.signInWithApple(idToken: result.idToken, nonce: result.nonce)
            } catch let error as ASAuthorizationError where error.code == .canceled {
                // User canceled — ignore
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
                // GIDSignInError.canceled is expected, other errors handled in AuthService
            }
        }
    }
}

// MARK: - Google Logo

private struct GoogleLogoView: View {
    var body: some View {
        Text("G")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(
                .linearGradient(
                    colors: [.blue, .green, .yellow, .red],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

#Preview {
    SignInView()
        .environmentObject(AuthService())
}
