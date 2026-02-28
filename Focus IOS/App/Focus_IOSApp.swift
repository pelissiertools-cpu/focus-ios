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
    @StateObject private var languageManager = LanguageManager.shared
    @StateObject private var appearanceManager = AppearanceManager.shared

    init() {
        let auth = AuthService()
        _authService = StateObject(wrappedValue: auth)
        _focusViewModel = StateObject(wrappedValue: FocusTabViewModel(authService: auth))

        // DEBUG: Print available Inter fonts — remove after testing
        for family in UIFont.familyNames.sorted() where family.contains("Inter") {
            print("Family: \(family)")
            for name in UIFont.fontNames(forFamilyName: family) {
                print("  -> \(name)")
            }
        }
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
            .environmentObject(languageManager)
            .environmentObject(appearanceManager)
            .environment(\.locale, languageManager.locale)
            .preferredColorScheme(appearanceManager.currentAppearance.colorScheme)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
