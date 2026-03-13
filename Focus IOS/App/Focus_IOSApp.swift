//
//  Focus_IOSApp.swift
//  Focus IOS
//
//  Created by Gabriel  on 2026-02-04.
//

import SwiftUI
import GoogleSignIn
import Auth

@main
struct Focus_IOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authService: AuthService
    @StateObject private var focusViewModel: FocusTabViewModel
    @StateObject private var languageManager = LanguageManager.shared
    @StateObject private var appearanceManager = AppearanceManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var coachMarkManager = CoachMarkManager.shared
    @State private var showLaunchScreen = true
    @Environment(\.scenePhase) private var scenePhase

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
            ZStack {
                Group {
                    if authService.isAuthenticated {
                        if authService.hasCompletedOnboarding {
                            MainTabView()
                                .environmentObject(authService)
                                .environmentObject(focusViewModel)
                        } else {
                            OnboardingContainerView()
                                .environmentObject(authService)
                        }
                    } else if !authService.isCheckingSession {
                        SignInView()
                            .environmentObject(authService)
                    }
                }
                .opacity(showLaunchScreen ? 0 : 1)

                if showLaunchScreen {
                    LaunchScreenView()
                        .zIndex(1)
                }
            }
            .task {
                // Hold splash for at least 1.5s, then wait for session check
                async let minDelay: Void? = try? await _Concurrency.Task.sleep(for: .seconds(1.5))
                await authService.waitForSessionCheck()
                _ = await minDelay
                withAnimation(.easeInOut(duration: 0.5)) {
                    showLaunchScreen = false
                }
            }
            .onChange(of: authService.currentUser?.id.uuidString) { _, newId in
                if let userId = newId {
                    coachMarkManager.handleUserSignIn(userId: userId)
                }
            }
            .environmentObject(languageManager)
            .environmentObject(appearanceManager)
            .environmentObject(notificationManager)
            .environmentObject(coachMarkManager)
            .environment(\.locale, languageManager.locale)
            .preferredColorScheme(appearanceManager.currentAppearance.colorScheme)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    _Concurrency.Task { @MainActor in
                        await authService.refreshSession()
                    }
                }
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
