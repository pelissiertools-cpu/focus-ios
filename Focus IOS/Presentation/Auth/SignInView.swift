//
//  SignInView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI
import AuthenticationServices
import GoogleSignIn
import CryptoKit

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
                    .font(.sf(size: 48, weight: .bold))
                    .foregroundColor(.black)

                Spacer()

                // Dark bottom drawer
                VStack(spacing: 12) {
                    // Error Message
                    if let errorMessage = authService.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.sf(.caption))
                            .padding(.horizontal)
                    }

                    // Continue with Apple
                    Button(action: handleAppleSignIn) {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo")
                                .font(.sf(size: 18))
                            Text("Continue with Apple")
                                .font(.sf(.body, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .contentShape(Rectangle())
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
                                .font(.sf(.body, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .contentShape(Rectangle())
                        .background(Color.white.opacity(0.12))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                    .disabled(authService.isLoading)

                    // Sign up
                    Button(action: { showAuth = true }) {
                        Text("Sign up")
                            .font(.sf(.body, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .contentShape(Rectangle())
                            .background(Color.white.opacity(0.12))
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .disabled(authService.isLoading)

                    // Log in
                    Button(action: { showAuth = true }) {
                        Text("Log in")
                            .font(.sf(.body, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .contentShape(Rectangle())
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
                // GIDSignInError.canceled is expected, other errors handled in AuthService
            }
        }
    }
}

// MARK: - Google Logo

struct GoogleLogoView: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 20.0
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -12, y: -12)

            // Blue (#4285F4)
            var blue = Path()
            blue.move(to: CGPoint(x: 31.6, y: 22.2273))
            blue.addCurve(to: CGPoint(x: 31.4182, y: 20.1818), control1: CGPoint(x: 31.6, y: 21.5182), control2: CGPoint(x: 31.5364, y: 20.8364))
            blue.addLine(to: CGPoint(x: 22, y: 20.1818))
            blue.addLine(to: CGPoint(x: 22, y: 24.05))
            blue.addLine(to: CGPoint(x: 27.3818, y: 24.05))
            blue.addCurve(to: CGPoint(x: 25.3864, y: 27.0682), control1: CGPoint(x: 27.15, y: 25.3), control2: CGPoint(x: 26.4455, y: 26.3591))
            blue.addLine(to: CGPoint(x: 25.3864, y: 29.5773))
            blue.addLine(to: CGPoint(x: 28.6182, y: 29.5773))
            blue.addCurve(to: CGPoint(x: 31.6, y: 22.2273), control1: CGPoint(x: 30.5091, y: 27.8364), control2: CGPoint(x: 31.6, y: 25.2727))
            blue.closeSubpath()
            context.fill(blue, with: .color(Color(red: 66/255, green: 133/255, blue: 244/255)))

            // Green (#34A853)
            var green = Path()
            green.move(to: CGPoint(x: 22, y: 32))
            green.addCurve(to: CGPoint(x: 28.6181, y: 29.5773), control1: CGPoint(x: 24.7, y: 32), control2: CGPoint(x: 26.9636, y: 31.1045))
            green.addLine(to: CGPoint(x: 25.3863, y: 27.0682))
            green.addCurve(to: CGPoint(x: 22, y: 28.0227), control1: CGPoint(x: 24.4909, y: 27.6682), control2: CGPoint(x: 23.3454, y: 28.0227))
            green.addCurve(to: CGPoint(x: 16.4045, y: 23.9), control1: CGPoint(x: 19.3954, y: 28.0227), control2: CGPoint(x: 17.1909, y: 26.2636))
            green.addLine(to: CGPoint(x: 13.0636, y: 23.9))
            green.addLine(to: CGPoint(x: 13.0636, y: 26.4909))
            green.addCurve(to: CGPoint(x: 22, y: 32), control1: CGPoint(x: 14.7091, y: 29.7591), control2: CGPoint(x: 18.0909, y: 32))
            green.closeSubpath()
            context.fill(green, with: .color(Color(red: 52/255, green: 168/255, blue: 83/255)))

            // Yellow (#FBBC04)
            var yellow = Path()
            yellow.move(to: CGPoint(x: 16.4045, y: 23.9))
            yellow.addCurve(to: CGPoint(x: 16.0909, y: 22), control1: CGPoint(x: 16.2045, y: 23.3), control2: CGPoint(x: 16.0909, y: 22.6591))
            yellow.addCurve(to: CGPoint(x: 16.4045, y: 20.1), control1: CGPoint(x: 16.0909, y: 21.3409), control2: CGPoint(x: 16.2045, y: 20.7))
            yellow.addLine(to: CGPoint(x: 16.4045, y: 17.5091))
            yellow.addLine(to: CGPoint(x: 13.0636, y: 17.5091))
            yellow.addCurve(to: CGPoint(x: 12, y: 22), control1: CGPoint(x: 12.3864, y: 18.8591), control2: CGPoint(x: 12, y: 20.3864))
            yellow.addCurve(to: CGPoint(x: 13.0636, y: 26.4909), control1: CGPoint(x: 12, y: 23.6136), control2: CGPoint(x: 12.3864, y: 25.1409))
            yellow.addLine(to: CGPoint(x: 16.4045, y: 23.9))
            yellow.closeSubpath()
            context.fill(yellow, with: .color(Color(red: 251/255, green: 188/255, blue: 4/255)))

            // Red (#E94235)
            var red = Path()
            red.move(to: CGPoint(x: 22, y: 15.9773))
            red.addCurve(to: CGPoint(x: 25.8227, y: 17.4727), control1: CGPoint(x: 23.4681, y: 15.9773), control2: CGPoint(x: 24.7863, y: 16.4818))
            red.addLine(to: CGPoint(x: 28.6909, y: 14.6045))
            red.addCurve(to: CGPoint(x: 22, y: 12), control1: CGPoint(x: 26.9591, y: 12.9909), control2: CGPoint(x: 24.6954, y: 12))
            red.addCurve(to: CGPoint(x: 13.0636, y: 17.5091), control1: CGPoint(x: 18.0909, y: 12), control2: CGPoint(x: 14.7091, y: 14.2409))
            red.addLine(to: CGPoint(x: 16.4045, y: 20.1))
            red.addCurve(to: CGPoint(x: 22, y: 15.9773), control1: CGPoint(x: 17.1909, y: 17.7364), control2: CGPoint(x: 19.3954, y: 15.9773))
            red.closeSubpath()
            context.fill(red, with: .color(Color(red: 233/255, green: 66/255, blue: 53/255)))
        }
    }
}

#Preview {
    SignInView()
        .environmentObject(AuthService())
}
