//
//  Focus_IOSApp.swift
//  Focus IOS
//
//  Created by Gabriel  on 2026-02-04.
//

import SwiftUI
import GoogleSignIn

@main
struct Focus_IOSApp: App {
    @StateObject private var authService: AuthService
    @StateObject private var focusViewModel: FocusTabViewModel

    init() {
        let auth = AuthService()
        _authService = StateObject(wrappedValue: auth)
        _focusViewModel = StateObject(wrappedValue: FocusTabViewModel(authService: auth))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isAuthenticated {
                    MainTabView()
                        .environmentObject(authService)
                        .environmentObject(focusViewModel)
                } else {
                    SignInView()
                        .environmentObject(authService)
                }
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
