//
//  AuthService.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation
import Supabase
import Combine
import AuthenticationServices
import CryptoKit

/// Service for handling authentication with Supabase
@MainActor
class AuthService: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseClientManager.shared.client) {
        self.supabase = supabase
        Task {
            await checkSession()
        }
    }

    /// Check if there's an active session
    func checkSession() async {
        do {
            let session = try await supabase.auth.session
            self.currentUser = session.user
            self.isAuthenticated = true
        } catch {
            self.isAuthenticated = false
            self.currentUser = nil
        }
    }

    /// Sign up a new user with email and password
    func signUp(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await supabase.auth.signUp(
                email: email,
                password: password
            )

            self.currentUser = response.user
            self.isAuthenticated = true
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Sign in an existing user with email and password
    func signIn(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await supabase.auth.signIn(
                email: email,
                password: password
            )

            self.currentUser = response.user
            self.isAuthenticated = true
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Send a password reset email
    func resetPassword(email: String) async throws {
        isLoading = true
        errorMessage = nil

        do {
            try await supabase.auth.resetPasswordForEmail(email)
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Update the user's email
    func updateEmail(newEmail: String) async throws {
        isLoading = true
        errorMessage = nil

        do {
            self.currentUser = try await supabase.auth.update(user: UserAttributes(email: newEmail))
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Update the user's password
    func updatePassword(newPassword: String) async throws {
        isLoading = true
        errorMessage = nil

        do {
            self.currentUser = try await supabase.auth.update(user: UserAttributes(password: newPassword))
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Sign in with Apple using native AuthenticationServices
    func signInWithApple(idToken: String, nonce: String) async throws {
        isLoading = true
        errorMessage = nil

        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            self.currentUser = session.user
            self.isAuthenticated = true
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Sign in with Google using GoogleSignIn SDK
    func signInWithGoogle(idToken: String, accessToken: String) async throws {
        isLoading = true
        errorMessage = nil

        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .google,
                    idToken: idToken,
                    accessToken: accessToken
                )
            )
            self.currentUser = session.user
            self.isAuthenticated = true
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Sign out the current user
    func signOut() async throws {
        isLoading = true
        errorMessage = nil

        do {
            try await supabase.auth.signOut()
            self.currentUser = nil
            self.isAuthenticated = false
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            throw error
        }
    }
}
