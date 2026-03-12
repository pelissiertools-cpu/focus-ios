//
//  MainTabView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @StateObject private var homeViewModel = HomeViewModel()

    var body: some View {
        TabView {
            HomeView(viewModel: homeViewModel, authService: authService)
                .environmentObject(focusViewModel)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            OnboardingContainerView()
                .tabItem {
                    Label("Onboarding", systemImage: "sparkles")
                }
        }
    }
}

#Preview {
    let auth = AuthService()
    MainTabView()
        .environmentObject(auth)
        .environmentObject(FocusTabViewModel(authService: auth))
}
