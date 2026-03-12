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
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authService: AuthService
    @StateObject private var focusViewModel: FocusTabViewModel
    @StateObject private var languageManager = LanguageManager.shared
    @StateObject private var appearanceManager = AppearanceManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var coachMarkManager = CoachMarkManager.shared

    init() {
        let auth = AuthService()
        _authService = StateObject(wrappedValue: auth)
        _focusViewModel = StateObject(wrappedValue: FocusTabViewModel(authService: auth))

        // Permission is now managed via NotificationManager toggle in Settings

        #if DEBUG
        for family in UIFont.familyNames.sorted() where family.contains("Inter") {
            print("Family: \(family)")
            for name in UIFont.fontNames(forFamilyName: family) {
                print("  -> \(name)")
            }
        }
        #endif
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
            .environmentObject(notificationManager)
            .environmentObject(coachMarkManager)
            .environment(\.locale, languageManager.locale)
            .preferredColorScheme(appearanceManager.currentAppearance.colorScheme)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
